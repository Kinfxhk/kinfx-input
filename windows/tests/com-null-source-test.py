"""Host-implemented TSF COM outputs may be null on success; never dereference them unchecked."""
from pathlib import Path
import re, unittest

SRC = (Path(__file__).parents[1] / 'tip' / 'tip.cpp').read_text(encoding='utf-8')

class ComNullOutputs(unittest.TestCase):
    def test_every_host_output_is_null_checked(self):
        calls = r'(GetRange|Clone|GetActiveView|GetCompartment|GetDocumentMgr|InsertTextAtSelection)'
        bad = []
        for m in re.finditer(r'(SUCCEEDED|FAILED)\(([a-z_]+)->' + calls + r'\([^;{]*?&([a-z_]+)\)\)', SRC):
            kind, out = m.group(1), m.group(4)
            tail = SRC[m.end():m.end() + 12]
            ok = (kind == 'SUCCEEDED' and re.match(r'\s*&&\s*' + out + r'\b', tail)) or \
                 (kind == 'FAILED' and re.match(r'\s*\|\|\s*!' + out + r'\b', tail))
            if not ok:
                bad.append(SRC[m.start():m.end() + 12])
        self.assertEqual(bad, [])

    def test_get_top_failure_clears_output(self):
        self.assertNotRegex(SRC, r'(?m)^\s*(if \(doc\) )?doc->GetTop\(&c\);')
        self.assertEqual(SRC.count('FAILED(doc->GetTop(&c))) c = nullptr;'), 2)

if __name__ == '__main__':
    unittest.main()
