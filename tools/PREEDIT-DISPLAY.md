# Held-run preedit display contract (scratch prototype)

`kinfx_display` is optional presentation data, not `kinfx_blur` and never a commit command.
The shared C shim consumes it; clients using native librime directly remain unchanged.
Candidate text/order/comments/segment byte offsets and all key semantics remain native.

## Version 1 record

Six newline-separated fields, atomically written as one context property:

1. literal `1` (wire version)
2. the existing `kinfx_english_state` owner ID
3. exact native raw `ctx.input`
4. exact native raw byte caret
5. display UTF-8 byte caret
6. complete display text

No control bytes allowed in display. Native input and display are each capped at 2048
bytes. The bridge reads into a separate 8192-byte checked buffer, NOT the legacy
`kx_property` 4096-byte buffer. It rejects missing/oversized/nonterminated values,
unknown version, stale owner/raw/caret, malformed UTF-8 and non-boundary/out-of-range
cursors. Rejection falls back to native presentation; it never truncates the text.
This is deliberately not a lifecycle/blocked/finalization ownership framework.

## Snapshot policy and caret restriction

`display_plan` is pure; its argument is one immutable snapshot of the relevant
run/rescue, settings and native-tail state. Letters mode:

- rescue not owned by a known tracked word: show `R.raw` when its native tail matches;
- tracked run: show `R.defer .. S.raw` when its native tail matches;
- other parked Chinese: show `R.defer .. S.pending .. native input`.

Radicals mode retains the native radical spelling and adds only the parked Chinese
prefix. It does NOT turn into blur letters: `asxe` displays `昨難水` but F35 emits `昨xe`.
Zero-candidate `asxz` works without inventing a candidate or modifying a translator.
Ordinary short codes, native uppercase/url/email, syntax, and explicitly selected
prefixes remain native. The display does not depend on the short-blur setting.

The held prefix is virtual/read-only. Only the native tail has editable raw offsets.
Letters map `displayCaret = displayBytes - nativeInputBytes + rawCaret`; radicals
map `parkedPrefixBytes + nativePreeditCaret`. No inverse mapping into held text is
advertised. Existing navigation/backspace ends rescue/flushes parked Chinese as it
already did. For example `asxz + Left` commits `昨`, leaves native `xz`, byte caret 1;
`asxz + Backspace` commits `昨`, leaves `x`. This patch does not make the virtual
prefix editable, does not silently swallow edits, and never forces End or keys.

## Engine regression tool

Build the exact source shim with `tools/rime-test-api.c` and librime headers/library,
then run a fresh user directory:

```sh
python3 tools/test-preedit-display.py --lib /path/libkxtest.dylib \
  --data /path/staged-data --work /path/new-user --output /path/result.json \
  --preedit letters --short-blur letters --width half
```

Run all eight letters/radicals × short-blur letters/commit × half/full configurations.
`--core-only` is the minimal RED/GREEN loop for `asxz/asxe/abxx`.
No host paths are embedded in this tool. It disables core dumps before loading librime.
Snapshots and key traces are production shim output; no observer Lua/instrumentation.
Injected transport rows are explicitly labelled injection, not natural typing defects.

Supplementary exact pure-function property checks use the Lua runtime exported by
librime-lua (not an alternative model implementation):

```sh
python3 tools/test-preedit-plan.py --source engine/rime/lua/english_mix.lua \
  --lua-lib /path/librime-lua.dylib --shim-lib /path/libkxtest.dylib \
  --output /path/plan-result.json
```

This engine proof does not establish IMK/TSF/IBus display/caret delivery. In particular,
the Windows TIP currently puts selection at composition end; this patch changes no
Windows/Linux platform files and is not Windows cursor acceptance.
