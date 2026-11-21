#!/usr/bin/env python3
"""Sync KINFX Input's embedded Rime engine from Kinfxhk/kinfx-ime (single source of truth).

Usage:
  # Sync from a local checkout of kinfx-ime:
  python3 scripts/sync-engine.py --from-dir ../kinfx-ime

  # Sync from a GitHub tag/branch of Kinfxhk/kinfx-ime:
  python3 scripts/sync-engine.py --ref v0.6.0

  # Verify zero drift in CI (exit 1 if engine/rime/ differs from source + overlay):
  python3 scripts/sync-engine.py --from-dir ../kinfx-ime --check
"""
from __future__ import annotations

import argparse
import datetime as dt
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
ENGINE_RIME = ROOT / "engine" / "rime"
ENGINE_LICENSES = ROOT / "engine" / "licenses"
ENGINE_VERSION_FILE = ROOT / "engine" / "ENGINE_VERSION.json"
SOURCE_MD = ROOT / "engine" / "SOURCE.md"

DEFAULT_REPO_URL = "https://github.com/Kinfxhk/kinfx-ime.git"

# Exact file mapping: (relative path in kinfx-ime) -> (relative path in engine/rime)
RIME_FILE_MAP: list[tuple[str, str]] = [
    ("schemas/kinfx-quick/kinfx_quick.schema.yaml", "kinfx_quick.schema.yaml"),
    ("schemas/kinfx-quick/kinfx_quick.dict.yaml", "kinfx_quick.dict.yaml"),
    ("schemas/kinfx-quick/kinfx_phrase.schema.yaml", "kinfx_phrase.schema.yaml"),
    ("schemas/kinfx-quick/kinfx_en.schema.yaml", "kinfx_en.schema.yaml"),
    ("schemas/kinfx-quick/kinfx_names.schema.yaml", "kinfx_names.schema.yaml"),
    ("schemas/kinfx-quick/kinfx_assoc.schema.yaml", "kinfx_assoc.schema.yaml"),
    ("lexicon/hk/kinfx_assoc.dict.yaml", "kinfx_assoc.dict.yaml"),
    ("lexicon/hk/kinfx_capture.txt", "kinfx_capture.txt"),
    ("lexicon/hk/kinfx_hk_idioms.dict.yaml", "kinfx_hk_idioms.dict.yaml"),
    ("lexicon/hk/kinfx_hk_words.dict.yaml", "kinfx_hk_words.dict.yaml"),
    ("lexicon/hk/kinfx_quick_phrase.dict.yaml", "kinfx_quick_phrase.dict.yaml"),
    ("lexicon/en/kinfx_en.dict.yaml", "kinfx_en.dict.yaml"),
    ("lexicon/en/kinfx_en_names.txt", "kinfx_en_names.txt"),
    ("lexicon/en/kinfx_en_unsafe.txt", "kinfx_en_unsafe.txt"),
    ("lexicon/en/kinfx_names.dict.yaml", "kinfx_names.dict.yaml"),
    ("schemas/rime.lua", "rime.lua"),
    ("schemas/lua/assoc.lua", "lua/assoc.lua"),
    ("schemas/lua/english_mix.lua", "lua/english_mix.lua"),
    ("schemas/lua/phrase_mix.lua", "lua/phrase_mix.lua"),
    ("schemas/lua/win_quick.lua", "lua/win_quick.lua"),
]

LICENSE_FILE_MAP: list[tuple[str, str]] = [
    ("LICENSE", "kinfx-ime-LICENSE.txt"),
    ("NOTICE", "kinfx-ime-NOTICE.txt"),
    ("lexicon/NOTICE", "lexicon-NOTICE.txt"),
    ("licenses/rime-quick-LGPL-3.0.txt", "rime-quick-LGPL-3.0.txt"),
]


