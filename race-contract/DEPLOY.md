# FRONTRUN — THE RACE · mainnet deploy runbook

Everything is prepped, compiled and tested. **You sign every transaction — I never touch your key.**
Contract verified against the real collection; the fire (transfer → 0xdead) is confirmed to work on-chain.

## What gets deployed
`FrontrunRace(collection, revealTimestamp)`:
- **collection** = `0xf8c20abd9c233a9de999c2ac6f1628df3f64efb0` — the real FRONTRUN
- **revealTimestamp** = `1783083827` — 2026-07-03 13:03:47 UTC (block 25452163, the collection's true reveal). This is the game clock t0; it's a shared offset so it doesn't change standings, only the displayed ground magnitude.

**Cost:** deploy gas = 612,699. At today's ~0.1 gwei ≈ **0.00006 ETH**; even at a 20 gwei spike ≈ 0.012 ETH.
Put **~0.05 ETH** in the deployer wallet as headroom for deploy + openBurn + renounce.

---

## 0 · One-time: put your key in an encrypted keystore (safest)
```
cast wallet import frontrun-deployer --interactive
# paste your private key, set a password. Nothing hits plaintext or shell history.
```
Hardware wallet instead? Swap `--account frontrun-deployer` for `--ledger` in every command below.

## 1 · Deploy
```
cd ~/Documents/frontrun-preview/race-contract
forge create src/FrontrunRace.sol:FrontrunRace \
  --rpc-url https://ethereum-rpc.publicnode.com \
  --account frontrun-deployer \
  --constructor-args 0xf8c20abd9c233a9de999c2ac6f1628df3f64efb0 1783083827 \
  --broadcast
```
Copy the **`Deployed to:`** address.

## 2 · Sanity-check the deploy (BEFORE opening anything)
```
export RACE=0x...          # paste the deployed address
RPC=https://ethereum-rpc.publicnode.com
cast call $RACE "frontrun()(address)"  --rpc-url $RPC   # -> 0xf8c2...efb0  (real collection)
cast call $RACE "startTime()(uint256)" --rpc-url $RPC   # -> 1783083827
cast call $RACE "burnOpen()(bool)"     --rpc-url $RPC   # -> false  (closed, as expected)
cast call $RACE "owner()(address)"     --rpc-url $RPC   # -> your address
```
If `frontrun` or `startTime` is wrong — STOP, redeploy. Nothing is live yet, so it's free to fix.

## 3 · Wire the site
Send me the **RACE** address. I set `CFG.mainnet.race`, flip the site default to mainnet, and push.
The leaderboard goes live-on-chain immediately (crown unclaimed, everyone accruing). The burn panel shows
**"burns open at launch"** and lets holders approve early — burn stays locked until step 4.

## 4 · GO — open the burn (the launch moment, live in the Space)
**ONE-WAY. This can never be closed.**
```
cast send $RACE "openBurn()" --rpc-url $RPC --account frontrun-deployer
```
The instant this lands, the burn panel arms for every holder. The first burn crowns the first king.

## 5 · Renounce — remove all admin forever (optional, anytime after step 4)
After `openBurn`, the owner can do literally nothing except renounce. Renouncing makes the game fully
autonomous — no hand on the wheel, not even yours. Strong trust signal.
```
cast send $RACE "renounce()" --rpc-url $RPC --account frontrun-deployer
cast call $RACE "owner()(address)" --rpc-url $RPC   # -> 0x000...000
```

## Optional · verify source on Etherscan
Append to step 1: `--verify --etherscan-api-key <KEY>` (or run `forge verify-contract` later).

---

### The three signatures, in order
1. `forge create …`  → deploys (dormant)
2. `cast send … openBurn()`  → **launch** (one-way)
3. `cast send … renounce()`  → hands off forever (optional)

Between 1 and 2 the game is deployed but closed — safe to sit there as long as you want.
