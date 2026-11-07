#!/usr/bin/env python3
"""Production Linux Engine.blur_text vs F35; real librime, isolated user.

--core PATH_TO_LINUX_DIR --share STAGED_SHARE --work NEW_DIR --output JSON
Does not simulate GUI focus. F35 is the engine's blur protocol only.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys


def run(a):
    a.work.mkdir(parents=True, exist_ok=False)
    os.environ['KX_SHARE'] = str(a.share)
    os.environ['KX_USER'] = str(a.work)
    sys.path.insert(0, str(a.core))
    from kxcore import Engine
    engine = Engine(share=str(a.share), user=str(a.work))
    assert engine.start()
    rows = []

    def type_(s, word):
        for c in word:
            engine.key(s, ord(c), 1 if c.isupper() else 0)
            engine.commit(s)  # already delivered top-outs/picks are not blur text

    def check(name, got, want):
        rows.append(dict(name=name, got=got, want=want, pass_=got == want))
        print('PASS' if got == want else 'FAIL', name, repr(got), 'want', repr(want), flush=True)
        a.output.write_text(json.dumps(dict(core=str(a.core), share=str(a.share),
            lua_sha256=hashlib.sha256((a.share/'data/lua/english_mix.lua').read_bytes()).hexdigest(),
            rows=rows), ensure_ascii=False, indent=2))

    for word, want in [('hel', 'hel'), ('vdhel', 'vdhel'), ('vd1hel', 'hel'),
                       ('hello', 'hello'), ('vd', 'vd'), ('he', 'he'),
                       ('openai.co', 'openai.co'), ('iPhone', 'iPhone'),
                       ('asxz', 'asxz'), ('abcd', 'abcd'),
                       ('asxe', '昨xe'), ('asxl', '昨xl'), ('asxs', '昨xs'),
                       ('asxv', '昨xv'), ('asxx', '昨xx'), ('abxx', '明xx'),
                       ('hello.', 'hello.'), ('hello-', 'hello-'),
                       ('https://x.com', 'https://x.com'), ('BTCUSDT', 'BTCUSDT'),
                       ('me@example.com', 'me@example.com')]:
        s = engine.session()
        type_(s, word)
        before = engine.blur_text(s)
        check('Engine.blur_text '+word, before, want)
        engine.key(s, 0xffe0, 0)
        committed = engine.commit(s) or ''
        check('F35 '+word, committed, want)
        check('property/F35 parity '+word, before, committed)
        check('property cleared after F35 '+word, engine.blur_text(s), '')
        type_(s, 'vd')
        engine.key(s, ord('1'), 0)
        check('Chinese pick after F35 '+word, engine.commit(s) or '', '好')
        engine.lib.kx_destroy(s)

    s = engine.session()
    type_(s, 'hel')
    before = engine.blur_text(s)
    t = engine.session()
    type_(t, 'hello')
    check('first context property survives second context', engine.blur_text(s), 'hel')
    check('second context property independent', engine.blur_text(t), 'hello')
    engine.key(s, 0xffe0, 0)
    check('interleaved first F35', engine.commit(s) or '', before)
    engine.key(t, 0xffe0, 0)
    check('interleaved second F35', engine.commit(t) or '', 'hello')
    engine.lib.kx_destroy(s)
    engine.lib.kx_destroy(t)
    failed = sum(not r['pass_'] for r in rows)
    print(json.dumps(dict(total=len(rows), failed=failed)))
    return bool(failed)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for n in ('core', 'share', 'work', 'output'):
        p.add_argument('--'+n, type=Path, required=True)
    raise SystemExit(run(p.parse_args()))
