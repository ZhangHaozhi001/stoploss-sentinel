# PLAN — StopLoss Sentinel (Reactive Omni Buildathon)

## Chosen track: **Set It and Forget It** ($2,000 / $250)
Why this track over the other two:
- **Reliability**: Every Second Counts is judged on full-loop latency in live DeFi integrations (real DEX pools on Unichain/Base Sepolia) — more moving parts, more ways to fail the Execution gate. Set It and Forget It explicitly rewards *usefulness over speed* and welcomes first-time contract builders; a small deterministic loop scores on all four criteria.
- **The brief hands us the concept**: "an alert when a position hits a price" / "custom rebalancing rules" are the track's own examples. We build exactly that, with an on-chain action instead of just an alert.
- **Reactive Meets AI rejected**: only $1,000, single slot, and it requires an AI model inside the running system (extra infra, extra failure modes) for less money.
- This track also allows any supported chain — we still use the same Lasna + Base Sepolia testnet stack, so no mainnet funds are ever needed.

## Concept — StopLoss Sentinel
*"Set a floor once. If the price breaks it, your vault rescues itself — no bot, no keeper, no watching charts."*

A personal stop-loss for a small testnet vault, implemented as a complete reactive loop:

1. **Origin (Base Sepolia)** — `PriceBeacon`: a minimal price-posting contract (stands in for an oracle feed). Its owner posts a price; every post emits `PriceUpdated(int256 price, uint256 updatedAt)`. Using our own beacon keeps the demo deterministic — the full loop can be triggered on demand, which is what the Execution criterion demands (real reactive txs + callbacks on-chain).
2. **Reactive (Lasna)** — `SentinelReactive` (inherits `AbstractReactive`): subscribes to `PriceUpdated` on Base Sepolia. Holds the user's rule: `floor` and `ceiling` (timestamps/cooldown per Base-Sepolia guidance). When a posted price crosses the floor (or ceiling) and the cooldown has passed, it requests a callback to the vault on Base Sepolia via `SYSTEM.requestCallbackV_1_0`, payload first arg = `address(0)` placeholder per protocol.
3. **Destination (Base Sepolia)** — `GuardedVault` (inherits `AbstractCallback`): holds a test ERC-20 balance for the user. Its `executeRescue(address sentinel, int256 triggerPrice)` is guarded by `onlyCallbackSender` + the callback proxy (via AbstractPayer). On a valid callback it sweeps the full balance to the user's pre-set `safeAddress`, freezes withdrawals, and emits `Rescued(...)`. Owner can deposit/withdraw while not frozen, and reset the vault after a rescue.

Demo story (video < 3 min): deposit test tokens → post a normal price (nothing happens) → post a price below the floor → show the Lasna reactive tx on Reactscan → show the Base Sepolia callback tx sweeping the vault → vault frozen, funds at the safe address.

### Why it should score
- **Execution**: full loop on-chain, reproducible on demand (beacon), tx hashes for all three legs.
- **Integration**: the RSC *is* the product — no RSC, no rescue. Rule state (floor/ceiling/cooldown) lives in the reactive contract.
- **Usefulness**: stop-loss / take-profit protection is a real, universal DeFi need; "would you leave it running?" — yes, that's the point of the track.
- **Craft**: small, readable, documented contracts based directly on the official Omni library and docs patterns.

## Architecture / files
```
src/PriceBeacon.sol       — origin-chain price poster (Base Sepolia)
src/SentinelReactive.sol  — the RSC (Lasna): subscription + threshold logic + callback request
src/GuardedVault.sol      — destination vault (Base Sepolia): AbstractCallback-guarded rescue
lib/reactive-lib-omni/    — official Reactive library (git submodule)
script/                   — Foundry deploy scripts (added in build phase)
test/                     — Foundry tests (added in build phase)
```

## Milestones (build-complete by Dec 3; submission by Dec 5)
- **M0 — Scope & scaffold (Nov 17, done)**: rules verified (NOTES.md), repo + compilable skeleton.
- **M1 — Contracts complete (by Nov 24)**: full logic (ceiling trigger, cooldown by timestamp, owner setters, pause/unsubscribe, coverDebt), Foundry unit tests incl. a mock-system harness for `react()`.
- **M2 — Testnet deploy & first full loop (by Nov 28)**: faucet lREACT + Base Sepolia ETH; deploy beacon → reactive → vault; wire addresses; trigger a breach; capture the three tx hashes (origin / reactive / callback). Verify contracts on Sourcify.
- **M3 — Hardening & docs (by Dec 1)**: re-run loop end-to-end from a clean wallet for final tx hashes; README with addresses, hashes, architecture diagram, run-book; edge cases (double-trigger, debt top-up).
- **M4 — Demo + submission package (by Dec 3)**: demo video < 3 min recorded; DoraHacks submission text drafted (title, description, repo, addresses, hashes, video link).
- **Buffer (Dec 4–5)**: user registers on DoraHacks + submits (user-account step); final check against the Dec 5 target (DoraHacks lists event end Dec 5 20:00 UTC — do not rely on the extra hours).

## Risks & mitigations
- **Lasna faucet / RPC flakiness** → start M2 early; both documented RPC hostnames noted (lasna-rpc.rnk.dev, lasna-omni-rpc.rnk.dev).
- **Callback billing**: recipient (vault) pays for callbacks in Base Sepolia ETH and the RSC pays its own gas in lREACT — keep both funded; test with small gas limit (1,000,000 per docs example).
- **Payload first-arg rule**: forgetting the `address(0)` placeholder is the #1 callback bug (docs) — skeleton already follows it; unit test asserts payload layout.
- **Deadline ambiguity** (Dec 5 vs Dec 6 04:00 CST) → plan is built to the earlier date.
