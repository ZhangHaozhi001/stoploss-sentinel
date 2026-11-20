# StopLoss Sentinel

**Set a floor once. If the price breaks it, your vault rescues itself — no bot, no keeper, no watching charts.**

A personal stop-loss for a small vault, built with Reactive Smart Contracts for the
[Reactive Omni Buildathon](https://dorahacks.io/hackathon/reactive-omni-buildathon/detail) —
track: **Set It and Forget It**.

## How it works

```
Base Sepolia                     Reactive Lasna                    Base Sepolia
┌─────────────┐   PriceUpdated   ┌──────────────────┐   callback   ┌──────────────┐
│ PriceBeacon │ ───────────────► │ SentinelReactive │ ───────────► │ GuardedVault │
│ (price feed)│   (origin event) │ rule: floor/ceil │  (via SYSTEM │ sweep + freeze│
└─────────────┘                  │ + cooldown       │   proxy)     └──────────────┘
                                 └──────────────────┘
```

1. **PriceBeacon** (`src/PriceBeacon.sol`) — a minimal price poster on Base Sepolia that
   stands in for an oracle feed. Every price post emits `PriceUpdated(int256,uint256)`.
   Using our own beacon keeps the demo deterministic: a breach can be triggered on
   demand, producing the full on-chain loop the judges can verify.
2. **SentinelReactive** (`src/SentinelReactive.sol`) — the Reactive Smart Contract on
   Lasna. It subscribes to the beacon's events through the Reactive system contract
   (`0x8888…8888`) and holds the user's rule: a floor, a ceiling, and a cooldown
   (compared against timestamps, never block numbers). On a breach it requests a
   callback to the vault via `SYSTEM.requestCallbackV_1_0`, reserving the payload's
   first argument as the sender-authentication address, per the Reactive protocol.
3. **GuardedVault** (`src/GuardedVault.sol`) — the destination vault on Base Sepolia.
   Its `executeRescue` can only be reached through the chain's callback proxy and
   only on behalf of the sentinel contract (`AbstractCallback.onlyCallbackSender`).
   It sweeps the full token balance to the owner's pre-set safe address, freezes
   withdrawals, and emits `Rescued`.

## Networks

| Contract | Chain | Chain ID |
|---|---|---|
| PriceBeacon | Base Sepolia | 84532 |
| SentinelReactive | Reactive Lasna | 5318007 |
| GuardedVault | Base Sepolia | 84532 |

## Deployed (M2 testnet run, 2026-11-18)

Deployer / safe address: `0x6ae9e830E7AB6215649863Bc7cA7f83d74f9b314`
(agent-managed testnet wallet). Funding path: 0.21 Sepolia ETH was bridged to
Base Sepolia via the official L1StandardBridge
(`0xfd0Bf71F60660E2f608ed56e1659C450eB113120`, per Base's official contract
list) — L1 tx
[`0xaa0d82d7…15531e`](https://sepolia.etherscan.io/tx/0xaa0d82d7f95cc6ec44438b4f4c53a4117d455e98b6db26d6ff7917f62415531e),
0.20 ETH arrived on Base Sepolia.

| Contract | Address | Deploy tx |
|---|---|---|
| PriceBeacon | `0x2A32Da7F073107E161f3b0ACD01C2Bc875133491` | `0x47af94885213eea44d2fea77bd9f1ea3471f56b7c498ba4a4f9ac0cbacd660c1` |
| SentinelReactive | `0x8b417463FA74DF28C46072599d64E084e73281be` | `0x9e45ba33ba9920c7944c6bb01ce0df56a1471dc080a7290c6afb48dbf3189464` |
| MockERC20 (MOCK) | `0x003704466988143B44242A9359B0B15e13c49F38` | `0x0ce1e5546d795c02cd27a4928311b6bf21b17f0b1c35564afc1f98af502fe2cc` |
| GuardedVault | `0x1D370e3782661ABBe757299a076FaB11d5b6D4e9` | `0x97a72c897e9f78596e0d2c1e43c7194efc6d4ed5cb889376b30faa7c2e34a4ef` |

Wiring: `sentinel.setVault(vault)` on Lasna, tx
`0x16d985249e8bf9edf2bb4285bef7b2406f64a488e967b90c4029d5e9e91c039c`.
All three core contracts are Sourcify-verified with **exact_match**
(PriceBeacon match 59455361, GuardedVault 59455365, SentinelReactive 59455388).

### First full loop (real cross-chain delivery)

Normal price 2100 posted first (tx `0x0a696685be1a6f71ddd1add73be81cef6c7a5027bafe1a6d3ebb1a3c9ffa25b5`, no trigger),
then the breach:

| Leg | Chain | Tx | Evidence |
|---|---|---|---|
| 1. Origin — `postPrice(1000)` | Base Sepolia | [`0xde80fec7…0103e4`](https://sepolia.basescan.org/tx/0xde80fec76038bb07452e2bed0e26daef2170b061e38cb1baf6c3c070d40103e4) | block 60290870, `PriceUpdated(1000)` |
| 2. Reactive — RSC `react()` | Lasna | [`0x476255bf…596bf7`](https://lasna.reactscan.net/tx/0x476255bfc21fcea58f95600132ab7ee5098a9fe19a06519a434ae6c067596bf7) | block 8628415, `Triggered(1000, …, triggerCount 1)` via system contract `0x8888…8888` |
| 3. Callback — `deliverCallback` → `executeRescue` | Base Sepolia | [`0x676d9c41…7512c`](https://sepolia.basescan.org/tx/0x676d9c41757e7671e698935585b0089136554333b07e40b5ea5df50b7507512c) | block 60290876, via callback proxy `0x476F44b1…743585`; `Rescued(1000, 100 MOCK)`; 100 MOCK swept to the safe address |

Post-loop state (re-read on-chain): vault `frozen = true`, `rescueCount = 1`,
vault MOCK balance 0, beacon price 1000.

## Deployed (M3 submission run, 2026-11-20)

The identical system re-deployed and re-run end to end from a fresh clean
wallet for the final submission. Deployer / safe address:
`0x55A9E6Cb835751520A6238a3896D6ad5B66379D9`. Funding path: 0.22 Sepolia ETH
was provided to the clean wallet; 0.20 ETH was bridged to Base Sepolia via
the official L1StandardBridge (L1 tx
[`0x1e694b01…a0282a4`](https://sepolia.etherscan.io/tx/0x1e694b018429ee641c81f9032f403008e570f7d195a84bff45fb67ebaa0282a4),
block 12174032) and arrived in full.

| Contract | Address | Deploy tx |
|---|---|---|
| PriceBeacon | `0x22fc9aBb07f59F75769C1940C3A023187726925D` | `0x8d299b0cc921ef7372c521557db01bbd7ea8da2ad750cfe02fc9e2c68d0ea43c` |
| SentinelReactive | `0x4639428321f570773F11cc078280ff8f71b68cbd` | `0xd6bc2b79adeeca272ed10ee3b857d655118a3eab2a822a097d92ce0e10d27e89` |
| MockERC20 (MOCK) | `0xB253862300855165330BCdbF3db405309b205aA3` | `0x607ab743fb9da34eab65b091112ccdc85cd6c5ea4a0a49cee5b15e60ae925e4f` |
| GuardedVault | `0x34dF93443E96C9CB22ec426797752627b3AAbB38` | `0x89d54247c2ee5bacb0da7774f865766c88727eb5baabe91c0de7bb5124fd832f` |

Wiring: `sentinel.setVault(vault)` on Lasna, tx
`0xcf43b926bab63bb5a8f93b726ec12785b98cfc1de0a82cba881c6c9100fd8a6f`.
All three core contracts are Sourcify-verified with **exact_match**
(PriceBeacon match 59576594, GuardedVault 59576680, SentinelReactive 59576961).

### M3 full loop (real cross-chain delivery)

Normal price 2100 posted first (tx `0xcbecc9a8357ee35f8d12f140c3dbcce2c071b23087e273525acb065b85743c8d`, no trigger),
then the breach:

| Leg | Chain | Tx | Evidence |
|---|---|---|---|
| 1. Origin — `postPrice(1000)` | Base Sepolia | [`0x9a499fc1…46bc39`](https://sepolia.basescan.org/tx/0x9a499fc1f53032b571550348c1e2b0290eace7521af721de4085eba57346bc39) | block 61206550, `PriceUpdated(1000)` |
| 2. Reactive — RSC `react()` | Lasna | [`0x1a2a4616…c8e9f8`](https://lasna.reactscan.net/tx/0x1a2a4616b32114dd9acc3374ad384b778902d2fddd3b1abd83fec9d806c8e9f8) | block 8797597, `Triggered(1000, …, triggerCount 1)` via system contract `0x8888…8888` |
| 3. Callback — `deliverCallback` → `executeRescue` | Base Sepolia | [`0x1c544301…1d5047`](https://sepolia.basescan.org/tx/0x1c544301cde4ff769cfdcc94d598a6b4c91b02d679a2a5999e62a063511d5047) | block 61206556 (6 blocks after the breach post), via callback proxy `0x476F44b1…743585`; `Rescued(1000, 100 MOCK)`; 100 MOCK swept to the safe address |

Post-loop state (re-read on-chain): vault `frozen = true`, `rescueCount = 1`,
vault MOCK balance 0, beacon price 1000, sentinel `triggerCount = 1`.

## Deployment (M2)

Foundry scripts in `script/` deploy and wire the system in order —
`DeployBeacon` → `DeploySentinel` → `DeployVault` → `SetVault` → `PostPrice`
(normal price, then a breach) — orchestrated end-to-end by `script/run-m2.sh`.
The deployer is an agent-managed testnet wallet; lREACT is obtained from the
official on-chain faucet contract on Base Sepolia
(`0x2afaFD298b23b62760711756088F75B7409f5967`, `request(address)`, 1 ETH → 100 lREACT).
Rule parameters for the demo run: initial price 2000, floor 1500, ceiling
disabled, cooldown 300 s; the vault is seeded with 100 test tokens and 0.05 ETH
(callbacks are billed to the recipient).

The full flow was first rehearsed on local forks of both live chains, then run
for real on the testnets on 2026-11-18 (see *Deployed* above): the breach post
was picked up by the Lasna RSC and the callback was delivered to the vault six
Base Sepolia blocks later, sweeping the full 100 MOCK to the safe address.

## Build

Requires [Foundry](https://book.getfoundry.sh/) and the official Reactive library
(vendored as a git submodule):

```bash
git submodule update --init
forge build
forge test   # 47 unit/integration tests, incl. a mock-system harness and a
             # local rehearsal of the full origin -> reactive -> callback loop
```

## Status

Work in progress — scoped and scaffolded 2026-11-17; **contracts complete and
fully tested 2026-11-18 (M1)**; **M2 complete 2026-11-18**: real testnet
deployment on Base Sepolia + Lasna with a full origin → reactive → callback
loop delivered on-chain and all three contracts Sourcify-verified
(build-complete by Dec 3, submission by Dec 5, 2026).

## License

MIT
