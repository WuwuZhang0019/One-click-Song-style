"""build_gb2312.py - 把 UTF-8 开发源码构建为 GB2312 交付插件。

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

# 需要纳入同一构建与校验流程的实际加载文件清单（入口 + 辅助文件）。
# 只有被 CAD 实际 LOAD/APPLOAD 的文件才放入 output/gb2312。
LOAD_FILES = ["one-click-simsun.lsp"]


def convert_one(source: Path, target: Path) -> int:
    try:
        raw = source.read_bytes()
    except OSError as exc:
        print(f"SOURCE_ERROR: {source.resolve()}: {exc}")
        return 1
    try:
        text = raw.decode("utf-8-sig", errors="strict")
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
    if failed:
        print(f"BUILD FAILED: {failed} file(s)")
        return 1
    print("BUILD OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
