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
SIMPITCHFAMILY = VARIABLE_PITCH | FF_ROMAN | TMPF_TRUETYPE  # 0x24 = 36
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

    Note: the MTEXT pitch/family parameter is the raw Win32 value WITHOUT the
    TrueType flag (that flag appears only in DXF group 1071 / SetFont), so
    SimSun uses pf22 (VARIABLE_PITCH|FF_ROMAN) here and pf36 (0x24) in 1071.
    """
    pf = SIMPITCHFAMILY & 0x0F  # 22 = VARIABLE_PITCH|FF_ROMAN (TrueType flag stripped)
    return f"\\f{family}|b{bold}|i{italic}|c{SIM_CHARSET}|pf{pf};"


if __name__ == "__main__":
    print("SimSun 1071 (regular) =", expected_simsun_1071())
    print("SimSun 1071 (b1)      =", expected_simsun_1071(bold=True))
    print("sample MTEXT code     =", repr(mtext_font_code("SimSun", bold=1)))
    print("roundtrip:", unpack_1071(expected_simsun_1071(bold=True, italic=True)))
