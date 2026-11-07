# Windows interaction handoff — NOT RELEASE READY

Base: 6ca81462c6ea71ca9aca5dea406f1587062b3e26
Branch: fix/windows-interaction-20261105

## Actual implementation
- Candidate popup WM_NCHITTEST returns HTTRANSPARENT: keyboard-only candidate window no longer intercepts mouse clicks aimed at another field below it. This is a verified contributor to the old-field 好好 result; previous tests did not verify actual field focus.
- Added owner-bound composition context, thread/document and text selection lifecycle handling, stale termination identity check, context generation/reentrancy guards, and forced hint/candidate hiding on focus loss.
- Blur uses existing F35 engine policy. No engine/settings or digit/Space/page/Shift-digit mappings changed. No new global hook or clipboard polling.
- Rejected blur locks do not queue potentially stale writes. They leave existing document preedit for the host. This fallback is NOT fully acceptance tested.

## Verified VM execution
VM: C:/Users/kinfx/專案/ime-vm-qa/Win11-IME-QA/Win11-IME-QA.vmx
Guest: Win11 10.0.26300; MSVC Build Tools 17.14.44, toolset14.44.35207 installed inside VM only.
Final tested DLL SHA256 FA15A50065C9356885FEFADA2156753CC6CC4EFDA067F4981E26FFDCB28A7065; version remains0.1.10 (development build, not released).

1. Official0.1.10 baseline: 248 old cases,217 pass31 fail. Thirty failures are pending vd same-window -> old 好好/new empty. Remaining smoke expects obsolete fullwidth period.
2. Owner-only first attempt: also217/248; insufficient because popup ate mouse click. Preserved raw fixed-focus evidence, but later contaminated rerun overwrote that file; do not use fixed-focus-results.json for acceptance.
3. Final uncontaminated old matrix:247/248. All240 focus cases pass target equality. Only failure hello.vd1 expects hello。好 but actual hello.好, consistent current halfwidth preference. Raw final-focus-results.json and final-focus-meta.json retained.
4. Full native raw recorder: vectors1–15 observed. Source/target examples: vd -> old好,new好; hel -> oldhel,new好; vd1hel -> old好hel,new好; Esc recovery好; Enter好 CRLF; paste after pick好QA_PASTE似; vdhel paste好反QA_PASTE; decimal123.45 space; BTCUSDT space; vd ShiftA pi space -> 好Api space. These are observations, not every semantic rule passed.
5. Separate180 repeat sequence:180/180 target好; exact source groups36 each: empty->empty,vd->好,hel->hel,vd1->好,vd1hel->好hel. Raw JSONL contains selection/preedit availability/caret/panel observations.
6. VM MSVC compilation and linking successful. Engine selftest2 failures: vd blur expected好 but rawvd; he blur expected竹 but rawhe. Shared engine untouched. Mac integration must decide/update policy/tests; DO NOT publish while this is unresolved.
7. Python source-contract3 tests passed; helper selftest compilation performed. These are not TSF runtime tests.

## Incomplete / blockers
- Native hide vector16 captured partial transitions but harness cannot reliably restore textbox focus after minimizing; NOT_RUN for complete acceptance. Repeat run skips hide; not a hide PASS.
- DPI scales, synthetic overlong candidates, negative-coordinate multi-monitor, failed TSF locks and app teardown callback schedules NOT_RUN.
- Edge launched and VNC genuinely typed into real fields, but result old v/new木 is not valid KINFX acceptance: activation/mode was not established for the external process; cannot claim a product regression from it. External automation attempt did not yield complete JSON. Native Notepad/Electron/terminal acceptance NOT_RUN. Do not claim all applications tested.
- During long child provider timeout VM became suspended by an external operation; vmware.log records12:39:55Z suspended. Parent resumed it and reran uncontaminated final matrix and180 sequence. Agent did not issue suspend/off/reboot commands.
- No host IME installed/deployed/registry modified; no host reboot/logoff/data clearing. All installation/registration/selftests restricted to guest. VM retained.

## Evidence root
C:/Users/kinfx/專案/ime-vm-qa/results/
- base-focus-results.json,base-focus-meta.json
- final-focus-results.json,final-focus-meta.json
- minimal.json (final DLL hash and both fields)
- final-interaction-events.jsonl (native vectors1–15 plus hide failure)
- repeat-interaction-events.jsonl (180 repeats, full raw measurements)
- repeat-interaction-plan.json
- compiler2-raw.log (mixed OEM/UTF8; preserve bytes),compile-fix.log,build-state.txt
- fixed-installed.json (may refer prior development binary; final hash provenance in repeat metadata/minimal)
- edge-live.json (exploratory only)

Absolute evidence paths and bundle are listed in C:/HermesHub/_inbox/kinfx-ime-windows-delivery.json. Mac is integration/release owner. This bundle is a partial verified fix, not release approval.
