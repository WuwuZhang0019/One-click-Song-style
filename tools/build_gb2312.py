"""build_gb2312.py - 把 UTF-8 开发源码构建为 GB2312 交付插件。

日期：2026-10-14。

依据 docs/GB2312编码修复与加载复测说明.md 第 4 节：

- 源码严格按 UTF-8 解码（允许去 BOM），目标严格按 gb2312 编码；
- 不可编码字符明确报错（文件、行、列、字符），禁止 ignore/replace；
- 交付文件写入前做严格往返校验，写入后做字节与文本读回校验；
- 输出构建时间、源路径、交付路径、字节数与 SHA-256。

用法（仓库根目录）：

    python -X utf8 tools/build_gb2312.py
"""

from __future__ import annotations

from datetime import datetime
from hashlib import sha256
from pathlib import Path
import re

# 需要纳入同一构建与校验流程的实际加载文件清单（入口 + 辅助文件）。
# 只有被 CAD 实际 LOAD/APPLOAD 的文件才放入 output/gb2312。
LOAD_FILES = ["one-click-simsun.lsp", "tests/native/ocs-native-checks.lsp",
              "tests/native/YJST-D5-CHECK-20261014.lsp", "tests/native/YJST-D5-DXF-20261014.lsp"]


def command_parts(text: str) -> tuple[str, str, str]:
    """日期：2026-10-14。从唯一主源码生成手动 YJSTFIX 入口，保留恢复状态预检。"""
    version = re.search(r'\(setq\s+\*OCS:Version\*\s+"([^"]+)"', text)
    dated = re.search(r'^;;; 日期：(\d{4}-\d{2}-\d{2})', text, re.MULTILINE)
    if not version or not dated:
        raise ValueError('COMMAND_SOURCE_METADATA_MISSING')
    prefix = f';;; 修复版独立命令：加载仅注册，输入 YJSTFIX 执行。\n;;; 日期：{dated.group(1)}\n'
    prefix += r'''(if (or (and (boundp '*OCS:Running*) *OCS:Running*)
            (and (boundp '*OCS:UndoMark*) *OCS:UndoMark*))
  (progn
    (princ "\n存在未结束操作或未关闭撤销分组。本次未加载修复代码，请先处理原恢复状态。")
    (exit)))
'''
    suffix = r'''
;;; 本文件由 build_gb2312.py 生成；加载完成后手动输入 YJSTFIX 转换当前图纸。
(princ "\n修复版独立命令已就绪：YJSTFIX。")
(princ)
'''
    return version.group(1), prefix, suffix


def convert_one(source: Path, target: Path, prefix: str = '', suffix: str = '') -> int:
    try:
        raw = source.read_bytes()
    except OSError as exc:
        print(f"SOURCE_ERROR: {source.resolve()}: {exc}")
        return 1
    try:
        text = prefix + raw.decode("utf-8-sig", errors="strict") + suffix
    except UnicodeDecodeError as exc:
        print(f"SOURCE_ERROR: {source.resolve()}: {exc}")
        return 1

    try:
        payload = text.encode("gb2312", errors="strict")
    except UnicodeEncodeError as exc:
        line = text.count("\n", 0, exc.start) + 1
        column = exc.start - text.rfind("\n", 0, exc.start)
        bad = text[exc.start : exc.end]
        print(f"ENCODING_ERROR: {source.resolve()}:{line}:{column}: {bad!r}")
        return 1

    if payload.decode("gb2312", errors="strict") != text:
        raise RuntimeError("GB2312 round-trip mismatch")

    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(target.suffix + ".tmp")
    temporary.write_bytes(payload)
    if temporary.read_bytes() != payload:
        raise RuntimeError("Written bytes mismatch")
    temporary.replace(target)

    delivered = target.read_bytes()
    if delivered != payload or delivered.decode("gb2312", errors="strict") != text:
        raise RuntimeError("Delivered file mismatch")

    print(f"DELIVERABLE: {target.resolve()}")
    print(f"  ENCODING: GB2312, no BOM; BYTES: {len(delivered)}")
    print(f"  SHA256: {sha256(delivered).hexdigest()}")
    return 0


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    outdir = root / "output" / "gb2312"
    print(f"BUILD_TIME: {datetime.now().astimezone().isoformat(timespec='seconds')}")
    print(f"REPO_ROOT: {root}")
    failed = 0
    for name in LOAD_FILES:
        source = root / name
        target = outdir / name
        print(f"SOURCE: {source.resolve()}")
        failed += convert_one(source, target)
    if not failed:
        source = root / 'one-click-simsun.lsp'
        version, prefix, suffix = command_parts(source.read_text(encoding='utf-8-sig'))
        target = outdir / f'YJSTFIX-v{version}.lsp'
        print(f"COMMAND_SOURCE: {source.resolve()}")
        failed += convert_one(source, target, prefix, suffix)
        # 日期：2026-10-14。撤回上一轮已交付的自动执行入口，避免旧链接仍自动转换。
        retired = outdir / 'RUN-YJST-v0.2.12.lsp'
        if not failed and retired.exists():
            notice = (';;; 日期：2026-10-14\n;;; 自动转换入口已停用。\n'
                      f'(princ "\\n此自动转换入口已停用。请 APPLOAD YJSTFIX-v{version}.lsp，输入 YJSTFIX 执行。")\n'
                      '(princ)\n')
            retired.write_bytes(notice.encode('gb2312', errors='strict'))
            print(f"RETIRED_AUTORUN: {retired.resolve()}")
    if failed:
        print(f"BUILD FAILED: {failed} file(s)")
        return 1
    print("BUILD OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
