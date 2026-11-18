# M1 REPORT — StopLoss Sentinel（合约 + 测试）

完成时间：2026-11-18（节点 11-24，提前 6 天）。执行：子代理独立完成，未注册、未提交、未碰用户钱包、未花任何主网/测试网资金。

## M1 完成范围（对 PLAN 逐项对账）

PLAN M1 定义：「full logic (ceiling trigger, cooldown by timestamp, owner setters, pause/unsubscribe, coverDebt), Foundry unit tests incl. a mock-system harness for react()」。

| PLAN 项 | 状态 | 落点 |
|---|---|---|
| ceiling trigger（上限触发） | ✅ | `SentinelReactive.react`：`price > ceiling` 触发；边界值（恰等于 floor/ceiling）不触发，有专门测试 |
| cooldown by timestamp | ✅ | 按事件携带的 `postedAt` 时间戳比较（不用区块号，合 Base Sepolia 规矩）；冷却内抑制、到期瞬间恢复，均有测试 |
| owner setters | ✅ | RSC：`setRule` / `setVault`；Vault：`setSafeAddress` / `reset`；Beacon：`transferOwnership`；全部 onlyOwner + 事件 + 非 owner 拒绝测试 |
| pause/unsubscribe | ✅ 本轮新增 | RSC `pause()` → 调 `SYSTEM.unsubscribe` 并置 `paused`，`react` 双保险直接返回；`unpause()` 重新 `subscribe`；重复 pause/unpause 分别 revert（AlreadyPaused/NotPaused） |
| coverDebt | ✅ | RSC 原有；本轮给 Vault 也补了 `coverDebt()`（回调由接收方付费，vault 对代理的债务同样需要自救入口） |
| mock-system harness for react() | ✅ | `test/mocks/MockSystemContract.sol` 用 `vm.etch` 把替身代码刻到真系统合约地址 0x8888…8888，记录订阅/退订/回调请求与可设债务；哨兵的构造订阅、onlySystem 鉴权、回调请求全程对着替身按真实协议跑 |
| Foundry unit tests | ✅ | 47 个测试，4 个套件，见下 |

## 本轮合约改动（超出 M0 骨架的部分）

1. **SentinelReactive**：新增 `paused` 状态 + `pause()`/`unpause()`（退订/重订 + 事件 + 错误）。
2. **GuardedVault 安全修复（重要）**：骨架的 `executeRescue` 只有 `onlyCallbackSender` 一道校验——任何人只要把第一个参数填成真哨兵地址就能伪造回调、强行冻结并清扫金库（钱扫到 owner 自己的安全地址，不被盗，但属可被任意触发的冻结/骚扰面，且与合约自身文档承诺的「双重校验」不符）。本轮补上 `onlyServiceProvider`（调用方必须是回调代理），与文档对齐，并有专门的伪造回调拒绝测试。
3. **GuardedVault**：新增 `coverDebt()` 外部入口（理由见上表）。
4. **零地址闸（复检加固）**：`GuardedVault` 构造与 `setSafeAddress` 拒绝零安全地址（防救援时把钱扫进黑洞）；`PriceBeacon.transferOwnership` 拒绝零地址（防信标被砖）。`SentinelReactive.setVault` 不设此闸——零地址在 `react` 里已有明确语义（未设 vault 时 breach 直接 revert VaultNotSet）。

## 测试结果（复检口径：干净重建后全量重跑）

`forge clean && forge build` → Compiler run successful；`forge test` → **47 passed, 0 failed, 0 skipped**：

- PriceBeaconTest：7（构造/发价/同值重发事件/权限/所有权转移/零地址闸）
- SentinelReactiveTest：21（构造订阅实参、外部 topic 忽略、非 system 调用拒绝、无 breach 不回调、边界不触发、下限/上限触发含 payload 逐字节布局断言〔selector + address(0) 占位 + 价格〕、冷却抑制与到期、vault 未设 revert、双 bounds 禁用、setters 权限与事件、pause 退订+静默、unpause 重订+恢复、coverDebt 实付）
- GuardedVaultTest：17（存取、转账失败 revert、权限、救援清扫+冻结+事件、零余额救援、**非代理调用方伪造回调拒绝**、错误 sender 拒绝、冻结后存取拒绝、reset 复用、安全地址改向、零地址闸×2、coverDebt 实付）
- FullLoopTest：2（本地全环路彩排：正常价无动作 → 跌破 floor → 哨兵记录回调请求 → 按真实投递方式〔占位符覆写为哨兵地址、由代理调用〕投递 → 金库清扫到安全地址并冻结；以及止盈方向 ceiling 触发全环路）

依赖变化：新增 `lib/forge-std`（v1.17.0）+ foundry.toml remapping 一行。改动均在 git 工作区未提交（仓库当前提交仍是 M0 骨架 69a4076），待主流程统一提交/推送。

## 复检记录

- 干净重建（forge clean 后 build+test）全绿，结果如上，非增量缓存口径。
- forge lint 两条警告已处置：①`Rescued` 事件在外部 transfer 后 emit——合约状态变更（frozen/rescueCount）都在 transfer 之前完成，符合 CEI，仅事件顺序提示，不改；②setSafeAddress 缺零地址检查——已按上文零地址闸修复并加回归测试。
- PLAN 里程碑逐项对账完成（上表）；README 状态行已同步为 M1 完成口径。

## 测试网部署：本轮未做（属 M2，非跳过）

理由：PLAN 与任务书均把部署+真实三腿哈希定在 M2（11-28）；工作区内没有预充值的测试钱包，Lasna 水龙头/Base Sepolia 水龙头领水是 M2 的第一步动作。本轮没有为赶进度牺牲任何测试项。

## M2 遗留清单（11-28 节点）

1. 建代理自管测试钱包 → Lasna 水龙头领 lREACT、Base Sepolia 水龙头领 ETH（RSC 自付 gas、vault 付回调账单，两边都要留余额）。
2. 写部署脚本（`script/` 目前为空）：顺序 beacon → sentinel → vault（构造需哨兵地址）→ `sentinel.setVault(vault)`；哨兵部署需带 lREACT 初始余额。
3. 触发一次 floor breach，抓三腿哈希（origin 发价 tx / Lasna reactive tx / Base 回调 tx），Reactscan + BaseScan 链接存档。
4. 三合约 Sourcify 验证（`forge verify-contract --verifier sourcify`）。
5. 部署后把地址 + 三腿哈希回填 README（已留占位段）。
6. 注意：vault 的回调代理地址用 Base Sepolia 官方值 0x476F44b11F5C942c58f4c8E3d0300E5710743585（NOTES 已记），部署前再核一遍官方文档页。
