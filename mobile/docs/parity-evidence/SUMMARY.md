# Parity Evidence Summary

**Generated:** 2026-05-01
**iOS device:** iPhone 15 Pro Simulator (393×852 pt logical, 1179×2556 px physical) — capture DEFERRED
**Android device:** Waived — no Pixel 7 emulator available
**Web viewport:** 390×844 CSS px (Playwright chromium-1217 headless, authenticated via storageState)
**Comparison canvas:** 390×754 (after iOS chrome masking + resize)
**Threshold:** ≤5.0% pixel divergence outside platform chrome
**pixelmatch:** v7.2.0  threshold=0.1  includeAA=false  diffColor=magenta
**Captured from:** test fixture user (the anti-PII rule for committed captures: a designated test account, never a real one, and any capture that shows personal data is redone with a scrubbed fixture)

## Status: PARTIAL — capture deferred to operator

This evidence pack is **scaffolded but not captured**. The capture run was attempted by an autonomous executor that lacks:

- A registered passkey + WebAuthn-capable headed Chromium session (Sway is passkey-only — `mobile/scripts/.auth/storageState.json` is operator-time data)
- `xcrun simctl` (still unselected — `sudo xcode-select -s` requires operator-time sudo)
- An iPhone 15 Pro simulator booted in a Mac GUI session
- An Android Pixel 7 emulator (`mobile/scripts/probe-android-emulator.sh` exited 78: no emulator available)

The locked rule for this pack is waivers, not in-phase fixes: the deferral is recorded in the evidence itself rather than by fabricating numbers or skipping the must_have schema. Every screen entry in `manifest.json` carries `pass: false` and a `waiver_reason` saying in words why the number is missing, so `verify-summary.js` exits 0 against the locked rule "pass === false ⇒ waiver_reason set", and the operator can flip rows to `pass: true` after running the capture pipeline. The reason is written into the pack because a reader outside the maintainers' tracker can act on a sentence and cannot resolve an issue id.

**Operator unblock sequence:**

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer    # one-time
xcrun -f simctl                                                     # verify
dip run dev                                                          # terminal 1
pnpm parity:auth                                                     # terminal 2 — complete passkey
xcrun simctl boot 'iPhone 15 Pro'
pnpm parity:verify                                                   # must exit 0 to close PARITY-19
```

After capture, eyeball each `diff/<slug>.png` and classify what the magenta shows with the nine parity diff tags — `[copy]`, `[layout]`, `[color]`, `[icon]`, `[interaction]`, `[state]`, `[platform]` (status bar, tab bar, Dynamic Island), `[no-web-counterpart]` (mobile-only screen, diff skipped) and `[bug]` (a real defect) — then file a `parity-followup` sub-issue for every `[bug]` and update each row's Pass/Fail + Notes columns from the diff numbers in `manifest.json`.

## Manual verifications

Manual verifications: iOS swipe-back and Android hardware-back are both deferred, the first pending an on-device gesture pass, the second pending an Android emulator as well.

The PARITY-18 *code* contract — drawer `drawerLabel` parity and OrgsStack header back-title — is verified by the `mobile/__tests__/navigation/AppDrawer.labels.spec.ts` and `mobile/__tests__/navigation/header-title-audit.test.ts` regression guards. The deferred manual verification is the on-device UAT pass on top of the verified code, not a re-verification of the code itself.

## Evidence table

| Screen | PARITY | Web ref | iOS divergence % | Android divergence % | Pass/Fail | Notes |
|---|---|---|---|---|---|---|
| Bill of the Week | PARITY-04 | /bill-of-the-week | n/a (deferred) | n/a (waived) | DEFERRED | Capture deferred — operator must run pnpm parity:auth + capture pipeline |
| Bills List | PARITY-05 | /bills | n/a (deferred) | n/a (waived) | DEFERRED | Capture deferred |
| Bill Detail | PARITY-06 | /bills/:id | n/a (deferred) | n/a (waived) | DEFERRED | Capture deferred |
| Legislators List | PARITY-08 | /legislators | n/a (deferred) | n/a (waived) | DEFERRED | Capture deferred |
| Legislator Detail | PARITY-09 | /legislators/:id | n/a (deferred) | n/a (waived) | DEFERRED | Capture deferred |
| Organizations List | PARITY-10 | /organizations | n/a (deferred) | n/a (waived) | DEFERRED | Capture deferred |
| Organization Detail | PARITY-11 | /organizations/:id | n/a (deferred) | n/a (waived) | DEFERRED | Capture deferred |
| Auth phone entry | PARITY-12 | /sign-in | n/a (deferred) | n/a (waived) | DEFERRED | Capture deferred |
| Auth code revealed | PARITY-12 | /sign-in | n/a (deferred) | n/a (waived) | DEFERRED | Capture deferred |
| Auth loading | PARITY-12 | /sign-in | n/a (deferred) | n/a (waived) | DEFERRED | Capture deferred |
| Auth Preview Sway CTA | PARITY-12 | /sign-in | n/a (deferred) | n/a (waived) | DEFERRED | Capture deferred |
| DeviceUnsupported | PARITY-12 | (none) | n/a (deferred) | n/a (waived) | DEFERRED | [no-web-counterpart] mobile-only; iOS capture deferred |
| Address onboarding | PARITY-13 | /users/registration | n/a (deferred) | n/a (waived) | DEFERRED | Capture deferred |
| Address edit | PARITY-13 | (none) | n/a (deferred) | n/a (waived) | DEFERRED | [no-web-counterpart] mobile-only; iOS capture deferred |
| Profile | PARITY-14 | (none) | n/a (deferred) | n/a (waived) | DEFERRED | [platform] Drawer.tsx canonical; [no-web-counterpart] mobile-only; iOS capture deferred |
| Notification Preferences | PARITY-15 | /users/notification_preferences | n/a (deferred) | n/a (waived) | DEFERRED | Capture deferred |
| Theme | PARITY-16 | /users/theme | n/a (deferred) | n/a (waived) | DEFERRED | Capture deferred |
| Passkey Management | PARITY-17 | /users/passkeys | n/a (deferred) | n/a (waived) | DEFERRED | Capture deferred |

## Parity-followup work filed with this pack

Three follow-ups carry the `parity-followup` label in the maintainers' tracker:

| Priority | Subject |
|----------|---------|
| P2 | Capture parity evidence — operator must register passkey, run dip dev, and pnpm parity:auth |
| P3 | Android Pixel 7 evidence pass deferred — emulator unavailable (umbrella waiver) |
| P3 | Manual gesture verification deferred — iOS swipe-back / Android hardware-back |

## Closing PARITY-19

Operator workflow to flip PARITY-19 from Partial → Complete:

1. Run the capture sequence above; produce all paired PNGs.
2. Eyeball every `diff/<slug>.png` and update `manifest.json` by the classification rule (≤5% with `[platform]` chrome only → `pass: true`; >5% on real content → keep `pass: false` and write what is still outstanding into `waiver_reason`).
3. Re-render this `SUMMARY.md` from the updated `manifest.json`; the preamble fields and the evidence table's columns stay as they are.
4. Run `pnpm parity:verify` — must exit 0.
5. Mark PARITY-19 `Complete` in the issue tracker, and update its coverage note.
6. Close the capture follow-up referencing this commit.
