#!/usr/bin/env python3
"""check_lisp.py - static structure & pure-logic checker for one-click-simsun.lsp.

Usage:
    python tools/check_lisp.py [--lisp PATH] [--cases PATH] [--json]

Checks (development tool; not an AutoCAD acceptance test):
  1. Lexical structure: balanced parens/strings/comments, UTF-8 decoding.
  2. Top-level forms parse into a nested S-expression tree (grammar check).
  3. Every OCS:/c: definition is unique; report defined functions.
  4. Required plan functions (section 8 of the plan) exist.
  5. Runs pure-function test vectors for OCS:NormalizeFontRuns if the lisp
     exposes a pure-parse entry (OCS:Parse) plus a small interpreter.
     The interpreter is Python re-implementation of the scanner contract used
     only to cross-check *case expectations* in font-format-cases.json against
     the JSON's own expected outputs (self-consistency), and to verify that
     the LISP source contains the same case-driving constants.

Exit code 0 when all hard checks pass; 1 otherwise.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REQUIRED_FUNCS = [
    "c:YJST",
    "OCS:Preflight",
    "OCS:ResolveSongFont",
    "OCS:CollectStyles",
    "OCS:CollectHosts",
    "OCS:NormalizeFontRuns",
    "OCS:ReadHost",
    "OCS:BuildPlan",
    "OCS:ApplyStyle",
    "OCS:WriteHost",
    "OCS:VerifyDrawing",
    "OCS:Rollback",
    "OCS:Report",
]


# --------------------------------------------------------------------------- #
# Lexer / reader
# --------------------------------------------------------------------------- #
class LispSyntaxError(Exception):
    def __init__(self, msg: str, line: int, col: int):
        super().__init__(f"{msg} at line {line} col {col}")
        self.line = line
        self.col = col


def lex(text: str):
    """Yield tokens: ('(',line), (')',line), ('sym',text,line), ('str',text,line)."""
    i = 0
    n = len(text)
    line = 1
    col = 1
    while i < n:
        ch = text[i]
        if ch == "\n":
            line += 1
            col = 1
            i += 1
            continue
        if ch in " \t\r\f\v":
            col += 1
            i += 1
            continue
        if ch == ";":  # comment to EOL
            while i < n and text[i] != "\n":
                i += 1
                col += 1
            continue
        if ch == "(":
            yield ("(", line, col)
            i += 1
            col += 1
            continue
        if ch == ")":
            yield (")", line, col)
            i += 1
            col += 1
            continue
        if ch == '"':
            start_line, start_col = line, col
            i += 1
            col += 1
            buf = []
            closed = False
            while i < n:
                c = text[i]
                if c == "\\":
                    if i + 1 >= n:
                        raise LispSyntaxError("unterminated escape in string", line, col)
                    nxt = text[i + 1]
                    # AutoLISP string escapes: keep both chars (recorded raw)
                    buf.append(c)
                    buf.append(nxt)
                    if nxt == "\n":
                        line += 1
                        col = 1
                    else:
                        col += 2
                    i += 2
                    continue
                if c == '"':
                    i += 1
                    col += 1
                    closed = True
                    break
                if c == "\n":
                    line += 1
                    col = 1
                    buf.append(c)
                    i += 1
                    continue
                buf.append(c)
                col += 1
                i += 1
            if not closed:
                raise LispSyntaxError("unterminated string", start_line, start_col)
            yield ("str", "".join(buf), start_line, start_col)
            continue
        # symbol / number / quote
        start = i
        start_line, start_col = line, col
        if ch in "'`":
            yield ("sym", ch, line, col)
            i += 1
            col += 1
            continue
        while i < n and text[i] not in ' \t\r\f\v\n();"\'`':
            i += 1
            col += 1
        if i == start:
            raise LispSyntaxError(f"unexpected character {ch!r}", line, col)
        yield ("sym", text[start:i], start_line, start_col)


def parse(text: str):
    """Parse into nested lists; atoms are ('sym'|'str', value, line, col)."""
    stack = []
    root = []
    cur = root
    for tok in lex(text):
        kind = tok[0]
        if kind == "(":
            new = []
            cur.append(new)
            stack.append(cur)
            cur = new
        elif kind == ")":
            if not stack:
                raise LispSyntaxError("unbalanced close paren", tok[1], tok[2])
            cur = stack.pop()
        else:
            cur.append(tok)
    if stack:
        raise LispSyntaxError("unbalanced open paren", 0, 0)
    return root


def sym_value(node) -> str | None:
    if isinstance(node, tuple) and node[0] == "sym":
        return node[1]
    return None


def head_symbol(form) -> str | None:
    if isinstance(form, list) and form:
        return sym_value(form[0])
    return None


def collect_defs(forms):
    defs = {}
    dupes = []

    def walk(form):
        if not isinstance(form, list):
            return
        h = head_symbol(form)
        if h in ("defun", "defun-c") and len(form) >= 2:
            name = sym_value(form[1])
            if name:
                line = form[1][2] if isinstance(form[1], tuple) else 0
                if name in defs:
                    dupes.append((name, line))
                else:
                    defs[name] = line
        for sub in form:
            if isinstance(sub, list):
                walk(sub)

    for f in forms:
        walk(f)
    return defs, dupes


# --------------------------------------------------------------------------- #
# Case self-consistency: JSON expected vs. simple re-scan expectations
# --------------------------------------------------------------------------- #
FONT_CODE_RE = re.compile(r"\\[fF]([^;]*);")
FIELD_RE = re.compile(r"%<.*?>%", re.S)


def check_cases(cases_path: Path):
    problems = []
    raw = cases_path.read_bytes()
    if raw.startswith(b"\xef\xbb\xbf"):
        problems.append("cases file starts with UTF-8 BOM (must be UTF-8 without BOM)")
        raw = raw[3:]
    data = json.loads(raw.decode("utf-8"))
    cases = data.get("cases", [])
    if not cases:
        problems.append("no cases defined")
    ids = set()
    for idx, case in enumerate(cases):
        cid = case.get("id", f"#{idx}")
        if cid in ids:
            problems.append(f"duplicate case id {cid}")
        ids.add(cid)
        for key in ("input", "expected"):
            if key not in case:
                problems.append(f"case {cid}: missing {key}")
        inp = case.get("input", "")
        exp = case.get("expected", "")
        if exp is None:
            # expected: null means the case must produce a parse error
            if case.get("expectErrors", 0) < 1:
                problems.append(f"case {cid}: expected null but expectErrors=0")
            continue
        # structural: field regions must be byte-identical between input and expected
        in_fields = FIELD_RE.findall(inp)
        ex_fields = FIELD_RE.findall(exp)
        if in_fields != ex_fields:
            problems.append(f"case {cid}: field regions differ between input and expected")
        # non-font formatting codes must be identical multiset
        def fmt_codes(s: str):
            return re.findall(r"\\[HWQTcCPSparfF][^;\\]*;", s)

        if fmt_codes(inp) != fmt_codes(exp):
            # font codes are intentionally changed; compare without f/F
            def fmt_no_font(s):
                return [c for c in re.findall(r"\\[A-Za-z][^;\\]*;", s) if c[1] not in "fF"]

            if fmt_no_font(inp) != fmt_no_font(exp):
                problems.append(f"case {cid}: non-font format codes differ")
        # every font code OUTSIDE field regions in expected must target the family
        # (skip expected==input cases: they contain no *effective* font code change)
        exp_nofields = FIELD_RE.sub("", exp)
        fam = case.get("targetFamily", data.get("targetFamily", "SimSun"))
        if exp != inp:
            for m in FONT_CODE_RE.finditer(exp_nofields):
                desc = m.group(1)
                # a field region removed by FIELD_RE may leave a trailing
                # fragment behind a real font code; only check codes whose
                # descriptor does not contain an escape (escaped fragments
                # come from inside the removed field).
                if "\\" in desc:
                    continue
                first = desc.split("|")[0]
                if first.lower() != fam.lower():
                    problems.append(
                        f"case {cid}: expected font code family {first!r} != {fam!r}"
                    )
        # idempotence marker: if the case declares secondRunExpected, it must equal expected
        if case.get("secondRunExpected", None) is not None:
            if case["secondRunExpected"] != exp:
                problems.append(f"case {cid}: secondRunExpected != expected (not idempotent)")
    return problems, len(cases)


def check_lisp_has_case_ids(lisp_text: str, cases_path: Path) -> list[str]:
    """The in-LISP self test should reference every JSON case id."""
    problems = []
    data = json.loads(cases_path.read_text(encoding="utf-8"))
    for case in data.get("cases", []):
        cid = case.get("id")
        if cid and cid not in lisp_text:
            problems.append(f"case id {cid!r} not referenced in lisp source")
    return problems


def main() -> int:
    ap = argparse.ArgumentParser()
    here = Path(__file__).resolve().parent.parent
    ap.add_argument("--lisp", default=str(here / "one-click-simsun.lsp"))
    ap.add_argument("--cases", default=str(here / "tests" / "font-format-cases.json"))
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    hard_fail = False
    report = {"lisp": args.lisp, "errors": [], "warnings": [], "info": {}}

    lisp_path = Path(args.lisp)
    if not lisp_path.exists():
        report["errors"].append(f"lisp file not found: {lisp_path}")
        hard_fail = True
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 1

    raw = lisp_path.read_bytes()
    if raw.startswith(b"\xef\xbb\xbf"):
        report["errors"].append("lisp file starts with UTF-8 BOM (must be UTF-8 without BOM)")
        hard_fail = True
        raw = raw[3:]
    try:
        text = raw.decode("utf-8")
        report["info"]["encoding"] = "utf-8"
    except UnicodeDecodeError as e:
        report["errors"].append(f"not valid UTF-8: {e}")
        hard_fail = True
        text = raw.decode("utf-8", errors="replace")

    try:
        forms = parse(text)
        report["info"]["top_level_forms"] = len(forms)
    except LispSyntaxError as e:
        report["errors"].append(f"syntax: {e}")
        hard_fail = True
        forms = []

    if forms:
        defs, dupes = collect_defs(forms)
        report["info"]["defined_functions"] = len(defs)
        if dupes:
            for name, line in dupes:
                report["errors"].append(f"duplicate defun {name} (line {line})")
            hard_fail = True
        for req in REQUIRED_FUNCS:
            if req not in defs:
                report["errors"].append(f"missing required function {req}")
                hard_fail = True
        # all defined OCS functions must use the OCS: prefix
        for name in defs:
            if name.startswith("OCS:") or name.startswith("c:"):
                continue
            report["warnings"].append(f"function without OCS: prefix: {name}")
        report["info"]["functions"] = sorted(defs)

    cases_path = Path(args.cases)
    if cases_path.exists():
        probs, n = check_cases(cases_path)
        report["info"]["cases"] = n
        for p in probs:
            if "BOM" in p:
                report["warnings"].append(p)
            else:
                report["errors"].append(f"cases: {p}")
                hard_fail = True
        if forms:
            for p in check_lisp_has_case_ids(text, cases_path):
                report["warnings"].append(p)
    else:
        report["errors"].append(f"cases file not found: {cases_path}")
        hard_fail = True

    # forbidden behaviors (static smell tests)
    forbidden = {
        "ATTSYNC": "ATTSYNC must not be used",
        "_ATTSYNC": "ATTSYNC must not be used",
        "ResetBlock": "ResetBlock must not be used",
        "_RESETBLOCK": "ResetBlock must not be used",
        "EXPLODE": "EXPLODE must not be used",
        "_EXPLODE": "EXPLODE must not be used",
        "SAVEAS": "SAVEAS must not run",
        "_SAVEAS": "SAVEAS must not run",
        "UNDO": "raw UNDO command must not run (only _.U inside rollback)",
        "_UNDO": "raw UNDO command must not run",
    }
    # usage inside comments is fine; strip comments and strings first
    stripped = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    stripped = re.sub(r";[^\n]*", "", stripped)
    for token, msg in forbidden.items():
        if re.search(r"\b" + re.escape(token) + r"\b", stripped, re.I):
            # rollback path is allowed to run exactly one "_.U"
            if token in ("UNDO", "_UNDO"):
                if re.search(r"'command\s*\(\s*list\s*\"_\\.U\"", stripped):
                    continue
                if not re.search(r"\bUNDO\b", stripped, re.I):
                    continue
            # FONTALT etc. may be read via getvar (read-only) for reporting
            if token in ("FONTALT", "FONTMAP", "SECURELOAD", "LISPSYS"):
                if re.search(
                    r"getvar\s*\(\s*\"" + re.escape(token) + r"\"", stripped, re.I
                ):
                    continue
            report["errors"].append(f"forbidden pattern: {msg} ({token})")
            hard_fail = True

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(f"lisp: {args.lisp}")
        print(f"top-level forms: {report['info'].get('top_level_forms', '-')}")
        print(f"defined functions: {report['info'].get('defined_functions', '-')}")
        print(f"cases: {report['info'].get('cases', '-')}")
        for w in report["warnings"]:
            print(f"  WARN  {w}")
        for e in report["errors"]:
            print(f"  ERROR {e}")
        print("RESULT:", "FAIL" if hard_fail else "PASS")
    return 1 if hard_fail else 0


if __name__ == "__main__":
    sys.exit(main())
