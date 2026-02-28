# AzeronDisplay Notes

## Stable Baseline
- Repo: `https://github.com/rhodes2r/AzeronDisplayRepo.git`
- Branch: `master`
- Known-good anchor commit: `33916b0`
- Commit message: `Charge/cooldown parity work: native cooldown text + GCD suppression + charge-path refactors`

## Current State Summary
- Addon architecture is modularized (`00/01/20/21/30/40/50/60/70/90` files + `Core.lua` orchestration).
- Cooldown swipes are restored and generally synced better than earlier attempts.
- Cooldown engine lives in `21_CooldownEngine.lua`.
- Recent failed rewrite was reverted; active file in WoW addon path was restored from repo copy.

## Primary Goal
- Keep Azeron cooldown/charge behavior aligned with CooldownCompanion detection behavior.
- Keep Azeron UI/layout behavior intact (only cooldown logic parity work).

## Known Remaining Issues
- Occasional mismatch where Azeron shows cooldown while source WoW action button appears ready.
- Charge-edge behavior still has cases where timing diverges from reference addon.
- Regression risk is high when changing cooldown source selection logic.

## Working Rules (Important)
- Prefer small isolated patches.
- No broad rewrites without a checkpoint commit first.
- When cooldown logic changes, compare with CooldownCompanion implementation first.
- Preserve current UI behavior while changing detection/rendering internals.

## Useful Paths
- Azeron cooldown engine: `AzeronDisplay/21_CooldownEngine.lua`
- Azeron core orchestrator: `AzeronDisplay/Core.lua`
- CooldownCompanion reference:
  - `CooldownCompanion/ButtonFrame.lua`
  - `CooldownCompanion/GroupFrame.lua`
  - `CooldownCompanion/Core.lua`

## Debug Commands Used
- `/azeron cdliner`
- `/azeron cdbybutton <ActionBarButtonName>`
- `/azeron cddiff <key> <seconds>`
- `/azeron cdbindshow <binding> <seconds>`
- `/azeron procdebug`
- `/azeron procsource`

## Recommended Resume Flow On New PC
1. Clone repo.
2. Checkout `33916b0` (or `master` if unchanged).
3. Copy `AzeronDisplay` folder to WoW AddOns.
4. Test baseline in-game before any edits.
5. Make one targeted patch at a time and retest after `/reload`.

## Suggested Next Technical Step
- Add instrumentation that logs **only active display-cooldown decisions** per Azeron button (with source slot/frame/spell and chosen branch) to isolate false positives without noisy output.
