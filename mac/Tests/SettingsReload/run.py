#!/usr/bin/env python3
"""Private native/hosted AppKit tests. No install, registration or OS key events."""
from pathlib import Path
import json, os, re, resource, shutil, subprocess, sys, tempfile
TESTS = Path(__file__).resolve().parent
TREE = Path(os.environ.get('KINFX_SOURCE_TREE', TESTS.parents[2])).resolve()
RIME = Path(os.environ.get('KINFX_RIME_DIR', TREE/'mac/build/rime')).resolve()/'dist'
OUT = Path(os.environ.get('KINFX_TEST_OUT') or tempfile.mkdtemp(prefix='kinfx-settings-reload-', dir=os.environ.get('TMPDIR'))).resolve()
OUT.mkdir(parents=True, exist_ok=True)
SWIFT = os.environ.get('SWIFTC', 'swiftc')
SDK = os.environ.get('SDKROOT') or subprocess.check_output(['xcrun','--show-sdk-path'],text=True).strip()
ENV = dict(os.environ,TMPDIR=str(OUT),PYTHONDONTWRITEBYTECODE='1')
def run(cmd, out):
    cmd=list(map(str,cmd))
    p=subprocess.run(cmd,capture_output=True,text=True,env=ENV,timeout=180,
                     preexec_fn=lambda:resource.setrlimit(resource.RLIMIT_CORE,(0,0)))
    record={'command':cmd,'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
    (out/f'cmd-{len(list(out.glob("cmd-*.json")))}.json').write_text(json.dumps(record,ensure_ascii=False,indent=2))
    return p
summary=[]
for suite in sys.argv[1:] or ['retry','legacy-settings','legacy-controller','failure-seams','persistence-io']:
    assert suite in ['retry','legacy-settings','legacy-controller','failure-seams','persistence-io','baseline-repro'],suite
    out=OUT/suite;out.mkdir()
    data=out/'data';data.mkdir()
    for p in (TREE/'engine/prelude').glob('*.yaml'):shutil.copy2(p,data/p.name)
    shutil.copytree(TREE/'engine/rime',data,dirs_exist_ok=True)
    # A second valid dictionary makes wrong-default selection distinct from a
    # missing schema: select can lie true while get_status still names KINFX.
    if suite=='failure-seams':
        source=(data/'kinfx_quick.schema.yaml').read_text()
        (data/'qa_other_schema.schema.yaml').write_text(source.replace('schema_id: kinfx_quick','schema_id: qa_other_schema',1))
    p=data/'default.yaml';s,n=re.subn(r'schema_list:\n(  - schema: \w+\n)+','schema_list:\n  - schema: kinfx_quick\n',p.read_text());assert n==1;p.write_text(s)
    test=TESTS/('main.swift' if suite=='retry' else suite+'.swift')
    shutil.copy2(test,out/'main.swift')
    common=['-isysroot',SDK,'-mmacosx-version-min=12.0','-I',RIME/'include','-I',TREE/'mac/Sources/Shim']
    shim=TREE/'mac/Sources/Shim/kx_shim.c'
    if suite in ['legacy-settings','failure-seams']:
        # Include the selected source tree, not the runner's tree, for A/B probes.
        s=(TESTS/'TestShim.c').read_text().replace('../../Sources/Shim/kx_shim.c',str(shim))
        (out/'TestShim.c').write_text(s);shim=out/'TestShim.c'
    p=run(['clang','-dynamiclib',*common,'-O2',shim,'-L',RIME/'lib','-lrime','-Wl,-rpath,'+str(RIME/'lib'),'-o',out/'shim.dylib'],out)
    if p.returncode:raise RuntimeError(p.stderr)
    sources=[*sorted((TREE/'mac/Sources/Engine').glob('*.swift'))]
    if suite in ['legacy-settings','failure-seams']:
        bridge=TESTS/'TestBridge.h';sources += [TESTS/'SettingsStubs.swift',TREE/'mac/Sources/App/SettingsWindow.swift']
        objs=[]
    else:
        bridge=TESTS/'QAClient.h'
        p=run(['clang',*common,'-fobjc-arc','-c',TESTS/'QAClient.m','-o',out/'QAClient.o'],out)
        if p.returncode:raise RuntimeError(p.stderr)
        objs=[out/'QAClient.o']
        sources += [TREE/'mac/Sources/App/InputController.swift',TREE/'mac/Sources/App/AppInfo.swift',TREE/'mac/Sources/App/SettingsWindow.swift']
    p=run([SWIFT,'-D','CONTEXT_TAIL_API','-sdk',SDK,'-target',os.uname().machine+'-apple-macos12.0','-swift-version','5','-module-cache-path',OUT/'module-cache','-import-objc-header',bridge,'-I',TREE/'mac/Sources/Shim',*sources,out/'main.swift',*objs,out/'shim.dylib','-framework','InputMethodKit','-L',RIME/'lib','-lrime','-Xlinker','-rpath','-Xlinker',RIME/'lib','-o',out/'probe'],out)
    if p.returncode:raise RuntimeError(p.stderr)
    p=run([out/'probe',out],out)
    rows=[json.loads(s) for s in p.stdout.splitlines() if s.startswith('{')]
    (out/'rows.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
    row={'suite':suite,'source':str(TREE),'exit':p.returncode,'checks':len(rows),'failed':sum(not x['pass'] for x in rows),'raw':str(out)}
    expected={'retry':27,'legacy-settings':62,'legacy-controller':43,'failure-seams':14,'persistence-io':24,'baseline-repro':1}
    assert len(rows)==expected[suite],f'Incomplete {suite}: {len(rows)}/{expected[suite]} assertions'
    summary.append(row);print(json.dumps(row),flush=True)
(OUT/'summary.json').write_text(json.dumps(summary,indent=2))
sys.exit(1 if any(r['exit'] or r['failed'] for r in summary) else 0)
