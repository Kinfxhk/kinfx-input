"""Document-manager teardown must tolerate a successful null COM output."""
from pathlib import Path
import unittest

class DocumentUninitSafety(unittest.TestCase):
    def test_successful_null_document_is_not_dereferenced(self):
        text = (Path(__file__).parents[1] / 'tip' / 'tip.cpp').read_text(encoding='utf-8')
        start = text.index('STDMETHODIMP OnUninitDocumentMgr(')
        body = text[start:text.index('STDMETHODIMP OnSetFocus(', start)]
        self.assertRegex(body, r'if\s*\(focus_\s*&&\s*SUCCEEDED\(focus_->GetDocumentMgr\(&owner\)\)\s*&&\s*owner\)')
        self.assertIn('owner->Release();', body)

if __name__ == '__main__':
    unittest.main()
