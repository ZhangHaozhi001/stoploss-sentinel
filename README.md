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

## Build

Requires [Foundry](https://book.getfoundry.sh/) and the official Reactive library
(vendored as a git submodule):

```bash
git submodule update --init
forge build
```

## Status

Work in progress — scoped and scaffolded 2026-11-17; contracts compile; deployment
and end-to-end loop scheduled per the build plan (build-complete by Dec 3, submission
by Dec 5, 2026).

## License

MIT