def apply_kinfx_input_schema_overlay(schema_text: str) -> str:
    """Apply KINFX Input's minimal standalone-shell overlay to kinfx_quick.schema.yaml.

    1. Remove punctuator/half_shape overrides so engine/prelude/punctuation.yaml
       (shared by Win/Mac/Linux shells) is the sole punctuation authority.
    2. Remove recognizer/patterns/reverse_lookup so backtick (`) outputs ASCII
       immediately without opening a reverse-lookup menu.
    """
    # 1. Replace punctuator block's half_shape section with a clear comment.
    punct_re = re.compile(
        r"(punctuator:\n  import_preset: default\n)"
        r".*?"
        r"(  digit_separators: \".:,'\"\n)",
        re.DOTALL,
    )
    punct_replacement = (
        r"\1"
        "  # KINFX Input overlay (synced by scripts/sync-engine.py):\n"
        "  # 標點全部由 engine/prelude/punctuation.yaml（三平台共用）單鍵直出，呢度唔再覆寫。\n"
        "  # 數字後面嘅 . : , ' 留半形（20,000、3.14、12:30）；連撳兩下先出中文標點。\n"
        r"\2"
    )
    out, n1 = punct_re.subn(punct_replacement, schema_text, count=1)
    if n1 != 1:
        raise RuntimeError(
            "Overlay failed: could not locate punctuator/half_shape block in kinfx_quick.schema.yaml"
        )

    # 2. Enable ASCII-default punctuation behavior for standalone shells.
    blur_re = re.compile(r"(  blur_short: letters\n)")
    out, n2 = blur_re.subn(
        r"\1  # KINFX Input overlay: half_shape is ASCII, full_shape is Chinese.\n  ascii_punct_default: true\n",
        out,
        count=1,
    )
    if n2 != 1:
        raise RuntimeError(
            "Overlay failed: could not locate english/blur_short in kinfx_quick.schema.yaml"
        )

    # 3. Remove reverse_lookup recognizer pattern (keep backtick instant ASCII).
    rev_re = re.compile(r"\n    reverse_lookup: \"`\[a-z\]\*'\?\$\"")
    out, n3 = rev_re.subn("", out, count=1)
    if n3 != 1:
        raise RuntimeError(
            "Overlay failed: could not locate recognizer/patterns/reverse_lookup in kinfx_quick.schema.yaml"
        )

    return out


def extract_schema_version(schema_text: str) -> str:
    m = re.search(r'^  version:\s*"([^"]+)"', schema_text, re.MULTILINE)
    return m.group(1) if m else "unknown"


def git_info(repo_dir: Path) -> tuple[str, str]:
    def run(args: list[str]) -> str:
        res = subprocess.run(
            ["git", "-C", str(repo_dir), *args],
            capture_output=True,
            text=True,
        )
        return res.stdout.strip() if res.returncode == 0 else ""

    commit = run(["rev-parse", "HEAD"]) or "unknown"
    tag = run(["describe", "--tags", "--exact-match"]) or run(["rev-parse", "--abbrev-ref", "HEAD"])
    return commit, tag


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def render_source_md(meta: dict) -> str:
    return f"""# engine/

本目錄的 `rime/` 由核心引擎倉庫 [`Kinfxhk/kinfx-ime`](https://github.com/Kinfxhk/kinfx-ime) 自動同步，**請勿直接手改 `engine/rime/`**。

- **單一核心引擎來源**：`{meta["source_repo"]}`
- **Schema 版本**：`v{meta["schema_version"]}`
- **同步來源參考**：`{meta["source_ref"]}`（commit `{meta["source_commit"]}`）
- **同步時間（UTC）**：`{meta["synced_at"]}`

## 如何更新引擎

所有中英混打、速成次序、聯想詞與詞庫改動，一律先在 `kinfx-ime` 修改並通過回歸測試，再於本 repo 執行：

```bash
# 由本地鄰近目錄同步
python3 scripts/sync-engine.py --from-dir ../kinfx-ime

# 或由 GitHub 指定 tag 同步
python3 scripts/sync-engine.py --ref v{meta["schema_version"]}

# 檢查本目錄與上游是否零漂移（CI 用）
python3 scripts/sync-engine.py --from-dir ../kinfx-ime --check
```

## 獨立版專屬覆寫（Overlay）

`scripts/sync-engine.py` 在同步 `kinfx_quick.schema.yaml` 時只會套用兩項最小覆寫，其餘所有 Lua 與詞庫均與 `kinfx-ime` 逐位元一致：

1. **移除 `punctuator/half_shape`**：由 `engine/prelude/punctuation.yaml` 統一控制三平台單鍵標點與半形預設，避免兩份標點表衝突。
2. **移除 `recognizer/patterns/reverse_lookup`**：讓反引號 `` ` `` 直接輸出半形 ASCII，不彈出拼音反查選單。

## 其他目錄

- `prelude/`：`rime/rime-prelude` 基底加上 KINFX Input 共用 `punctuation.yaml`（LGPL-3.0）。
- `licenses/`：由 `kinfx-ime` 同步的 `LICENSE`、`NOTICE` 與詞庫授權說明。
"""


