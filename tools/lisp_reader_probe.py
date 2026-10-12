# -*- coding: utf-8 -*-
"""lisp_reader_probe.py - 模拟 AutoLISP 读入器，定位交付文件中的读入期语法错误。

AutoLISP LOAD 期读入规则（与本探针一致）：
- 空白分隔 token；`;` 到行尾为注释；`"` 开始字符串，`\\` 转义下一字节，遇未转义 `"` 结束；
- `(` `)` 控制列表深度，`'` 为 quote 前缀；
- 读到文件尾时深度 > 0 → 语法错误；深度 < 0 → 语法错误；字符串未闭合 → 语法错误；
- 额外报告：字符串内出现裸控制字符、原子中含非 ASCII（DBCS 符号，引擎兼容性风险）。
用法： python -X utf8 tools/lisp_reader_probe.py <file.lsp>
"""
from __future__ import annotations

import sys
from pathlib import Path

WS = " \t\r\n\f\v"


def probe(text: str):
    """返回 (errors, warnings)。errors 为读入期语法错误列表。"""
    errors = []
    warnings = []
    depth = 0
    i = 0
    n = len(text)
    line = 1
    col = 1

    def adv(k=1):
        nonlocal i, line, col
        for _ in range(k):
            if i < n and text[i] == "\n":
                line += 1
                col = 1
            else:
                col += 1
            i += 1

    in_string = False
    str_start = (0, 0)
    while i < n:
        c = text[i]
        if in_string:
            if c == "\\":
                # 转义：吃掉反斜杠与下一个字符
                if i + 1 >= n:
                    errors.append((line, col, "字符串以孤立反斜杠结尾（未闭合）"))
                    adv(1)
                    in_string = False
                    continue
                nxt = text[i + 1]
                if nxt not in '"\\nrt e' and nxt not in ('"', "\\", "n", "r", "t", "e", "U", "u"):
                    warnings.append((line, col, f"字符串内非标准转义 \\{nxt!r}"))
                adv(2)
                continue
            if c == '"':
                in_string = False
                adv(1)
                continue
            if ord(c) < 32 and c not in "\t\r\n":
                errors.append((line, col, f"字符串内出现控制字符 U+{ord(c):04X}"))
            adv(1)
            continue
        if c in WS:
            adv(1)
            continue
        if c == ";":
            while i < n and text[i] != "\n":
                adv(1)
            continue
        if c == '"':
            in_string = True
            str_start = (line, col)
            adv(1)
            continue
        if c == "(":
            depth += 1
            adv(1)
            continue
        if c == ")":
            depth -= 1
            if depth < 0:
                errors.append((line, col, "多余的右括号（列表提前闭合）"))
                depth = 0
            adv(1)
            continue
        if c == "'":
            adv(1)
            continue
        # 原子：读到 空白/括号/引号/分号 为止
        start = (line, col)
        atom = ""
        while i < n and text[i] not in WS and text[i] not in '()"\';':
            atom += text[i]
            adv(1)
        if any(ord(ch) > 127 for ch in atom):
            warnings.append((start[0], start[1], f"符号中含非 ASCII 字符: {atom!r}"))
    if in_string:
        errors.append((str_start[0], str_start[1], "文件结束时字符串仍未闭合"))
    if depth > 0:
        errors.append((-1, -1, f"文件结束时仍有 {depth} 个未闭合的左括号"))
    return errors, warnings


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: lisp_reader_probe.py <file.lsp>")
        return 2
    path = Path(sys.argv[1])
    raw = path.read_bytes()
    # 自动探测：严格 GB2312 解码
    try:
        text = raw.decode("gb2312", errors="strict")
        enc = "gb2312(strict)"
    except UnicodeDecodeError as exc:
        try:
            text = raw.decode("gbk", errors="strict")
            enc = f"gbk(strict, gb2312 failed: {exc})"
        except UnicodeDecodeError as exc2:
            text = raw.decode("latin-1")
            enc = f"latin-1 fallback ({exc2})"
    print(f"FILE: {path.resolve()}")
    print(f"BYTES: {len(raw)}  DECODED_AS: {enc}")
    # 字节级检查：0x00 / 0x1A / 孤立 0x0D 之外的控制字符
    bad_bytes = {}
    for idx, b in enumerate(raw):
        if b < 32 and b not in (0x09, 0x0A, 0x0D):
            ln = raw.count(b"\n", 0, idx) + 1
            bad_bytes.setdefault(b, []).append(ln)
    for b, lines in bad_bytes.items():
        print(f"RAW_CONTROL_BYTE: 0x{b:02X} at lines {lines[:10]}{'...' if len(lines) > 10 else ''}")
    errors, warnings = probe(text)
    print(f"READ_ERRORS: {len(errors)}")
    for ln, col, msg in errors:
        loc = f"line {ln}" if ln > 0 else "EOF"
        if col > 0:
            loc += f" col {col}"
        print(f"  ERROR {loc}: {msg}")
    print(f"WARNINGS: {len(warnings)}")
    for ln, col, msg in warnings[:20]:
        print(f"  WARN line {ln} col {col}: {msg}")
    if len(warnings) > 20:
        print(f"  ... ({len(warnings) - 20} more)")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
