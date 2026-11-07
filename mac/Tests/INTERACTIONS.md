# Native Mac interaction regressions

Run from repo root (uses only isolated scratch/user data):

```sh
SWIFTC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc \
  bash mac/Tests/run-interactions.sh
bash mac/build.sh selftest
bash mac/build.sh app direct
```

`run-interactions.sh` accepts `KINFX_RIME_DIR`, `KINFX_TEST_OUT`, `SWIFTC` and
`SDKROOT`. It needs a desktop session, but never activates a window, registers an
input source, posts keys, reads the clipboard or touches installed user settings.
The SettingsWindow controls are real AppKit objects: the test dispatches the
actual popup action, reads the saved setting/Rime patch and reopens the window.

## Evidence boundaries

- CandidatePanel tests execute the real `show` path with real font measurement,
  alpha-zero windows and synthetic caret/candidate data. Includes malformed and
  zero-width carets, negative display origins, monitor seams, all shortcut labels,
  explicit truncation, dismissal notifications and key-free caret refresh.
- Geometry policy also has a deterministic multi-screen boundary sweep. It picks
  below, above, right, left in that order; if no safe rectangle fits it hides,
  rather than overlapping the active line or losing shortcut labels.
- Horizontal content that cannot fit in 600 points falls back to vertical; each
  candidate stays on one line with tail ellipsis and its original numbered label.
  Embedded newlines/tabs use visible markers. There is no candidate mouse action;
  the keyboard-only window passes mouse events through instead of swallowing them.
- A 100ms timer exists only while candidates are visible. It asks the same weak
  IMK client for geometry, never updates marked text/engine state, and is cancelled
  on every accepted hide/blur. Screen topology changes dismiss until the next update.
- Shared-panel lifecycle: controllers pass `owner: ObjectIdentifier(self)` to
  `show(..., owner: ..., refreshCaret: ...)` and `hide(owner: ...)`. A late blur
  from A cannot hide B, including invalid/empty A updates. The owner token retains
  no controller; the caller's refresh closure must still use weak captures.
  Ownerless `hide()` remains the process-wide workspace/sleep/screen safety net.
- Timer identity is checked before and after the client geometry query. A query
  can reenter `show`/`hide`, so invalidation alone cannot prevent its stale return
  value hiding or moving the replacement (even for the same owner). Real repeating
  timer tests cover replacement, reentrant nil/valid results, and repeated hides;
  required visible fixtures fail explicitly rather than silently skipping.
- The engine self-test covers 9/5 order and numeric/Space selection. ShiftSpace
  is reserved for Sucheng full/half-width switching, never English confirmation.
  `run-shiftspace.sh` tests shell predicates plus real-engine replay; full modifier
  press/Space/release sequences are required too, not only a shifted Space event.
  A green replay does not imply actual OS/IMK modifier delivery was measured.
- The hosted `SettingsReload` harness constructs the complete production controller
  with a native NSTextView `IMKTextInput` QA client, real SettingsWindow popup
  actions and librime. It covers malformed-schema failure → explicit retry on the
  same owner, four runtime switches, idle punctuation categories, destruction and
  native reopen/restore failures. These are hosted method calls, not OS IMK keys.
- `run-interactions.sh` runs `run-settings-reload.sh` and `run-trace.sh`; both also
  work independently with the same `KINFX_RIME_DIR`, `KINFX_TEST_OUT`, `SWIFTC`
  and `SDKROOT` variables. The reload runner writes full commands, stdout/stderr
  and JSON assertions below its output directory (use a fresh directory per run).
- During a failed rebuild no input-ready dictionary session is exposed. Existing
  controller handles retain only four Boolean switches and the validated idle
  `empty|latin|other` category until an explicit settings retry. Unhandled keys
  use the host app's literal fallback (not full-width conversion during failure);
  retry restores the owner's pre-failure width intent. No text/composition is
  cached or replayed. New controllers also fall back literally until that retry.
- No installed IMK real-key acceptance is implied. Scroll/resize/full-screen,
  OS-delivered modifier events and actual app focus remain separate GUI gates.

No registration/install/version change is performed by these tests or build
commands. Do not launch the built app as an IME or copy it over the daily install
as part of this suite.
