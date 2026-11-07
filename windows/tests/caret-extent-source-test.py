"""Source-only caret extent contract; not GUI/candidate position acceptance."""
from pathlib import Path
import re
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "tip" / "tip.cpp").read_text(encoding="utf-8")
BELOW = SOURCE.split("  void Below(", 1)[1].split("  void Begin(", 1)[0]


class CaretExtentSourceTests(unittest.TestCase):
    def test_extent_uses_released_clone_collapsed_to_caret_end(self):
        clone = re.search(r"r->Clone\(&(?P<range>\w+)\)", BELOW)
        self.assertIsNotNone(clone, "Full composition bounds do not identify a horizontally scrolled caret")
        name = clone.group("range")
        collapse = BELOW.index(f"{name}->Collapse(ec, TF_ANCHOR_END)")
        extent = BELOW.index(f"v->GetTextExt(ec, {name}, &rc, &clipped)")
        release = BELOW.index(f"{name}->Release()")
        self.assertLess(clone.start(), collapse)
        self.assertLess(collapse, extent)
        self.assertLess(extent, release)
        self.assertNotIn("v->GetTextExt(ec, r,", BELOW)
        self.assertNotIn("r->Collapse", BELOW, "Never mutate the live composition range")
        self.assertIn(f"SUCCEEDED({name}->Collapse", BELOW)
        self.assertLess(release, BELOW.index("v->Release()"))
        self.assertIn("generation == generation_", BELOW[collapse:extent])
        self.assertIn("generation == generation_", BELOW[extent:release])
        self.assertIn("Same(c, focus_)", BELOW[extent:release])

    def test_existing_candidate_fallback_remains(self):
        update = SOURCE.split("  void Update(", 1)[1].split("  void Write(", 1)[0]
        self.assertIn("if (at.x < 0 && last_.x >= 0)", update)
        self.assertIn("if (at.x < 0) at = CaretAt(&lineH);", update)
        self.assertIn("at->x = rc.left; at->y = rc.bottom + 2;", BELOW)
        self.assertIn("last_ = *at; lastH_ = *lineH;", BELOW)


if __name__ == "__main__":
    unittest.main(verbosity=2)
