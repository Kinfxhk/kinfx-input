#!/usr/bin/python3
"""Native-GI shell regressions; run on Linux inside a private D-Bus session.

KX_LIB must contain kinfx-ibus, kxcore.py and libkxshim.so; KX_SHARE is staged
package data, and KX_USER must be a disposable directory (never the live user).
No mock engine: every key reaches the real C shim/librime/Lua stack.
"""
import importlib.machinery
import importlib.util
import os
import unittest

import gi
gi.require_version("IBus", "1.0")
from gi.repository import Gio, IBus

loader = importlib.machinery.SourceFileLoader("kx_ibus", os.path.join(os.environ["KX_LIB"], "kinfx-ibus"))
spec = importlib.util.spec_from_loader(loader.name, loader)
assert spec is not None
shell = importlib.util.module_from_spec(spec)
loader.exec_module(shell)
IBus.init()
# Both settings remain reachable; defaults must stay exactly as specified.
os.makedirs(shell.ENGINE.user, exist_ok=True)
shell.kxcore.save(dict(shell.ENGINE.settings,
                       page_size=os.environ.get("KX_TEST_PAGE_SIZE", "9"),
                       short_blur=os.environ.get("KX_TEST_SHORT_BLUR", "letters")),
                  shell.ENGINE.settings_path)
assert shell.ENGINE.start(), "native engine did not start"


class CapturedEngine(shell.KxEngine):
    """Capture the IBus output boundary, not engine decisions."""
    __gtype_name__ = "KxInteractionTestEngine"

    def __init__(self, **kw):
        super().__init__(**kw)
        self.commits = []
        self.preedit = ("", False)
        self.auxiliary = ("", False)
        self.lookup_visible = False

    def commit_text(self, text):
        self.commits.append(text.get_text())

    def update_preedit_text_with_mode(self, text, cursor, visible, mode):
        self.preedit = (text.get_text(), visible)

    def update_preedit_text(self, text, cursor, visible):
        self.preedit = (text.get_text(), visible)

    def update_auxiliary_text(self, text, visible):
        self.auxiliary = (text.get_text(), visible)

    def hide_auxiliary_text(self):
        self.auxiliary = ("", False)

    def update_lookup_table(self, table, visible):
        self.lookup_visible = visible

    def hide_lookup_table(self):
        self.lookup_visible = False


