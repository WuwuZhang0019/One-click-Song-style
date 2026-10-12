"""find_non_gb2312.py - 列出 UTF-8 源码中无法用严格 GB2312 表示的字符及位置。

用法：python -X utf8 tools/find_non_gb2312.py [文件...]
默认检查仓库根目录的 one-click-simsun.lsp。
"""

from __future__ import annotations

from pathlib import Path

DEFAULT_FILES = ["one-click-simsun.lsp"]


def scan(path: Path) -> list[tuple[int, int, str, str]]:
    text = path.read_bytes().decode("utf-8-sig", errors="strict")
    bad: list[tuple[int, int, str, str]] = []
    line = 1
    col = 1
    for ch in text:
        if ch == "\n":
            line += 1
            col = 1
            continue
        try:
            ch.encode("gb2312", errors="strict")
        except UnicodeEncodeError:
            bad.append((line, col, ch, f"U+{ord(ch):04X}"))
        col += 1
    return bad


def main() -> int:
    import sys

    root = Path(__file__).resolve().parent.parent
    files = sys.argv[1:] or DEFAULT_FILES
    total = 0
    for name in files:
        p = Path(name)
        if not p.is_absolute():
            p = root / name
        bad = scan(p)
        total += len(bad)
        print(f"== {p} : {len(bad)} non-GB2312 char(s)")
        for line, col, ch, code in bad:
            print(f"  {p.name}:{line}:{col} {ch!r} {code}")
    print(f"TOTAL: {total}")
    return 1 if total else 0


if __name__ == "__main__":
    raise SystemExit(main())
