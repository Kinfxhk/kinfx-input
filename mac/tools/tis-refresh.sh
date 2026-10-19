#!/bin/bash
# Ask HIToolbox to rebuild this login session's input-source list without logging
# out: from inside the GUI session, toggle a source the user has switched off
# (enable, wait, disable). Net change to the user's sources: none.
#   tools/tis-refresh.sh [source id]   default: Squirrel's Hans mode (disabled here)
cd "$(dirname "$0")/.."
L=${1:-im.rime.inputmethod.Squirrel.Hans}
if ! build/kx-tis-list "$L" | grep -q "^$L enabled=0"; then
  echo "$L is enabled or missing; not touching it"; exit 1
fi
T=$PWD/build/kx-tis
bash tools/gui-run.sh /bin/bash -c "$T enable $L; sleep 3; $T disable $L" 2>&1 | grep -v sandbox_extension
killall TextInputMenuAgent 2>/dev/null
sleep 3
build/kx-tis-list "$L" | grep "^$L " | cut -c1-60
