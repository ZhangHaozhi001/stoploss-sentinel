# M2 REPORT — StopLoss Sentinel（测试网部署 & 首个全环路）

执行时间：2026-11-18（节点 11-28，提前 10 天开工）。结论：**部署脚本与全流程已就绪并在双链分叉上彩排通过；真实测试网部署卡在一步人工动作——给测试钱包领 Base Sepolia ETH 的水龙头全部要求账号/浏览器验证，无法程序化完成（详见 §2）。钱包注资到位后，`bash script/run-m2.sh` 一条命令即可无人值守跑完 M2 剩余全部步骤。**

全程只用测试网与代理自管测试钱包，未碰用户钱包、未花主网资金、未注册/提交 DoraHacks。

## 1. M1 提交推送 ✅

- 待提交改动先做密钥扫描：全仓 grep `PRIVATE_KEY|mnemonic|seed phrase` 与 64 位 hex 串，无命中（仅系统合约地址等公开常量）；无 .env / wallet 文件混入。
- 提交 `4417142`「M1: complete contracts + 47-test suite…」共 18 个文件，已推送至 https://github.com/ZhangHaozhi001/stoploss-sentinel （69a4076..4417142）。
- 附带修复：仓库级 git 身份缺失（本机环境未配置）——已在本仓库内设置 user.name/email 后提交；`hidden_files/` 已加入 .gitignore。

## 2. 测试钱包与领水 ⚠️ 卡点（需人工/浏览器一步）

- 代理自管测试钱包已建：地址 **0x6ae9e830E7AB6215649863Bc7cA7f83d74f9b314**；私钥只存 `hidden_files/test-wallet.txt`（0600，目录 0700，已 gitignore），未进仓库、未回传明文。当前余额：Base Sepolia 0 ETH、Lasna 0 lREACT。
- **Lasna lREACT 不是网页水龙头**（官方文档 "Reactive Mainnet & Lasna Testnet" 页，2026-11-18 实读）：是链上兑换合约——向 Ethereum Sepolia `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434` 或 Base Sepolia `0x2afaFD298b23b62760711756088F75B7409f5967` 调 `request(address)` 并附 ETH，1 ETH → 100 lREACT。**只要 Base Sepolia ETH 到位，这一步可全程序化**（run-m2.sh 第 0 步已实现：附 0.1 ETH 换 10 lREACT）。
- **Base Sepolia ETH 水龙头逐一核实，全部被人工/账号环节挡住**：
  - Chainlink（faucets.chain.link/base-sepolia）：必须浏览器内连接钱包（MetaMask/WalletConnect）才能领，无公开 API 路径。
  - QuickNode（faucet.quicknode.com/base/sepolia）：网页 bot 验证 + **要求领取钱包自带少量以太坊主网余额**——与本任务「不花主网资金」硬限制直接冲突，新测试钱包主网余额为 0。
  - Coinbase CDP / Alchemy / Chainstack / Bware 等：均需先注册账号登录。
  - Superchain Faucet（app.optimism.io）：需 GitHub OAuth 身份证明。
- 按任务书口径：领水停在这一步、不绕验证。**解卡动作（任选其一，均给地址 0x6ae9e830E7AB6215649863Bc7cA7f83d74f9b314 领 ≥0.2 ETH）**：① 有浏览器能力的流程打开 Chainlink 水龙头页连接任意钱包领 Base Sepolia ETH + LINK 页面的 ETH drip；② 用已有 Coinbase/Alchemy 账号在其水龙头页填该地址领取。注资后运行 `bash script/run-m2.sh` 即自动完成兑换、部署、接线、触发与回调轮询。

## 3. 部署脚本 ✅ + 分叉彩排 ✅（真实部署待注资）

脚本（`script/`，参数全走环境变量，私钥只从 hidden_files 读）：

