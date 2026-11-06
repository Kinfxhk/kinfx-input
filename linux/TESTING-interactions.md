# Linux shell interaction regressions

`test-interactions.py` uses native PyGObject/IBus and the real packaged C
shim/librime/Lua stack, not a fake engine. Its subclass only captures output at
the IBus boundary. It does **not** prove desktop candidate geometry or real
application key delivery.

## Scope and product invariants

- **Shift+Space is the Sucheng full_shape (半形/全形) toggle only.** It is not
  an English-confirmation gesture and must never be repurposed, moved, or
  silently re-bound. The shell does not intercept it; it reaches Rime's
  `Shift+space → toggle: full_shape` binding unchanged. Any English-confirm
  design belongs to the shared engine, and is not asserted here.
- **Space paging and Enter-candidate are preserved.** The shell never swallows
  them; tests assert `vd`+Space/Right still page and `vd1`+Enter still confirms.
- **Candidate clicks = native selection, never a synthetic key.** IBus documents
  the button argument as "Mouse button" (valadoc/ibus-1.0); the GTK panels send
  `1` for the primary button, so the shell accepts button `1` and rejects others
  and any Ctrl/Alt/Super/Release modifier state. A click calls the first-class
  `kx_select_candidate_on_current_page` shim (RimeApi
  `select_candidate_on_current_page`), not `process_key`, so it picks exactly the
  displayed candidate on the current page — including association slot 9, whose
  label key is `Shift+9` == `parenleft` and would otherwise type `(` under the
  Windows-parity `association/paren_pick=false` default. The shim brackets the
  call in a `kinfx_candidate_click` property transaction; `assoc.lua` observes
  that in its commit/update notifiers so a picked suffix still runs
  `close_assoc` and keeps `kinfx_punct_tail` consistent (a raw select would
  otherwise bypass the processor exactly like a direct `commit_text`). Keyboard
  `Shift+9` after a pick still types `（`/`(` and closes the list — that literal
  meaning is untouched; only the mouse picks the 9th suffix.

## Run without installing or touching the daily IBus daemon

Prerequisites: Linux, Python GI, IBus 1.5+, `dbus-daemon`, and a staged package
share directory. Extract an existing `.deb` with `dpkg-deb -x`; do not install it.
Stage `kinfx-ibus`, `kxcore.py`, `test-interactions.py` and that package's
`libkxshim.so` together in a scratch `lib` directory. Use the engine data from
the exact revision being tested, not an older installed package when testing
shared Lua changes.

With `QA` pointing to your scratch directory (never the live user directory):

```sh
export KX_LIB="$QA/lib"
export KX_SHARE="$QA/share"   # contains data/, app-info.json, settings-spec.json
export KX_USER="$QA/user"     # disposable, created by the engine
# Use a private session bus. No ibus-daemon is needed for this native unit suite.
dbus-run-session -- /usr/bin/python3 "$KX_LIB/test-interactions.py"
```

If `dbus-run-session` is not installed, start a task-owned
`dbus-daemon --session --nofork --print-address=1`, pass its printed address as
`DBUS_SESSION_BUS_ADDRESS`, and terminate **only that exact process** afterwards.
Do not use broad `pkill`, the daily session bus, or `DISPLAY=:0`.

The suite runs under the product default `english/blur_short = letters` and
`page_size = 9`; `KX_TEST_SHORT_BLUR` / `KX_TEST_PAGE_SIZE` env overrides let the
same assertions also run under `commit` and page size 5 (both values stay
reachable; the default is never changed by the test). This is private test data
in a disposable dir; it changes no product default.

The expected-value tests protect focus/reset/disable cleanup, secure/private
input passthrough, existing Ctrl+Shift/Alt+Shift semantics, keyboard paging and
Shift+digit selection, candidate-click bounds/buttons/modifiers, association
slots across the whole current page (all 9 at page 9, 5 at page 5), the literal
9th-suffix click vs keyboard Shift+9, a normal click opening the association and
keeping its suffix punctuation tail identical to the keyboard path, and not
rearming an association in another field. Subtests are not counted as
independent top-level tests.

## Separate integration evidence

A private IBus daemon can run the existing `test-ibus.py` with page sizes 9 and
5. A GTK3 client on a **private Xvfb display** should additionally verify the
actual entry strings and preedit after `vd`/`hel`/`vdhel` blur, a chord spanning
focus, password-to-normal focus, association focus-out, and paste followed by
Shift+1. Use Xvfb `-displayfd` to acquire a free display instead of guessing a
number another job may use; propagate the private IBus/session-bus addresses
and explicitly point KX_LIB/KX_SHARE/KX_USER at the staged files.

The GTK harness records blur vectors and the English Shift/Space/Return research
rows as **pending_shared** (raw values, never a PASS against an undecided or
broken shared behaviour), and records Tab focus movement without asserting it
(Tab's expand role is intentional; whether focus traversal is a gap is a product
question). Width-crossing rows (short/long English, Chinese, mixed) are captured
in both full_shape modes so the shared-Lua owner can evaluate 「英文標點半形、
中文可全形」 without the shell forcing width. Candidate click tests invoke the
native shell callback (`do_candidate_clicked`, real PyGObject/IBus vfunc into
the production libkxshim/librime stack); they do not click a GNOME panel or a
desktop candidate window, so real pointer hit-testing of candidate geometry
remains unmeasured here. Xvfb/GTK3 is not native
Wayland, GTK4, Qt, Electron, or a dual-screen placement test.

