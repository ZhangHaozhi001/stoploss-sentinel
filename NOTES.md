# Reactive Omni Buildathon — verified facts (2026-11-17)

Sources (official only):
- DoraHacks page: https://dorahacks.io/hackathon/reactive-omni-buildathon/detail
- Reactive blog announcement (2026-11-04): https://blog.reactive.network/reactive-omni-buildathon-thirty-days-to-find-out-what-one-second-buys/
- Reactive docs: https://dev.reactive.network (Getting Started / Reactive Contracts / Origins & Destinations)

## Event
- Name: Reactive Omni Buildathon (Reactive Network). Registration + submissions via DoraHacks.
- Window: Nov 5 – Dec 5, 2026. DoraHacks lists the event end as **2026-12-05T20:00:00Z** (= Dec 6, 04:00 CST). The blog says "runs until December 5th". **Internal plan targets Dec 3 build-complete, Dec 5 latest submission** (brief instruction: plan for Dec 5).
- Prize pool: **$5,500, denominated in USD, paid in REACT**. Judged by the Reactive team (guest judges, if any, announced on the DoraHacks page).

## Tracks (themes + prizes)
1. **Every Second Counts** — $2,000 first / $250 runner-up. Time-sensitive DeFi where reaction time matters (arbitrage on price gaps, stop-loss/take-profit for DEX positions, rebalancing vaults, withdrawal queues). Built on **Unichain Sepolia (1301)** and/or **Base Sepolia (84532)** with Reactive Lasna in the middle. Strongest entries show full-loop latency numbers (origin event → Reactive → callback).
2. **Set It and Forget It** — $2,000 first / $250 runner-up. Personal automations anyone can build, on **any chain Reactive supports**; usefulness over speed ("is this something you'd actually leave running?"). Examples from the brief: portfolio tracker, alert when an LP position hits a price, custom rebalancing rules. Explicitly the track for builders new to contracts / building with AI coding tools.
3. **Reactive Meets AI** — $1,000 first only. A neural network must be part of the *running system* (deciding what an RSC does next, interpreting its events, or being triggered by them). AI used only as a coding tool does NOT qualify here — those projects belong in Set It and Forget It.

5 winning slots total (2 + 2 + 1). Field: ~194 registrations, ~17 estimated submitted projects (parent scan estimate — thin field).

## Judging (each entry scored 1–5, four equally weighted criteria)
- **Execution** — Does it run? Judges want to see the reactive transactions and the callbacks they trigger **on-chain**. *Entries without them aren't scored further.* (Hard gate.)
- **Integration** — Does the reactive contract do real work, or is it bolted on?
- **Usefulness** — Does it solve a problem real users have?
- **Craft** — Readable code, a working demo, documentation someone else could follow.

## Deliverables (per submission, via DoraHacks)
- Link to a **public, open-source repository**
- **Deployed contract addresses**
- **A few transaction hashes showing the full loop** (origin event → reactive tx → callback)
- **Demo video under 3 minutes**

## Ground rules
- Everything built during the event (Nov 5 – Dec 5); prior work allowed only as a dependency, not as the submission itself.
- **Every Second Counts runs on Lasna testnet.** The other two tracks may use Reactive mainnet (1597) or Lasna (5318007).
- On Base Sepolia use **timestamps, not block counts**, for timers/cooldowns/deadlines (200 ms blocks since the Denim upgrade).
- Mainnets and testnets must not be mixed (origin and destination both testnet or both mainnet).
- Testnet REACT (lREACT) from the Reactive Lasna faucet (linked from dev.reactive.network). Reactive contracts must be kept funded — they pay gas for their own reactive transactions; a contract in debt receives nothing.

## Networks (from docs "Origins & Destinations" + "Verifying" pages)
| Chain | Chain ID | Role | Callback proxy | RPC |
|---|---|---|---|---|
| Reactive Lasna (testnet) | 5318007 | RSC host | 0x8888888888888888888888888888888888888888 (system contract) | https://lasna-rpc.rnk.dev/ (explorer lasna.reactscan.net) |
| Base Sepolia | 84532 | origin/destination | 0x476F44b11F5C942c58f4c8E3d0300E5710743585 | public Base Sepolia RPC |
| Unichain Sepolia | 1301 | origin/destination | 0x775c9B990ADe401060B78D0e98684eEf8d2466C1 | public Unichain Sepolia RPC |
| Ethereum Sepolia | 11155111 | origin/destination | 0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4 | — |
| Reactive Mainnet | 1597 | RSC host (tracks 2–3 only) | 0x8888888888888888888888888888888888888888 | https://mainnet-rpc.rnk.dev/ |

## Omni development pattern (docs, post-RVM)
- Solidity **^0.8.29**; standard Foundry/Hardhat tooling; no RVM, no dual deployment.
- Official library: **github.com/Reactive-Network/reactive-lib-omni** (`@reactive/src/...`): inherit `AbstractReactive`, subscribe in the constructor via `SYSTEM.subscribe(chainId, contract, topic0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE)`, implement `react(LogRecord memory log_) external onlySystem`.
- System contract `SYSTEM` = 0x8888888888888888888888888888888888888888; `REACTIVE_IGNORE` = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad.
- Callbacks: `SYSTEM.requestCallbackV_1_0(CallbackConfiguration_V_1_0{chainId, recipient, gasLimit, payload})`. **The payload's first argument must be an `address` placeholder (pass address(0))** — the network overwrites the first 160 bits with the requesting reactive contract's address so the destination can authenticate it.
- Destination side: inherit `AbstractCallback` (same lib), guard callback functions with `onlyCallbackSender(firstArg)`; deploy order = reactive contract first → destination with its address → set recipient on the reactive contract via owner setter.
- Callbacks are billed to the *recipient* contract on the destination chain (in that chain's native token); the reactive contract pays for its own reactive transactions on Lasna. Both must be funded.
- Contract verification via Sourcify (`forge verify-contract --verifier sourcify`).

## Registration / payment notes
- Registration is on DoraHacks (user account step — NOT done in this scoping pass, batched for later).
- Prizes paid in REACT (amount denominated in USD). No entry fee found in official sources. Winners/payout mechanics beyond "paid in REACT" are not specified in the announcement; expect a wallet address to be requested from winners via DoraHacks.
- No mandatory Telegram/Discord step found in official sources for this event (unlike BCH BLAZE).
