// Bare-modifier chords: a Ctrl+Shift tap toggles Chinese/English. The TSF key sink tracks the
// modifiers itself, so no machine-wide keyboard hook is needed: a WH_KEYBOARD_LL hook runs in every
// process's input path, misses admin/UAC windows and lets a held-back modifier break other apps'
// shortcuts. Alt+Shift is not a chord here: TSF never receives VK_MENU, so that pair stays Windows'
// own input-language switch.
#pragma once

struct KxChord {
  enum { kCtrl = 1, kShift = 2, kAlt = 4 };
  int down = 0;        // modifiers held right now
  int seen = 0;        // modifiers seen since the chord started
  bool dirty = false;  // a real key arrived: it is a shortcut, not a chord

  // mods: the modifier bits of the key, 0 for any real key. True when this event completes a bare
  // Ctrl+Shift chord (on the last modifier release, in either order).
  bool Event(int mods, bool up) {
    if (!mods) {
      if (seen) dirty = true;
      return false;
    }
    if (!up) {
      if (!down) { seen = 0; dirty = false; }
      down |= mods;
      seen |= mods;
      return false;
    }
    down &= ~mods;
    if (down) return false;  // another modifier is still held: the chord is not over
    // kAlt is still tracked: Ctrl+Alt+Shift must not read as a bare Ctrl+Shift tap.
    bool bare = !dirty && seen == (kCtrl | kShift);
    seen = 0;
    dirty = false;
    return bare;
  }
};
