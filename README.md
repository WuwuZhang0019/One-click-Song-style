# 一键统一宋体（YJST）

日期：2026-10-12　状态：可加载使用，原生验收部分完成（见 [docs/AutoCAD验收记录.md](docs/AutoCAD验收记录.md)）

一条命令 `YJST` 把**当前 DWG** 内的文字字体统一为宋体（SimSun），保留字高、宽度、旋转、对齐、图层、颜色等其他格式；不逐个选择、不弹确认框。

## 使用步骤

1. 根目录 `one-click-simsun.lsp` 是 UTF-8 开发源码。当前目标 CAD 要求 GB2312；按 [编码修复说明](docs/GB2312编码修复与加载复测说明.md) 生成并验证 `output/gb2312/one-click-simsun.lsp` 后，运行 `APPLOAD` 加载该交付文件（提示 `一键统一宋体（YJST）v0.1.0 已加载`）。
2. 命令行输入 `YJST` 回车。
3. 程序自动完成：环境与字体预检 → 扫描并生成修改计划 → Undo 分组 → 写入样式与内容 → 恢复临时状态 → 再生 → 读回检查 → 输出中文摘要。
4. 查看命令行摘要；结构化结果保存在 `*OCS:LastReport*`（Visual LISP 控制台或 `(princ *OCS:LastReport*)` 可读）。
5. 一次 `U` 即可撤销本次转换（不撤销你之前的操作）。

## 覆盖范围

- 模型空间与全部布局（含关闭/冻结/锁定图层上的本图文字；锁定层临时解锁后恢复）
- 普通块、嵌套块、未插入的块定义、动态块原始定义与匿名表示
- `ATTDEF`、已有 `ATTRIB`、常量属性与多行属性
- `TEXT`、`MTEXT`（局部字体覆盖）、标注/公差、普通引线、多重引线、表格、字段宿主
- 文字样式：`Standard`、注释性、未使用的普通样式（保留样式名与引用关系，只改字体定义）

**跳过（不计入本图完成缺口）**：外部参照块与依赖样式（不打开、不改写外部文件）、SHAPE/形文件记录、PDF/图片/OLE/已轮廓化文字、标注与表格的显示缓存匿名块（交源宿主处理）。
**专业/代理对象**：无法解析其内部文字时记入报告的“未覆盖”明细，整体状态最多为“部分完成”。

## 不做的事

不改字高/宽度/倾斜/旋转/对齐/图层/颜色等非字体数据；不缩字、不压宽、不移动对象；不执行 `ATTSYNC`、`ResetBlock`、`EXPLODE`、`SAVEAS` 或自动保存；不修改 `FONTALT`、`FONTMAP`、`SECURELOAD`、`LISPSYS`。

字体缺失或预检失败时**在写入任何业务数据之前退出**，不会静默换成黑体/NSimSun/STSong。

## 文件

```
one-click-simsun.lsp              UTF-8 开发源码（不要直接加载到 CAD）
output/gb2312/one-click-simsun.lsp GB2312 CAD 加载交付文件（APPLOAD 只加载它）
output/gb2312/crlf/               CRLF 行尾变体（行尾实验用）
output/gb2312/probe/              引擎特性探针 p01–p13（配合 ocs-probe.lsp）
output/gb2312/parts/              主文件二分部件 part1–12（配合 ocs-bisect.lsp）
output/gb2312/ocs-probe.lsp       探针驱动（命令 OCS_PROBE）
output/gb2312/ocs-bisect.lsp      二分驱动（命令 OCS_BISECT）
docs/
  AutoLISP一键统一宋体实施方案.md   实施方案（实现与验收依据）
  GB2312编码修复与加载复测说明.md  编码转换、加载指引与复测清单
  语法错误定位排查指南.md           「语法错误」探针/二分定位步骤与修法对照表
  AutoCAD验收记录.md               环境、证据、未验证项、GB2312 构建记录
tests/
  font-format-cases.json          扫描器 15 个样例（C01–C15）
  native/ocs-native-checks.lsp    原生检查与故障注入入口（OCS_T01…OCS_T23、OCS_ENV、OCS_SCANNER）
  native/probe1.lsp probe2.lsp    S01 环境探针（开发用）
tools/
  build_gb2312.py                 UTF-8 → GB2312 严格构建与校验
  build_diag.py                   生成诊断工具包（探针/二分/CRLF 变体）
  test_build_gb2312.py            构建工具 5 项样例检查
  find_non_gb2312.py              列出无法 GB2312 表示的字符
  lisp_reader_probe.py            模拟 AutoLISP 读入器的结构检查（括号/字符串/注释/转义）
  check_lisp.py                   静态结构与样例一致性检查
  font_params.py                  SimSun 1071/字符集/pitch-family 计算
```

## 自检与检查

```powershell
python -X utf8 tools\build_gb2312.py     # 构建 GB2312 交付文件（含严格校验与 SHA-256）
python -X utf8 tools\build_diag.py       # 构建诊断工具包（探针/二分部件/CRLF 变体）
python -X utf8 tools\test_build_gb2312.py # 构建工具 5 项样例检查
python -X utf8 tools\find_non_gb2312.py   # 列出源码中无法 GB2312 表示的字符
python tools\check_lisp.py                # 结构、必需函数、禁止行为、样例一致性
python tools\lisp_reader_probe.py output\gb2312\one-click-simsun.lsp  # AutoLISP 读入器结构检查
python tools\font_params.py               # 1071 打包值
```

AutoCAD 内（加载交付文件后）：

- `OCS_SCANNER` —— 纯函数扫描器 15 用例自检
- `OCS_ENV` —— 记录版本与字体参数
- `OCS_T01` … `OCS_T23` —— 对应验收矩阵场景（详见 `tests/native/ocs-native-checks.lsp` 头部说明）
- `OCS_PROBE` / `OCS_BISECT` —— 引擎特性探针 / 主文件二分定位（加载失败排查用，见排查指南）

## 已知未验证项

见 [docs/AutoCAD验收记录.md](docs/AutoCAD验收记录.md) 第 2.3 与第 4 节：本机 AutoCAD core console 启动即崩溃（2022 `AcPal.dll` 0xC0000005 / 2020 ErrorStatus=53），GB2312 交付文件的目标 CAD 加载与 `YJST` 功能复测、原生场景 T01–T23、保存重开、打印显示等需在可用的 AutoCAD 环境中执行后回填。

目标 CAD 加载 GB2312 交付文件报「语法错误」的最新定位：交付文件对标准 AutoLISP 读入规则完全干净（`tools/lisp_reader_probe.py` 0 错误），报错源于目标引擎独有限制（该引擎不把 `defmacro` 当特殊形式，疑似 ZWCAD Classic "LISP Release 1.0"）。已生成探针/二分诊断工具包，步骤见 [docs/语法错误定位排查指南.md](docs/语法错误定位排查指南.md)。
