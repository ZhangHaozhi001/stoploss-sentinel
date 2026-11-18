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

Deployed addresses and the full-loop transaction hashes will be added here after the
testnet deployment milestone (see PLAN.md in the working notes).

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

The full flow has been rehearsed successfully on local forks of both live
chains; the real testnet deployment is pending a Base Sepolia faucet drip to
the deployer wallet (all public faucets currently require an account or
browser wallet verification).

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
fully tested 2026-11-18 (M1)**; M2 deployment scripts written and rehearsed
end-to-end on chain forks 2026-11-18, real testnet deployment pending faucet
funding of the deployer wallet (build-complete by Dec 3, submission by Dec 5, 2026).

## License

MIT
