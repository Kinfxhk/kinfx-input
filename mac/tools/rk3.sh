#!/bin/bash
# Real-key run, user-like source switch: focus TextEdit, Control+Space (previous source),
# confirm from the IMK log that KINFX was the LAST server activated, then type with CGEvent.
#   tools/rk3.sh            prints activations, trace, saved text; restores OpenVanilla
cd ~/kinfx-input-dev/w/mac
T=~/.hermes/cache/scratch/unwire50/mac_type_str
L="$HOME/Library/Containers/hk.kinfx.inputmethod.KINFXInput/Data/Library/Application Support/KINFX Input/log"
F=~/kinfx-input-dev/rk3.txt
front() { lsappinfo info -only name "$(lsappinfo front)" 2>/dev/null | awk -F'"' 'NR==1{print $2}'; }
# per-document input source: TIS "current" can say KINFX while TextEdit's document still uses
# OpenVanilla, so judge by the last IMK server that logged "Activate Server".
last_active() { /usr/bin/log show --start "$1" --style compact --predicate 'eventMessage CONTAINS "Activate Server"' 2>/dev/null | grep -vE 'Deactivate' | grep -oE '(KINFXInput|OpenVanilla|Squirrel)\[' | tail -1 | tr -d '['; }
[[ -x build/kx-ctrlspace ]] || swiftc -O tools/kx-ctrlspace.swift -o build/kx-ctrlspace
mkdir -p "$L"; touch "$L/trace-on"; rm -f "$L/kx-trace.log"
: > "$F"; open -a TextEdit "$F"; sleep 1.5
case "$(front)" in 文字編輯|TextEdit) ;; *) echo "ABORT front=$(front)"; rm -f "$L/trace-on"; exit 2 ;; esac
S=$(date '+%Y-%m-%d %H:%M:%S'); sleep 1
build/kx-ctrlspace; sleep 1.5
A=$(last_active "$S")
echo "after ctrl+space: last activated=$A  $(build/kx-mods)  front=$(front)"
if [[ $A != KINFXInput ]]; then build/kx-ctrlspace; sleep 1.5; A=$(last_active "$S"); echo "second ctrl+space: last activated=$A"; fi
if [[ $A == KINFXInput ]]; then
  $T 'vd1'; sleep 0.4; $T $'\n'; sleep 0.2; $T 'iPhone '; sleep 0.6
  echo "after typing: front=$(front)  $(build/kx-mods)  last activated=$(last_active "$S")"
else
  echo "KINFX never became the active server; not typing"
fi
[[ -s $L/kx-trace.log ]] && cut -c27-200 "$L/kx-trace.log" || echo NO_TRACE
rm -f "$L/trace-on" "$L/kx-trace.log"
[[ $(last_active "$S") == KINFXInput ]] && { build/kx-ctrlspace; sleep 1; }
echo "restored: last activated=$(last_active "$S")"
