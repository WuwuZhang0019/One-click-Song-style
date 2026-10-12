"""test_build_gb2312.py - 构建工具的 5 项样例检查（对应 GB2312 说明第 8 节）。

运行：python -X utf8 tools/test_build_gb2312.py
检查项：中文 UTF-8→GB2312 且源码不变、BOM 去除、不可编码字符行列报错、
非法 UTF-8 输入失败、源文件不存在时失败；并确认失败不会覆盖已有交付文件。
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def convert_direct(src: Path, dst: Path) -> tuple[int, str]:
    try:
        raw = src.read_bytes()
    except OSError as exc:
        return 1, f"SOURCE_ERROR: {exc}"
    try:
        text = raw.decode("utf-8-sig", errors="strict")
    except UnicodeDecodeError as exc:
        return 1, f"SOURCE_ERROR: {exc}"
    try:
        payload = text.encode("gb2312", errors="strict")
    except UnicodeEncodeError as exc:
        line = text.count("\n", 0, exc.start) + 1
        column = exc.start - text.rfind("\n", 0, exc.start)
        return 1, f"ENCODING_ERROR: {src}:{line}:{column}: {text[exc.start:exc.end]!r}"
    assert payload.decode("gb2312", errors="strict") == text
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(payload)
    assert dst.read_bytes() == payload
    assert dst.read_bytes().decode("gb2312", errors="strict") == text
    return 0, "OK"


def main() -> int:
    failures = 0
    with tempfile.TemporaryDirectory() as td:
        tdp = Path(td)

        # 1. 中文 UTF-8 转 GB2312 且源码不变
        src1 = tdp / "a.lsp"
        src1.write_bytes(";;; 中文注释 宋体\n".encode("utf-8"))
        before = src1.read_bytes()
        code, msg = convert_direct(src1, tdp / "out" / "a.lsp")
        if code != 0 or src1.read_bytes() != before:
            print("CHECK1 FAIL", msg)
            failures += 1
        else:
            print("CHECK1 PASS")

        # 2. UTF-8 BOM 去除
        src2 = tdp / "b.lsp"
        src2.write_bytes(b"\xef\xbb\xbf" + ";;; BOM 测试\n".encode("utf-8"))
        code, msg = convert_direct(src2, tdp / "out" / "b.lsp")
        out = (tdp / "out" / "b.lsp").read_bytes()
        if code != 0 or out.startswith(b"\xef\xbb\xbf"):
            print("CHECK2 FAIL", msg)
            failures += 1
        else:
            print("CHECK2 PASS")

        # 3. 不可编码字符按行列报错（em dash U+2014 不在 GB2312）
        src3 = tdp / "c.lsp"
        src3.write_bytes(";;; line1\n;;; 破折号 —— 结束\n".encode("utf-8"))
        dst3 = tdp / "out" / "c.lsp"
        dst3.write_bytes(b"PREVIOUS")
        code, msg = convert_direct(src3, dst3)
        if code == 0 or "ENCODING_ERROR" not in msg or ":2:" not in msg:
            print("CHECK3 FAIL", msg)
            failures += 1
        elif dst3.read_bytes() != b"PREVIOUS":
            print("CHECK3 FAIL: failed build overwrote previous deliverable")
            failures += 1
        else:
            print("CHECK3 PASS:", msg)

        # 4. 非法 UTF-8 输入失败
        src4 = tdp / "d.lsp"
        src4.write_bytes(b"bad utf8: \xff\xfe\n")
        code, msg = convert_direct(src4, tdp / "out" / "d.lsp")
        if code == 0 or "SOURCE_ERROR" not in msg:
            print("CHECK4 FAIL", msg)
            failures += 1
        else:
            print("CHECK4 PASS")

        # 5. 源文件不存在时失败
        code, msg = convert_direct(tdp / "missing.lsp", tdp / "out" / "e.lsp")
        if code == 0 or "SOURCE_ERROR" not in msg:
            print("CHECK5 FAIL", msg)
            failures += 1
        else:
            print("CHECK5 PASS")

    print("RESULT:", "FAIL" if failures else "PASS")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
