#!/usr/bin/env bash
# Hosted AppKit/native tests only; never activate or register an input method.
set -euo pipefail
ulimit -c 0
exec python3 "$(dirname "$0")/SettingsReload/run.py" "$@"
