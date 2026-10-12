# -*- coding: utf-8 -*-
"""build_diag.py - 生成目标 CAD 引擎诊断工具包（GB2312）。

背景：output/gb2312/one-click-simsun.lsp 对标准 AutoLISP 读入规则完全干净
（tools/lisp_reader_probe.py 验证：括号配对、字符串闭合、无控制字符、无 BOM、
GB2312 字节全部在 A1-FE 区间），但目标 CAD 引擎报「语法错误」。该引擎不支持
defmacro（此前 no function definition: FN 可证），疑似中望 ZWCAD Classic 的
"LISP Release 1.0" 精简 LISP 引擎。

本工具生成三类诊断文件（全部严格 GB2312、无 BOM、LF 行尾）：

1. probe/p01..p13.lsp  —— 引擎特性探针。每个文件只用基础语法 + 一项待测特性，
   加载成功时打印唯一 OK 标记。配合 ocs-probe.lsp 的 c:OCS_PROBE 一键顺序加载，
   第一个失败的探针即指出引擎不支持（或处理不同）的语法特性。
2. parts/part1..part12.lsp —— 主源码按顶层 form 边界切分的 12 个独立部件，
   每个部件可单独 LOAD（defun 只在加载期定义、不互相调用）。
   配合 ocs-bisect.lsp 的 c:OCS_BISECT 逐部加载，第一个失败的部件定位错误区间。
3. crlf/one-click-simsun.lsp —— 完整交付文件的 CRLF 行尾变体（快速实验用）。

驱动与探针只使用最基础的 LISP（defun/setq/while/strcat/itoa/princ/load），
确保驱动本身能在受限引擎中加载。

用法（仓库根）：
    python -X utf8 tools/build_diag.py
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "one-click-simsun.lsp"
OUT = ROOT / "output" / "gb2312"

PROBE_DIR = OUT / "probe"
PARTS_DIR = OUT / "parts"
CRLF_DIR = OUT / "crlf"

N_PARTS = 12

# ---------------------------------------------------------------- 探针内容
# 每个探针：标题注释（中文）+ 基础语句 + 单项特性 + OK 标记。
# 注意：探针正文在 Python 源码中用普通字符串书写，其中的反斜杠按 Python
# 转义规则解释，写出后即为目标 LISP 源码（与主源码同一套转义约定）。
PROBES: list[tuple[str, str]] = [
    (
        "p01",
        "基础语法：defun / princ / 中文注释",
        ';;; probe p01 - basic defun + princ + Chinese comment 中文注释\n'
        '(defun OCS-P1 ( / )\n'
        '  (princ "\\nPROBE-01-OK basic-defun-princ")\n'
        ')\n'
        '(OCS-P1)\n',
    ),
    (
        "p02",
        "注释内含 ASCII 括号与引号（模拟主源码 133-135 行注释）",
        ';;; probe p02 - comment containing ASCII parens and quotes\n'
        ';; 注意：不使用 defmacro / 反引号宏。加载时会把 (fn &rest args) 参数表\n'
        ';; 当普通调用求值，报 "no function definition: FN"。\n'
        '(defun OCS-P2 ( / )\n'
        '  (princ "\\nPROBE-02-OK comment-parens-quotes")\n'
        ')\n'
        '(OCS-P2)\n',
    ),
    (
        "p03",
        "字符串转义：反斜杠 \\\\、转义引号 \\\"、\\n、\\t",
        ';;; probe p03 - string escapes: backslash, escaped quote, newline, tab\n'
        '(defun OCS-P3 ( / s )\n'
        '  (setq s (strcat "a\\\\b" "\\"q\\"" "x\\ty" "x\\ny"))\n'
        '  (princ "\\nPROBE-03-OK string-escapes")\n'
        '  (princ s)\n'
        ')\n'
        '(OCS-P3)\n',
    ),
    (
        "p04",
        "关键字符号 :error（plist 模式的基石）",
        ';;; probe p04 - keyword symbols\n'
        '(defun OCS-P4 ( / x )\n'
        '  (setq x (list :error "msg" :ok T))\n'
        '  (if (eq (car x) :error)\n'
        '    (princ "\\nPROBE-04-OK keyword-symbols")\n'
        '    (princ "\\nPROBE-04-FAIL")\n'
        '  )\n'
        ')\n'
        '(OCS-P4)\n',
    ),
    (
        "p05",
        "quote 简写 'symbol 与通过变量调用函数",
        ';;; probe p05 - quote shorthand and calling function held in variable\n'
        '(defun OCS-P5fn ( / ) (princ "\\nPROBE-05-OK quote-shorthand"))\n'
        '(defun OCS-P5 ( / f )\n'
        '  (setq f \'OCS-P5fn)\n'
        '  (if f (f) (princ "\\nPROBE-05-FAIL"))\n'
        ')\n'
        '(OCS-P5)\n',
    ),
    (
        "p06",
        "科学计数法 1e-9（equal 容差用）",
        ';;; probe p06 - scientific notation real literal\n'
        '(defun OCS-P6 ( / e )\n'
        '  (setq e 1e-9)\n'
        '  (if (and (< e 1.0) (> e 0.0))\n'
        '    (princ "\\nPROBE-06-OK scientific-notation")\n'
        '    (princ "\\nPROBE-06-FAIL")\n'
        '  )\n'
        ')\n'
        '(OCS-P6)\n',
    ),
    (
        "p07",
        "16 层深层嵌套（主源码最大嵌套深度）",
        ';;; probe p07 - deep nesting depth 16 (same as main file max)\n'
        '(defun OCS-P7 ( / )\n'
        '  (progn (progn (progn (progn (progn (progn (progn\n'
        '    (progn (progn (progn (progn (progn (progn (progn\n'
        '      (princ "\\nPROBE-07-OK deep-nesting-16")\n'
        '    ))))))))))))))\n'
        ')\n'
        '(OCS-P7)\n',
    ),
    (
        "p08",
        "中文字符串 + strcat 中文",
        ';;; probe p08 - Chinese text inside strings\n'
        '(defun OCS-P8 ( / s )\n'
        '  (setq s (strcat "中文测试" "宋体"))\n'
        '  (princ "\\nPROBE-08-OK chinese-strings")\n'
        '  (princ (strcat " strlen=" (itoa (strlen s))))\n'
        ')\n'
        '(OCS-P8)\n',
    ),
    (
        "p09",
        "vl-load-com（主源码第一个顶层求值形式）",
        ';;; probe p09 - vl-load-com (first top-level form of main file)\n'
        '(vl-load-com)\n'
        '(princ "\\nPROBE-09-OK vl-load-com")\n',
    ),
    (
        "p10",
        "vl-catch-all-apply + quote 传函数符号",
        ';;; probe p10 - vl-catch-all-apply with quoted symbol\n'
        '(defun OCS-P10 ( / r )\n'
        '  (setq r (vl-catch-all-apply \'princ (list "\\nPROBE-10-OK vl-catch-all-apply")))\n'
        '  (if (vl-catch-all-error-p r)\n'
        '    (princ "\\nPROBE-10-FAIL")\n'
        '  )\n'
        ')\n'
        '(OCS-P10)\n',
    ),
    (
        "p11",
        "* 包裹的全局符号（*OCS:Version* 风格）",
        ';;; probe p11 - starred global symbols\n'
        '(setq *OCS:ProbeVar* "v0.1")\n'
        '(if (and (boundp \'*OCS:ProbeVar*) *OCS:ProbeVar*)\n'
        '  (princ "\\nPROBE-11-OK starred-symbols")\n'
        '  (princ "\\nPROBE-11-FAIL")\n'
        ')\n',
    ),
    (
        "p12",
        "空局部变量表 ( / )（endUndoGroup / c:YJST 使用）",
        ';;; probe p12 - empty local argument list ( / )\n'
        '(defun OCS-P12 ( / )\n'
        '  (princ "\\nPROBE-12-OK empty-locals")\n'
        ')\n'
        '(OCS-P12)\n',
    ),
    (
        "p13",
        "大整数 4294967296（toHex 用）与负数 -16（lsh 用）",
        ';;; probe p13 - large integer and negative literal\n'
        '(defun OCS-P13 ( / a b )\n'
        '  (setq a 4294967296 b -16)\n'
        '  (if (and (> a 0) (< b 0))\n'
        '    (princ "\\nPROBE-13-OK bigint-negative")\n'
        '    (princ "\\nPROBE-13-FAIL")\n'
        '  )\n'
        ')\n'
        '(OCS-P13)\n',
    ),
]

PROBE_DRIVER = """;;; ocs-probe.lsp - 引擎特性探针驱动（vanilla LISP）
;;; 用法：APPLOAD 加载本文件后，命令行执行 OCS_PROBE
;;; 输出：逐个加载 probe/p01..p13.lsp，任一探针加载失败即指出
;;;      目标引擎不支持（或处理不同）的语法特性。
(defun c:OCS_PROBE ( / i f r nm)
  (setq i 1)
  (while (<= i 13)
    (setq nm (itoa i))
    (if (< i 10) (setq nm (strcat "0" nm)))
    (setq f (strcat "%PROBEDIR%/p" nm ".lsp"))
    (princ (strcat "\\n== PROBE " (itoa i) "/13 == "))
    (setq r (load f "PROBE-LOAD-FAILED"))
    (if (= r "PROBE-LOAD-FAILED")
      (princ "<<< LOAD FAILED")
      (princ "ok")
    )
    (setq i (1+ i))
  )
  (princ "\\n== PROBE DONE ==")
  (princ)
)
(princ "\\nOCS 探针驱动已加载：执行 OCS_PROBE 逐项测试引擎语法特性。")
(princ)
"""

BISECT_DRIVER = """;;; ocs-bisect.lsp - 主文件二分定位驱动（vanilla LISP）
;;; 用法：APPLOAD 加载本文件后，命令行执行 OCS_BISECT
;;; 输出：逐部加载 parts/part1..part12.lsp，第一个 LOAD FAILED 的部件
;;;      即包含目标引擎无法读入的语法构造；把该部件行号范围反馈给开发。
(defun c:OCS_BISECT ( / i f r )
  (setq i 1)
  (while (<= i %NPARTS%)
    (setq f (strcat "%PARTSDIR%/part" (itoa i) ".lsp"))
    (princ (strcat "\\n== PART " (itoa i) "/%NPARTS% == "))
    (setq r (load f "PART-LOAD-FAILED"))
    (if (= r "PART-LOAD-FAILED")
      (princ "<<< LOAD FAILED")
      (princ "ok")
    )
    (setq i (1+ i))
  )
  (princ "\\n== BISECT DONE ==")
  (princ)
)
(princ "\\nOCS 二分驱动已加载：执行 OCS_BISECT 逐部定位主文件错误区间。")
(princ)
"""


ALLINONE_DRIVER = """;;; ocs-diag-all.lsp - 一键诊断 v2：加载本文件即自动执行全部测试（vanilla LISP）
;;; A. 引擎特性探针 probe/p01..p13（13 项语法特性；v1 的 p1..p9 文件名 bug 已修）
;;; B. part12 测试用例逐条探针 cases/c01..cNN（15 条 MTEXT 用例字符串）
;;; C. part12 逐顶层 form 探针 sub12/f01..fNN（定位到具体 defun）
;;; D. 行尾实验：CRLF 版与 LF 版各 LOAD 一次（可能中断驱动，放最后）
;;; 程序自动临时关闭 SECURELOAD，全程无安全弹窗；若中途中断，
;;; 请手动执行 (setvar "SECURELOAD" 1) 恢复。
(princ "\\n==== OCS 一键诊断 v2 开始 ====")
(princ "\\n(SECURELOAD 已由程序临时关闭；若中途中断请执行 (setvar \\"SECURELOAD\\" 1) 恢复)")
(vl-catch-all-apply 'setvar (list "SECURELOAD" 0))

;; ---- A. 引擎特性探针 ----
(princ "\\n---- A. 引擎特性探针（13 项）----")
(setq OCS-DIAG-I 1)
(while (<= OCS-DIAG-I 13)
  (setq OCS-DIAG-NM (itoa OCS-DIAG-I))
  (if (< OCS-DIAG-I 10) (setq OCS-DIAG-NM (strcat "0" OCS-DIAG-NM)))
  (setq OCS-DIAG-F (strcat "%PROBEDIR%/p" OCS-DIAG-NM ".lsp"))
  (princ (strcat "\\n== PROBE " OCS-DIAG-NM "/13 == "))
  (setq OCS-DIAG-R (load OCS-DIAG-F "PROBE-LOAD-FAILED"))
  (if (= OCS-DIAG-R "PROBE-LOAD-FAILED")
    (princ "<<< LOAD FAILED（软失败）")
    (princ "ok")
  )
  (setq OCS-DIAG-I (1+ OCS-DIAG-I))
)

;; ---- B. part12 测试用例逐条探针 ----
(princ "\\n---- B. part12 用例逐条探针（%NCASES% 条）----")
(setq OCS-DIAG-I 1)
(while (<= OCS-DIAG-I %NCASES%)
  (setq OCS-DIAG-NM (itoa OCS-DIAG-I))
  (if (< OCS-DIAG-I 10) (setq OCS-DIAG-NM (strcat "0" OCS-DIAG-NM)))
  (setq OCS-DIAG-F (strcat "%CASESDIR%/c" OCS-DIAG-NM ".lsp"))
  (princ (strcat "\\n== CASE " OCS-DIAG-NM "/%NCASES% == "))
  (setq OCS-DIAG-R (load OCS-DIAG-F "CASE-LOAD-FAILED"))
  (if (= OCS-DIAG-R "CASE-LOAD-FAILED")
    (princ "<<< LOAD FAILED（软失败）")
    (princ "ok")
  )
  (setq OCS-DIAG-I (1+ OCS-DIAG-I))
)

;; ---- C. part12 逐顶层 form 探针 ----
(princ "\\n---- C. part12 逐 form 探针（%NFORMS% 个）----")
(setq OCS-DIAG-I 1)
(while (<= OCS-DIAG-I %NFORMS%)
  (setq OCS-DIAG-NM (itoa OCS-DIAG-I))
  (if (< OCS-DIAG-I 10) (setq OCS-DIAG-NM (strcat "0" OCS-DIAG-NM)))
  (setq OCS-DIAG-F (strcat "%SUB12DIR%/f" OCS-DIAG-NM ".lsp"))
  (princ (strcat "\\n== FORM " OCS-DIAG-NM "/%NFORMS% == "))
  (setq OCS-DIAG-R (load OCS-DIAG-F "FORM-LOAD-FAILED"))
  (if (= OCS-DIAG-R "FORM-LOAD-FAILED")
    (princ "<<< LOAD FAILED（软失败）")
    (princ "ok")
  )
  (setq OCS-DIAG-I (1+ OCS-DIAG-I))
)

;; ---- D. 行尾实验（整文件加载，若触发语法错误会中断驱动，属预期） ----
(princ "\\n---- D. 行尾实验（若中断属预期，诊断数据已全部打出）----")
(setq OCS-DIAG-R (load "%MAINLF-CRLF%" "CRLF-LOAD-FAILED"))
(if (= OCS-DIAG-R "CRLF-LOAD-FAILED")
  (princ "\\nD 结果：主文件 CRLF 版 = LOAD FAILED（行尾不是根因）")
  (princ "\\nD 结果：主文件 CRLF 版 = LOAD OK（行尾就是根因，交付改用 CRLF）")
)
(load "%MAINLF%" "MAIN-LOAD-FAILED")

(princ "\\n==== OCS 一键诊断 v2 结束 ====")
(vl-catch-all-apply 'setvar (list "SECURELOAD" 1))
(princ "\\n(SECURELOAD 已恢复为 1)")
(princ)
"""


def split_top_level_forms(text: str) -> list[tuple[int, int]]:
    """返回 [(start_line, end_line)]，按顶层 form 边界（1-based 行号，含端点）。"""
    forms = []
    depth = 0
    start = 0
    in_str = False
    i = 0
    n = len(text)
    line = 1
    form_start_line = 1
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            i += 1
            continue
        if c == ";":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "(":
            if depth == 0:
                form_start_line = line
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                forms.append((form_start_line, line))
        i += 1
    return forms


def write_gb2312(path: Path, text: str) -> None:
    payload = text.encode("gb2312", errors="strict")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)
    # 读回校验
    back = path.read_bytes().decode("gb2312", errors="strict")
    assert back == text, f"round-trip mismatch: {path}"


def main() -> int:
    try:
        text = SOURCE.read_bytes().decode("utf-8-sig", errors="strict")
    except (OSError, UnicodeDecodeError) as exc:
        print(f"SOURCE_ERROR: {exc}")
        return 1

    lines = text.split("\n")
    total_lines = len(lines)

    # ---- 1) 探针 ----
    for idx, (name, feature, body) in enumerate(PROBES, 1):
        header = (
            f";;; probe {name} ({idx:02d}/13) - 引擎特性测试：{feature}\n"
            f";;; 由 tools/build_diag.py 生成；加载成功应看到 PROBE-{idx:02d}-OK 标记\n"
        )
        write_gb2312(PROBE_DIR / f"{name}.lsp", header + body)
        print(f"PROBE: {name}.lsp  ({feature})")

    # ---- 2b) part12 细分：按顶层 form 切成 sub12/fNN.lsp ----
    SUB12_DIR = OUT / "sub12"
    forms = split_top_level_forms(text)
    print(f"FORMS: {len(forms)} top-level forms in source")
    per = (len(forms) + N_PARTS - 1) // N_PARTS
    part12_forms = forms[(N_PARTS - 1) * per :]
    for idx, (lo, hi) in enumerate(part12_forms, 1):
        body = "\n".join(lines[lo - 1 : hi])
        header = (
            f";;; sub12/f{idx:02d} - 主源码第 {lo}-{hi} 行（part12 第 {idx} 个顶层 form）\n"
            f";;; 由 tools/build_diag.py 生成；加载成功打印 OK-F{idx:02d}\n"
        )
        footer = f'\n(princ "\\nOK-F{idx:02d} lines {lo}-{hi}")\n(princ)\n'
        write_gb2312(SUB12_DIR / f"f{idx:02d}.lsp", header + body + footer)
        print(f"SUB12: f{idx:02d}.lsp  lines {lo}-{hi}")
    N_FORMS = len(part12_forms)

    # ---- 2c) selfTestCases 的 15 条用例逐条拆成 cases/cNN.lsp ----
    CASES_DIR = OUT / "cases"
    # 定位 OCS:selfTestCases 的 defun 区间
    stc = next(f for f in forms if "(defun OCS:selfTestCases" in lines[f[0] - 1])
    stc_lines = lines[stc[0] - 1 : stc[1]]
    # 在 defun 内找每条以 "(list" 开头的顶层用例（括号配平即一条）
    cases: list[tuple[int, int]] = []  # 相对 stc_lines 的起止行
    depth = 0
    case_start = None
    for rel, ln in enumerate(stc_lines):
        s = ln.strip()
        if depth == 0:
            # "(list " 带实参的是单条用例；外层裸 "(list" 跳过
            if s.startswith("(list "):
                case_start = rel
                depth = ln.count("(") - ln.count(")")
                if depth == 0 and case_start is not None:
                    cases.append((case_start, rel))
                    case_start = None
        else:
            depth += ln.count("(") - ln.count(")")
            if depth <= 0:
                cases.append((case_start, rel))
                case_start = None
                depth = 0
    for idx, (lo, hi) in enumerate(cases, 1):
        body = "\n".join(stc_lines[lo : hi + 1])
        first_src_line = stc[0] + lo
        last_src_line = stc[0] + hi
        header = (
            f";;; cases/c{idx:02d} - selfTestCases 第 {idx} 条用例"
            f"（主源码第 {first_src_line}-{last_src_line} 行）\n"
            f";;; 由 tools/build_diag.py 生成；加载成功打印 OK-C{idx:02d}\n"
        )
        footer = f'\n(princ "\\nOK-C{idx:02d}")\n(princ)\n'
        write_gb2312(CASES_DIR / f"c{idx:02d}.lsp", header + body + footer)
        print(f"CASE: c{idx:02d}.lsp  src lines {first_src_line}-{last_src_line}")
    N_CASES = len(cases)

    # ---- 2d) 二分部件（part1..part12）----
    for p in range(N_PARTS):
        chunk = forms[p * per : (p + 1) * per]
        if not chunk:
            continue
        lo, hi = chunk[0][0], chunk[-1][1]
        seg_start = lo - 1
        seg_end = hi  # 含端点行
        body = "\n".join(lines[seg_start:seg_end])
        part_no = p + 1
        header = (
            f";;; part{part_no} - 主源码第 {lo}-{hi} 行"
            f"（顶层 form {p * per + 1}-{p * per + len(chunk)}，共 {len(forms)} 个）\n"
            f";;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART{part_no}\n"
        )
        footer = f'\n(princ "\\nOK-PART{part_no} lines {lo}-{hi}")\n(princ)\n'
        write_gb2312(PARTS_DIR / f"part{part_no}.lsp", header + body + footer)
        print(f"PART: part{part_no}.lsp  lines {lo}-{hi}  ({len(chunk)} forms)")

    # ---- 3) 驱动 ----
    write_gb2312(
        OUT / "ocs-probe.lsp",
        PROBE_DRIVER.replace("%PROBEDIR%", str(PROBE_DIR).replace("\\", "/")),
    )
    write_gb2312(
        OUT / "ocs-bisect.lsp",
        BISECT_DRIVER.replace("%PARTSDIR%", str(PARTS_DIR).replace("\\", "/")).replace(
            "%NPARTS%", str(N_PARTS)
        ),
    )
    # 一键诊断驱动 v2：加载即自动执行探针 + 用例 + form 细分 + 行尾实验
    write_gb2312(
        OUT / "ocs-diag-all.lsp",
        ALLINONE_DRIVER.replace("%PROBEDIR%", str(PROBE_DIR).replace("\\", "/"))
        .replace("%CASESDIR%", str(CASES_DIR).replace("\\", "/"))
        .replace("%SUB12DIR%", str(SUB12_DIR).replace("\\", "/"))
        .replace("%NCASES%", str(N_CASES))
        .replace("%NFORMS%", str(N_FORMS))
        .replace("%MAINLF%", str(OUT / "one-click-simsun.lsp").replace("\\", "/"))
        .replace(
            "%MAINLF-CRLF%", str(CRLF_DIR / "one-click-simsun.lsp").replace("\\", "/")
        ),
    )
    print(
        "DRIVER: ocs-probe.lsp (c:OCS_PROBE), ocs-bisect.lsp (c:OCS_BISECT), "
        "ocs-diag-all.lsp v2 (load-and-run)"
    )

    # ---- 4) CRLF 变体 ----
    crlf_payload = text.encode("gb2312", errors="strict").replace(b"\n", b"\r\n")
    CRLF_DIR.mkdir(parents=True, exist_ok=True)
    (CRLF_DIR / "one-click-simsun.lsp").write_bytes(crlf_payload)
    back = (CRLF_DIR / "one-click-simsun.lsp").read_bytes().decode("gb2312", errors="strict")
    assert back.replace("\r\n", "\n") == text, "CRLF round-trip mismatch"
    print(f"CRLF: crlf/one-click-simsun.lsp  ({len(crlf_payload)} bytes)")

    print(f"DIAG BUILD OK (source lines: {total_lines})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
