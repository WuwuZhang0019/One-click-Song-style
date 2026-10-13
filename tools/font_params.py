"""Sign the text style font metadata the same way AutoCAD's DXF group 1071 does.

The plan (docs/AutoLISP一键统一宋体实施方案.md section 3) requires the
SimSun font file, typeface, charset and pitch/family to be validated on the
target AutoCAD rather than assumed.  This helper documents the exact value
that OCS:pack1071 / vla-SetFont must produce for SimSun and lets the native
acceptance run compare it against what AutoCAD actually wrote.
"""

from __future__ import annotations

ANSI_CHARSET = 0
DEFAULT_CHARSET = 1
GB2312_CHARSET = 134
OEM_CHARSET = 255

DEFAULT_PITCH = 0
FIXED_PITCH = 1
VARIABLE_PITCH = 2
FF_DONTCARE = 0
FF_ROMAN = 16
FF_SWISS = 32
TMPF_TRUETYPE = 4

# SimSun: variable pitch, roman (serif) family, TrueType
SIMPITCHFAMILY = VARIABLE_PITCH | FF_ROMAN | TMPF_TRUETYPE  # 0x16 = 22
SIM_CHARSET = GB2312_CHARSET  # 134

SUN_FAMILY = "SimSun"
SUN_FONTFILE_CANDIDATES = ["simsun.ttc", "simsun.ttf", "SIMSUN.TTC"]
REJECTED_FAMILIES = ["NSimSun", "SimHei", "STSong"]


def pack_1071(charset: int, bold: bool, italic: bool, pitch_family: int) -> int:
    v = charset & 0xFF
    if bold:
        v |= 1 << 8
    if italic:
        v |= 1 << 9
    v |= (pitch_family & 0xFF) << 16
    # DXF group 1071 is a signed 32-bit long
    if v >= 1 << 31:
        v -= 1 << 32
    return v


def unpack_1071(v: int) -> tuple[int, bool, bool, int]:
    if v < 0:
        v += 1 << 32
    return (v & 0xFF, bool(v & (1 << 8)), bool(v & (1 << 9)), (v >> 16) & 0xFF)


def expected_simsun_1071(bold: bool = False, italic: bool = False) -> int:
    return pack_1071(SIM_CHARSET, bold, italic, SIMPITCHFAMILY)


def mtext_font_code(family: str, *, bold: int = 0, italic: int = 0) -> str:
    """Font switch code used inside MTEXT raw content.

    日期：2026-10-13。采用与 SetFont 一致的候选参数 22，仍需原生读回验证。
    """
    pf = SIMPITCHFAMILY  # 2 | 16 | 4 = 22，与 LISP 目标参数一致
    return f"\\f{family}|b{bold}|i{italic}|c{SIM_CHARSET}|pf{pf};"


if __name__ == "__main__":
    print("SimSun 1071 (regular) =", expected_simsun_1071())
    print("SimSun 1071 (b1)      =", expected_simsun_1071(bold=True))
    print("sample MTEXT code     =", repr(mtext_font_code("SimSun", bold=1)))
    print("roundtrip:", unpack_1071(expected_simsun_1071(bold=True, italic=True)))