| 脚本 | 链 | 作用 |
|---|---|---|
| `DeployBeacon.s.sol` | Base Sepolia | 部署 PriceBeacon（初始价 2000） |
| `DeploySentinel.s.sol` | Lasna | 部署 SentinelReactive：floor 1500 / ceiling 禁用 / 冷却 300 s，部署时自带 5 lREACT |
| `DeployVault.s.sol` | Base Sepolia | 部署 MockERC20 + GuardedVault（回调代理 0x476F44b11F5C942c58f4c8E3d0300E5710743585），铸 1000、存 100 MOCK 进金库，金库预存 0.05 ETH 付回调账单 |
| `SetVault.s.sol` | Lasna | `sentinel.setVault(vault)` |
| `PostPrice.s.sol` | Base Sepolia | 发价（彩排/实跑各用两次：2100 正常价、1000 跌破价） |
| `run-m2.sh` | 双链 | 总控：余额检查 → lREACT 兑换 → 五步部署/接线/发价 → 轮询金库 frozen/rescueCount → 打印汇总 |

顺序与任务书一致：beacon → sentinel → vault → setVault。M1 遗留的部署前复核项已关闭：2026-11-18 实读官方 Origins & Destinations 页，Base Sepolia 回调代理确为 0x476F44b11F5C942c58f4c8E3d0300E5710743585，与 NOTES 及脚本硬编码一致。

**分叉彩排**（anvil 分叉 Base Sepolia + Lasna 实时链，测试钱包经 anvil_setBalance 注资后用同一批脚本 --broadcast 全程实跑）：

- PriceBeacon → 0x8b417463FA74DF28C46072599d64E084e73281be（分叉地址，仅彩排）
- SentinelReactive → 同址部署于 Lasna 分叉，构造内对**真实系统合约**的 subscribe 未 revert；回读：vault 已接线、余额恰 5 lREACT、floor = 1500
- MockERC20 → 0x2A32Da7F073107E161f3b0ACD01C2Bc875133491；GuardedVault → 0x003704466988143B44242A9359B0B15e13c49F38，金库回读 100 MOCK + 0.05 ETH
- 发价 2100 → 1000 均成功，beacon 回读 price = 1000
- 彩排产物 broadcast/ 已删除，未污染仓库。注：分叉上无人投递反应式回调，三腿的真实跨链投递只能在注资后的实跑中产生——这正是 M2 剩余部分。

**待注资后执行（run-m2.sh 自动完成前四项）**：① 真实部署三合约；② 触发 breach 并抓三腿哈希（origin 发价 tx / Lasna reactive tx / Base 回调 tx，Reactscan + BaseScan 存档）；③ `forge verify-contract --verifier sourcify` 验证三合约（Lasna 5318007 的 Sourcify 支持情况实跑时确认，若不支持则以 Reactscan 的 Sourcify 兼容验证入口替代并记录）；④ 地址+哈希回填 README；⑤ 金库 frozen/rescueCount 与安全地址到账的链上复核。

## 4. 复检

- 加脚本后 `forge build` 通过、`forge test` 仍 **47 passed / 0 failed**（脚本文件不影响测试面）。
- 彩排回读断言全对（见 §3）：接线、哨兵余额 5 lREACT、floor、金库余额、最终价格逐项与脚本参数一致。
- 彩排中发现并修复一个真实缺陷：首版钱包文件是 `cast wallet new` 的无标签输出，与 run-m2.sh 的按标签 grep 不匹配——钱包文件已规范为带标签两行格式，run-m2.sh 改为按 64 位 hex 正则提取私钥，两边对齐。
- README 已同步 M2 状态（Deployment 一节 + Status 行）；PLAN M2 清单逐项对账：领水（卡，§2）、部署脚本（✅）、三腿哈希（待注资）、Sourcify（待注资）、README 回填（待注资，状态行已先行更新）。

## M2 剩余清单（一句话版）

人工给 0x6ae9e830E7AB6215649863Bc7cA7f83d74f9b314 领 ≥0.2 Base Sepolia ETH → `bash script/run-m2.sh` → 抓三腿哈希 + Sourcify 验证 + README 回填 → M2 完成；之后 M3（12-1）从干净钱包重跑取最终哈希。