def build_expected_tree(src_dir: Path) -> tuple[dict[Path, bytes], str]:
    expected: dict[Path, bytes] = {}
    schema_version = "unknown"

    for src_rel, dst_rel in RIME_FILE_MAP:
        src_path = src_dir / src_rel
        if not src_path.is_file():
            raise FileNotFoundError(f"Missing expected source file: {src_path}")
        raw = src_path.read_bytes()
        if dst_rel == "kinfx_quick.schema.yaml":
            text = raw.decode("utf-8")
            schema_version = extract_schema_version(text)
            raw = apply_kinfx_input_schema_overlay(text).encode("utf-8")
        expected[ENGINE_RIME / dst_rel] = raw

    for src_rel, dst_rel in LICENSE_FILE_MAP:
        src_path = src_dir / src_rel
        if not src_path.is_file():
            raise FileNotFoundError(f"Missing expected license file: {src_path}")
        expected[ENGINE_LICENSES / dst_rel] = src_path.read_bytes()

    return expected, schema_version


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync KINFX Input engine from kinfx-ime.")
    src_group = parser.add_mutually_exclusive_group(required=True)
    src_group.add_argument("--from-dir", type=Path, help="Path to local kinfx-ime checkout")
    src_group.add_argument("--ref", type=str, help="Git tag or branch to clone from kinfx-ime")
    parser.add_argument("--repo-url", default=DEFAULT_REPO_URL, help="Git URL when using --ref")
    parser.add_argument("--check", action="store_true", help="Verify engine/rime/ matches source without writing")
    args = parser.parse_args()

    tmp_dir: Path | None = None
    try:
        if args.from_dir:
            src_dir = args.from_dir.resolve()
            if not src_dir.is_dir():
                print(f"ERROR: source directory not found: {src_dir}", file=sys.stderr)
                return 2
            commit, ref_name = git_info(src_dir)
        else:
            tmp_dir = Path(tempfile.mkdtemp(prefix="kinfx-ime-sync-"))
            subprocess.run(
                ["git", "clone", "--depth", "1", "--branch", args.ref, args.repo_url, str(tmp_dir)],
                check=True,
            )
            src_dir = tmp_dir
            commit, _ = git_info(src_dir)
            ref_name = args.ref

        expected, schema_version = build_expected_tree(src_dir)

        if args.check:
            drifts: list[str] = []
            for dst_path, want_bytes in sorted(expected.items()):
                rel = dst_path.relative_to(ROOT)
                if not dst_path.is_file():
                    drifts.append(f"MISSING: {rel}")
                    continue
                got_bytes = dst_path.read_bytes()
                if got_bytes != want_bytes:
                    drifts.append(f"DIFF: {rel}")
                    if dst_path.suffix in {".lua", ".yaml", ".txt"}:
                        diff_lines = list(
                            difflib.unified_diff(
                                got_bytes.decode("utf-8", errors="replace").splitlines(),
                                want_bytes.decode("utf-8", errors="replace").splitlines(),
                                fromfile=f"current/{rel}",
                                tofile=f"expected/{rel}",
                                n=2,
                                lineterm="",
                            )
                        )
                        for line in diff_lines[:20]:
                            drifts.append(f"  {line}")
            if drifts:
                print("ENGINE DRIFT DETECTED:", file=sys.stderr)
                for d in drifts:
                    print(d, file=sys.stderr)
                return 1
            print(f"OK: engine/rime matches kinfx-ime v{schema_version} ({commit[:7]}) with 0 drift.")
            return 0

        # Write synced files
        for dst_path, data in expected.items():
            dst_path.parent.mkdir(parents=True, exist_ok=True)
            dst_path.write_bytes(data)

        meta = {
            "source_repo": "Kinfxhk/kinfx-ime",
            "schema_version": schema_version,
            "source_ref": ref_name,
            "source_commit": commit,
            "synced_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "overlay": [
                "remove punctuator/half_shape (delegated to engine/prelude/punctuation.yaml)",
                "set english/ascii_punct_default: true (half_shape ASCII, full_shape Chinese)",
                "remove recognizer/patterns/reverse_lookup (backtick stays ASCII)",
            ],
            "files": {
                str(p.relative_to(ROOT)): sha256_bytes(b)[:16]
                for p, b in sorted(expected.items())
            },
        }
        ENGINE_VERSION_FILE.write_text(
            json.dumps(meta, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        SOURCE_MD.write_text(render_source_md(meta), encoding="utf-8")
        print(
            f"Synced {len(expected)} files from kinfx-ime v{schema_version} ({commit[:7]}) -> engine/rime/"
        )
        return 0
    finally:
        if tmp_dir and tmp_dir.exists():
            shutil.rmtree(tmp_dir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