class Interactions(unittest.TestCase):
    serial = 0

    def setUp(self):
        type(self).serial += 1
        self.e = CapturedEngine(engine_name="kinfx", object_path="/qa/engine%d" % self.serial,
                                connection=Gio.bus_get_sync(Gio.BusType.SESSION, None))
        self.e.do_focus_in()

    def tearDown(self):
        if shell.ENGINE.alive(self.e.sess):
            shell.ENGINE.clear(self.e.sess)
            shell.ENGINE.commit(self.e.sess)
            shell.ENGINE.destroy(self.e.sess)
        self.e.destroy()

    def key(self, keyval, state=0):
        return self.e.do_process_key_event(keyval, 0, state)

    def type_text(self, text):
        for c in text:
            self.key(ord(c))
            self.key(ord(c), IBus.ModifierType.RELEASE_MASK)

    def test_focus_out_does_not_carry_associations_to_next_field(self):
        self.type_text("vd1")
        self.e.do_focus_out()
        self.e.do_focus_in()
        self.e.commits.clear()
        self.key(ord("!"), IBus.ModifierType.SHIFT_MASK)
        self.assertNotEqual("".join(self.e.commits), "似")
        self.assertFalse(self.e.lookup_visible)

    def test_private_and_pin_input_resume_only_after_normal_content_type(self):
        for purpose, hints in ((IBus.InputPurpose.PIN, 0),
                               (IBus.InputPurpose.FREE_FORM, IBus.InputHints.PRIVATE)):
            with self.subTest(purpose=purpose, hints=hints):
                self.type_text("vdhel")
                self.e.emit("set-content-type", int(purpose), int(hints))
                self.assertEqual(self.e.preedit, ("", False))
                self.assertFalse(self.e.auxiliary[1])
                self.assertFalse(self.e.lookup_visible)
                self.assertFalse(self.key(ord("v")))
                self.e.do_candidate_clicked(0, 1, 0)
                self.assertEqual(self.e.commits, [])
                self.e.emit("set-content-type", int(IBus.InputPurpose.FREE_FORM), 0)
                self.type_text("vd1")
                self.assertEqual("".join(self.e.commits), "好")
                self.e.do_reset()
                self.e.commits.clear()

    def test_reset_drops_held_text_and_modifier_chord(self):
        self.type_text("vdhel")
        self.key(IBus.KEY_Control_L)
        self.key(IBus.KEY_Shift_L, IBus.ModifierType.CONTROL_MASK)
        self.e.do_reset()
        self.key(IBus.KEY_Shift_L, IBus.ModifierType.RELEASE_MASK)
        self.key(IBus.KEY_Control_L, IBus.ModifierType.RELEASE_MASK)
        self.assertEqual(self.e.preedit, ("", False))
        self.assertFalse(self.e.auxiliary[1])
        self.type_text("vd1")
        self.assertEqual("".join(self.e.commits), "好")

    def assert_association_closed(self):
        self.assertFalse(self.e.lookup_visible)
        self.assertEqual(shell.ENGINE.property(self.e.sess, "kinfx_assoc_code"), "")
        self.assertEqual(shell.ENGINE.property(self.e.sess, "kinfx_candidate_click"), "")
        # A later update must not resurrect the placeholder.
        shell.ENGINE.clear(self.e.sess)
        self.e._update()
        self.assertFalse(self.e.lookup_visible)

    def test_association_clicks_all_current_page_slots_pick_literal_suffixes(self):
        for next_page in (False, True):
            for index in range(int(shell.ENGINE.settings["page_size"])):
                with self.subTest(index=index, next_page=next_page):
                    self.e.do_reset()
                    self.e.commits.clear()
                    self.type_text("vd1")
                    if next_page:
                        self.key(IBus.KEY_space)
                    want = shell.ENGINE.view(self.e.sess)[3][index][0]
                    self.e.do_candidate_clicked(index, 1, IBus.ModifierType.BUTTON1_MASK)
                    self.assertEqual("".join(self.e.commits), "好" + want)
                    self.assertEqual(shell.ENGINE.property(self.e.sess, "kinfx_punct_tail"), "other")
                    self.assert_association_closed()

    def test_ninth_association_click_picks_displayed_suffix_not_shift9(self):
        self.type_text("vd1")
        if len(shell.ENGINE.view(self.e.sess)[3]) < 9:
            self.e.do_candidate_clicked(8, 1, 0)
            self.assertEqual("".join(self.e.commits), "好")
            self.assertTrue(self.e.lookup_visible)
            return
        want = shell.ENGINE.view(self.e.sess)[3][8][0]
        self.e.do_candidate_clicked(8, 1, 0)
        self.assertEqual("".join(self.e.commits), "好" + want)
        self.assertFalse(self.e.lookup_visible)

    def test_normal_click_opens_association_and_suffix_punctuation_matches_keyboard(self):
        self.type_text("vd")
        self.e.do_candidate_clicked(0, 1, 0)
        self.assertEqual("".join(self.e.commits), "好")
        self.assertTrue(self.e.lookup_visible)
        self.assertTrue(shell.ENGINE.property(self.e.sess, "kinfx_assoc_code"))
        want = shell.ENGINE.view(self.e.sess)[3][0][0]
        self.e.do_candidate_clicked(0, 1, 0)
        self.key(ord("."))
        clicked = "".join(self.e.commits)
        self.e.do_reset()
        self.e.commits.clear()
        self.type_text("vd1")
        self.key(ord("!"), IBus.ModifierType.SHIFT_MASK)
        self.key(ord("."))
        self.assertEqual(clicked, "".join(self.e.commits))
        self.assertTrue(clicked.startswith("好" + want))

    def test_keyboard_shift9_still_types_parenthesis_not_suffix(self):
        for code in (ord("("), ord("9"), IBus.KEY_KP_9):
            self.e.do_reset()
            self.e.commits.clear()
            self.type_text("vd1")
            self.key(code, IBus.ModifierType.SHIFT_MASK)
            self.assertEqual("".join(self.e.commits), "好(")
            self.assertFalse(self.e.lookup_visible)

    def test_click_uses_current_page_and_rejects_stale_menu(self):
        self.type_text("vd ")
        want = shell.ENGINE.view(self.e.sess)[3][0][0]
        self.e.do_candidate_clicked(0, 1, 0)
        self.assertEqual("".join(self.e.commits), want)
        self.e.do_focus_out()
        self.e.commits.clear()
        self.e.do_candidate_clicked(0, 1, 0)
        self.assertEqual(self.e.commits, [])

    def test_invalid_candidate_events_do_not_type(self):
        for index, button, state in ((-1, 1, 0), (9, 1, 0), (0, 2, 0), (0, 4, 0),
                                    (0, 1, IBus.ModifierType.MOD1_MASK),
                                    (0, 1, IBus.ModifierType.SUPER_MASK)):
            with self.subTest(index=index, button=button, state=state):
                self.type_text("vd")
                self.e.do_candidate_clicked(index, button, state)
                self.assertEqual(self.e.commits, [])
                self.e.do_reset()

    def test_bare_chord_toggles_but_shortcut_does_not(self):
        for alt in (False, True):
            modifier = IBus.KEY_Alt_L if alt else IBus.KEY_Control_L
            for ascii_mode in (True, False):
                self.key(modifier)
                self.key(IBus.KEY_Shift_L)
                self.key(IBus.KEY_Shift_L, IBus.ModifierType.RELEASE_MASK)
                self.key(modifier, IBus.ModifierType.RELEASE_MASK)
                self.e.commits.clear()
                handled = [self.key(ord(c)) for c in "vd1"]
                self.assertEqual(any(handled), not ascii_mode)
                self.assertEqual("".join(self.e.commits), "" if ascii_mode else "好")
                self.e.do_reset()
        self.e.commits.clear()
        self.key(IBus.KEY_Control_L)
        self.key(IBus.KEY_Shift_L)
        self.key(ord("s"), IBus.ModifierType.CONTROL_MASK | IBus.ModifierType.SHIFT_MASK)
        self.key(IBus.KEY_Shift_L, IBus.ModifierType.RELEASE_MASK)
        self.key(IBus.KEY_Control_L, IBus.ModifierType.RELEASE_MASK)
        self.type_text("vd1")
        self.assertEqual("".join(self.e.commits), "好")

    def test_keyboard_paging_shift_digit_and_escape_are_unchanged(self):
        for page_key in (IBus.KEY_space, IBus.KEY_Right):
            self.e.do_reset()
            self.e.commits.clear()
            self.type_text("vd")
            self.assertTrue(self.key(page_key))
            want = shell.ENGINE.view(self.e.sess)[3][0][0]
            self.type_text("1")
            self.assertEqual("".join(self.e.commits), want)
        self.e.do_reset()
        self.e.commits.clear()
        self.type_text("vd1")
        self.key(ord("!"), IBus.ModifierType.SHIFT_MASK)
        self.assertEqual("".join(self.e.commits), "好似")
        self.e.do_reset()
        self.e.commits.clear()
        self.type_text("vdhel")
        self.key(IBus.KEY_Escape)
        self.type_text("vd1")
        self.assertEqual("".join(self.e.commits), "好反好")

    def test_shortcut_modified_candidate_click_does_not_select(self):
        self.type_text("vd")
        self.e.do_candidate_clicked(0, 1, IBus.ModifierType.CONTROL_MASK)
        self.assertEqual(self.e.commits, [])
        self.assertTrue(self.e.lookup_visible)

    def test_focus_out_hides_code_auxiliary(self):
        # The auxiliary text (code shown next to a converted preedit) depends on
        # shared blur data that is still being fixed at base 6ca. Set it visible
        # directly so this asserts only the shell's hide path on focus-out.
        self.type_text("vd")
        self.e.update_auxiliary_text(IBus.Text.new_from_string("vd"), True)
        self.assertTrue(self.e.auxiliary[1])
        self.e.do_focus_out()
        self.assertFalse(self.e.auxiliary[1])

    def test_secure_input_never_reaches_the_dictionary(self):
        self.e.emit("set-content-type", int(IBus.InputPurpose.PASSWORD), 0)
        handled = [self.key(ord(c)) for c in "vd1"]
        self.assertEqual(handled, [False, False, False])
        self.assertEqual(self.e.commits, [])
        self.assertFalse(self.e.lookup_visible)

    def test_out_of_range_candidate_click_does_not_wrap_to_first(self):
        self.type_text("vd")
        self.e.do_candidate_clicked(10, 1, 0)
        self.assertEqual(self.e.commits, [])
        self.assertTrue(self.e.lookup_visible)

    def test_secondary_candidate_click_does_not_select(self):
        self.type_text("vd")
        self.e.do_candidate_clicked(0, 3, 0)
        self.assertEqual(self.e.commits, [])
        self.assertTrue(self.e.lookup_visible)

    def test_disable_discards_preedit_and_held_text_before_reenable(self):
        self.type_text("vdhel")
        self.assertTrue(self.e.preedit[1])
        self.e.emit("disable")
        self.assertEqual(self.e.preedit, ("", False))
        self.assertFalse(self.e.lookup_visible)
        self.e.emit("enable")
        self.type_text("vd1")
        self.assertEqual("".join(self.e.commits), "好")

    def test_focus_out_does_not_complete_a_chord_in_the_next_field(self):
        self.key(IBus.KEY_Control_L)
        self.key(IBus.KEY_Shift_L, IBus.ModifierType.CONTROL_MASK)
        self.e.do_focus_out()
        self.e.do_focus_in()
        self.key(IBus.KEY_Shift_L, IBus.ModifierType.RELEASE_MASK)
        self.key(IBus.KEY_Control_L, IBus.ModifierType.RELEASE_MASK)
        self.type_text("vd1")
        self.assertEqual("".join(self.e.commits), "好")

    def _manufacture_failed_latch(self, tail=1):
        # A failed-latched rebuild leaves the owner's idle reservation (latin tail)
        # with no native session. Build that shape directly (native gone, idle
        # reservation kept) without a real redeploy so the suite stays clean.
        e = shell.ENGINE
        self.key(ord("v"))  # force _session() to create the owner
        h = self.e.sess
        self.assertTrue(e.alive(h))
        sid = e.native_session(h)
        options = [e.lib.kx_option(sid, k.encode()) for k in e.SWITCHES]
        e.lib.kx_destroy(sid)
        e.sessions.clear()
        e.undrained.clear()
        e.retry_runtime[h] = {"options": options, "tail": tail, "digit": 0}
        e.native_rebuild_failed = True
        e.reload_pending = False
        self.assertFalse(e.alive(h))
        self.assertTrue(e.owns(h))
        return h, options

    def _assert_routing_revoked(self, h, options):
        e = shell.ENGINE
        self.assertIn(h, e.retry_runtime)
        self.assertEqual(e.retry_runtime[h]["tail"], 0)
        self.assertEqual(e.retry_runtime[h]["options"][1], options[1])  # width kept
        # Restore for the next test.
        e.retry_runtime.pop(h, None)
        e.native_rebuild_failed = False

    def test_terminal_actions_revoke_routing_when_native_unavailable(self):
        # Every frontend terminal action (focus-out, reset, disable, secure) must
        # revoke the failed-latched owner's latin routing, so a later explicit
        # retry types full-width punctuation (hello。) rather than hello.
        actions = [
            ("focus-out", lambda: self.e.do_focus_out()),
            ("reset", lambda: self.e.do_reset()),
            ("disable", lambda: self.e.do_disable()),
            ("secure", lambda: self.e.do_set_content_type(IBus.InputPurpose.PASSWORD, 0)),
        ]
        for name, act in actions:
            with self.subTest(action=name):
                h, options = self._manufacture_failed_latch()
                act()
                self._assert_routing_revoked(h, options)
                if name == "secure":
                    self.e.secure = False


if __name__ == "__main__":
    unittest.main(verbosity=2)
