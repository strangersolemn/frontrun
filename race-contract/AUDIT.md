# FRONTRUN — THE RACE · security audit (self / AI pass)

Target: `contracts/FrontrunRace.sol` (140 lines, burn-only satellite).
Method: line-by-line adversarial review + executable proofs (`test/Audit.t.sol`, 6/6 passing).
Verdict: **one critical bug found. Do not deploy the current contract. A verified fix is in `src/FrontrunRaceFixed.sol`.**

---

## 🔴 CRITICAL — the crown compares against a frozen floor, so it drifts off the true leader

**Where:** `burnInto()` crown check —
```solidity
if (!crownClaimed || survivorGround > kingGround || king == sacrifice) { ... kingGround = survivorGround; }
```
`kingGround` is a **snapshot** of the king's ground at the moment it was crowned. But every living
piece — the king included — keeps accruing base ground every second (`groundOf = base + absorbed`).
So the stored floor sits still while the king's real ground climbs. The gap between them grows without
bound.

**Consequence:** a challenger only has to clear the *stale* floor, not the king's *actual* ground. So a
piece that is genuinely **behind** the king can still steal the crown. The on-chain king stops matching
the front-runner the site shows — and over time the floor erodes to nothing, so eventually almost any
burn takes the crown. For an immutable contract, that breaks the whole game permanently.

**Proof:** `testBug_CrownDivergesFromLeader()` — A stacks two early burns (ground 370, the clear
leader); time passes; B makes one late burn (ground 340). A is still ahead (370 > 340), **yet the crown
goes to B.** Test passes, i.e. the divergence is real on the deployed-as-written contract.

**Why it happens:** all living pieces share the same `base`, so the true ordering is by `absorbed`
alone (the base cancels when you compare two live pieces). Comparing a live total against a frozen total
re-introduces the base as noise.

**Fix (one line of logic):** compare against the king's **live** ground:
```solidity
take = survivorGround > groundOf(king);   // base cancels → absorbed-vs-absorbed, time-invariant
```
`testFix_CrownStaysWithLeader()` runs the identical scenario against `FrontrunRaceFixed.sol` and the
crown correctly stays with A. This keeps the intended mechanic (“stack, burn, overtake”) intact — you
still overtake by out-absorbing the king; you just can't win by merely waiting.

---

## 🟠 HIGH (operational) — renouncing before opening bricks the game forever

`openBurn()` requires `owner`. `renounce()` sets `owner = address(0)`. If `renounce` is called **before**
`openBurn`, the burn can never be opened by anyone — the game is permanently dead on arrival.
**Mitigation:** strict launch order — `openBurn()` first, confirm `burnOpen == true`, *then* `renounce()`.
(The deploy runbook already sequences it this way; treat it as a hard rule, not a preference.)

---

## 🟡 LOW (defense-in-depth) — crown update sat after the external transfer

The original does its `transferFrom` to `0xdead`, then reads `groundOf(survivor)` and updates the crown.
The core state (dead/absorbed/burnCount) is set before the call, so ground/supply are safe even under a
reentrant collection. But the crown write after the call is avoidable risk. The real FRONTRUN collection
is a standard non-callback ERC721 (a plain `transferFrom` invokes no receiver hook), so this is not
exploitable in practice — but the fix moves the external call to the very end so **no** state is touched
after it. Full checks-effects-interactions, free hardening.

---

## ✅ Checked and clean

- **Ownership of pieces:** `burnInto` requires the caller owns *both* sacrifice and survivor — you can't
  burn someone else's piece, and you can't burn into a rival to inflate them.
- **No double-burn / no un-death:** `dead[]` is permanent; burning a dead piece reverts. (proved)
- **Ground conservation:** the survivor gains *exactly* the sacrifice's ground; the dead piece reads 0;
  its final tally is preserved in `deadGround`. (proved)
- **Access control:** `openBurn` / `renounce` are owner-only; `openBurn` is one-way; after `renounce`
  both revert. (reasoned)
- **No custody:** the contract never holds ETH or NFTs — the sacrifice goes straight to `0xdead`. No
  drain surface, no withdraw function to get wrong.
- **Arithmetic:** Solidity 0.8 checked math; all quantities are seconds-scale, nowhere near overflow.
- **Burn-closed guard:** burning before `openBurn` reverts. (proved)

## Notes (not bugs)

- **Burns get bigger over time** is intended and preserved by the fix (a later burn carries a larger
  base). The fix only removes the *unearned* erosion from idle time.
- **MEV/ordering:** a crown-taking burn is public and could be front-run. Inherent to on-chain games;
  no funds at risk. Worth a one-liner to holders, not a code change.

---

### Status — FIXED (2026-07-07)
The fix is now **merged into `contracts/FrontrunRace.sol`** (crown compares live `groundOf(king)`;
external transfer moved to the end for full CEI; stale header/comment corrected). Verified:
- `test/Audit.t.sol` — **8/8 passing**, incl. the crown regression, a real-overtake case, king-sacrifice
  inheritance, and all safety properties.
- Live-EVM rehearsal (anvil): deploy → openBurn → approve → burnInto reads correct across every selector
  the site uses (`groundOf`, `crown`, `dead`, `burnCount`, `burnOpen`); sacrifice lands at `0xdead`;
  ground conserved exactly.

Constructor args and deploy gas are unchanged. Ready for the deploy runbook. A live public-testnet
(Sepolia) rehearsal of the fixed build is optional and needs a funded testnet key.
