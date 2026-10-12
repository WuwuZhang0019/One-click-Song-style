# AutoCAD 验收记录 —— 一键统一宋体（YJST）

日期：2026-10-12
状态：部分验证（静态与纯逻辑检查已通过；原生 AutoCAD 内执行验证受本机环境限制，未完成）

---

## 1 环境

| 项 | 值 | 来源 |
| --- | --- | --- |
| 操作系统 | Windows NT 10.0 (10.0.26200.0) | `[Environment]::OSVersion` |
| AutoCAD 2020 | 23.1.47.0，简体中文，安装于 `C:\Software\Autodesk\AutoCAD 2020` | 卸载注册表 / `acmgd.dll` 版本 |
| AutoCAD 2022 | 24.1.51.0，简体中文，安装于 `C:\Software\Autodesk\AutoCAD 2022` | 卸载注册表 / `acmgd.dll` 版本 |
| 目标字体 | `C:\Windows\Fonts\simsun.ttc`（内部名同时含 `SimSun` 与 `NSimSun`），`STSONG.TTF`（内部名 `STSong`）为**非目标**字体 | 直接读取字体文件名表 |
| Git | 2.50.1.windows.1 | `git --version` |
| Python | 3.14（`C:\Users\Administrator\AppData\Local\Programs\Python\Python314`） | `where python` |

字体参数（写入目标，S01 待原生确认项）：

| 参数 | 值 | 说明 |
| --- | --- | --- |
| 字体族（typeface） | `SimSun` | `vla-SetFont` 第 1 参数 |
| FontFile | `simsun.ttc`（优先文件名，失败回退绝对路径） | `vla-put-FontFile` |
| CharSet | 134（GB2312） | `SetFont` 第 4 参数 |
| PitchAndFamily | 36（0x24 = VARIABLE_PITCH\|FF_ROMAN\|TMPF_TRUETYPE） | `SetFont` 第 5 参数 |
| DXF 1071 | 常规 1441926；b1 1442182 | `tools/font_params.py` 打包结果 |
| MTEXT 字体码 pf | 22（0x16，去掉 TMPF 标志） | MTEXT 描述参数不含 TrueType 标志 |
| 大字体清空路径 | STYLE 组码 4 → `entmod` 写空 → DXF + COM 双读回 | 方案第 3 节候选路径 |

---

## 2 本机原生执行尝试与结论（S01 关键证据）

### 2.1 尝试记录

| 尝试 | 命令/方式 | 结果 |
| --- | --- | --- |
| A | `accoreconsole.exe 2020 /nologo` | 退出码 53，输出 `ERROR: Some thing went wrong. ErrorStatus=53` |
| B | `accoreconsole.exe 2022 /nologo` | 进程崩溃，退出码 `-1073741819`（0xC0000005） |
| C | 2022 崩溃事件 | `Faulting module name: AcPal.dll, version: 24.1.51.0, Exception code: 0xc0000005, Fault offset: 0xe4ba`（多次复现） |
| D | 2020 /s 空脚本、`/i 新建 dwg` | 仍报 ErrorStatus=53 / 76；未生成 DWG |
| E | 2022 `/isolate` 隔离用户配置、ASCII 工作目录 | 仍崩溃于 `AcPal.dll` |
| F | `acad.exe 2022 /b`（GUI + 脚本，无交互桌面） | 进程可存活（25 秒未退出），但无 GUI 消息泵，命令无法确认执行 |
| G | 直接加载 `probe1.lsp`/`probe2.lsp` 走 core console | 同 A/B，未能产出 `probe2.out` |

**结论**：本机 headless 自动化通道不可用——2022 的 `AcPal.dll` 启动即崩（0xC0000005），2020 返回 ErrorStatus=53/76；2020/2022 均未出现可用的交互式 AutoCAD 会话。因此 **S01「至少一个明确的目标 CAD 版本通过字体转换与关键数据往返试验」这一完成条件在本机无法满足**，方案第 13 节要求的原生验收转为「待用户在可用的 AutoCAD 环境中执行」。

### 2.2 已通过的验证（不依赖 CAD 运行时）

| 检查 | 工具 | 结果 |
| --- | --- | --- |
| 括号/字符串/注释结构、UTF-8 无 BOM | `tools/check_lisp.py` | PASS（153 个顶层 form，140 个函数） |
| 方案第 8 节 13 个必需函数齐全 | 同上 | PASS |
| 函数前缀 `OCS:`/`c:` 唯一且无重复 defun | 同上 | PASS |
| 禁止行为静态扫描（ATTSYNC/EXPLODE/ResetBlock/SAVEAS/裸 UNDO、setvar 环境变量） | 同上 | PASS（回滚路径仅允许一次 `"_.U"`） |
| 15 个扫描器样例结构自洽（字段区逐字节一致、非字体格式码一致、目标族一致、幂等标记一致） | 同上 | PASS |
| 15 个用例 ID 均在 LISP 源码中登记 | 同上 | PASS（C01–C15 注释清单） |
| 1071 打包/解包往返 | `python tools/font_params.py` | PASS（1441926/1442182 往返正确） |
| Interop 元数据存在性 | PowerShell 字符串扫描 `Autodesk.AutoCAD.Interop.Common.dll` | `RegenerateTableSuppressed`、`FieldCode`、`MTextAttributeContent`、`GetConstantAttributes`、`UpdateMTextAttribute`、`BigFontFile`、`SetFont`、`GetTextString/SetTextString`、`GetFieldId/SetFieldId` 均存在 |
| 官方文档核对 | Autodesk 帮助（FontFile、SetFont、BigFontFile、STYLE DXF、TextOverride、MTextAttributeContent、Table 对象） | 与实现一致；BigFontFile「不能设为 NULL 或空字符串」已按组码 4 路径绕开 |

### 2.3 明确的未验证项（不得当作通过）

| 编号 | 项目 | 状态 |
| --- | --- | --- |
| S01 全部 | 目标 CAD 版本字体转换、SHX/Bigfont/TTF/竖排/注释性样式试验、长文本与字段/表格内容项/动态块往返 | **未验证**（headless 通道不可用） |
| T01–T17、T19–T23 | 全部原生场景 | **未验证**（需在可用 AutoCAD 中运行 `tests/native/ocs-native-checks.lsp` 的 OCS_T01…OCS_T23 命令） |
| T18 | 二次运行零有效修改、空图纸 | **未验证**（逻辑已实现，等原生执行） |
| 字形 | SimSun 缺失字形、私用区字符、打印/PDF 显示 | **未验证** |
| 外参 | T15 外部参照保持原状 | **未验证**（本机无参照样例） |
| 表格内容项上限 | 实现中上限 64、越界判定依赖 `0x8002000B`/含 “index/超出” 的错误串 | **未验证**（需在原生确认该版本错误文本） |
| MTEXT 长文本读回 | 使用 `vla-get-TextString`/`vla-put-TextString` 整串往返 | **未验证**（方案要求以长文本往返试验为准） |
| Esc 中断 | `vl-catch-all-apply 'OCS:executeWrites` 捕获 → 恢复临时状态 + 结束分组 + 一次 `_.U` | **未验证**（需交互式原生测试） |

---

## 3 已实现与静态可证的行为

- **扫描器**（`OCS:NormalizeFontRuns`，纯函数）：逐字符扫描；先转义（`\` 后接合法转义字符，`\f`/`\F` 例外走字体分支）→ 字段 `%<…>%` 整体保护（支持嵌套 `%<` 与转义）→ 字体指令 `\f`/`\F`（后随字符非字母才认定）；字段内 `\f` 不替换；正文中的字体名不改；解析失败只记录 `(code pos len msg)`，不删段落；已是目标族原样保留（幂等）。
- **样式**：按组码 70 位 1/16 分类跳过形文件与外参依赖记录；`Standard`、注释性、未使用样式照常处理；写入顺序 `FontFile → SetFont → 组码4清空大字体 → 读回`；读回校验 40/41/50/70/71/1071/XData 键数不变。
- **遍历**：以 `Blocks` 集合为主入口，块按句柄去重；外参块不进入；`*D…` 动态表示与 `*U…` 显示缓存分类（显示缓存记为跳过并计数，交源宿主处理）；块引用额外读 `GetAttributes`/`GetConstantAttributes`。
- **宿主**：TEXT/MTEXT、ATTRIB/ATTDEF（含多行 `MTextAttributeContent` + `UpdateMTextAttribute`）、标注 `TextOverride`、公差、普通引线（改关联注释）、多重引线、表格（`RegenerateTableSuppressed` 临时抑制并恢复、行列 × 内容项枚举、字段/公式不回写显示值）。
- **撤销/回滚**：`vla-StartUndoMark` 分组；错误或 Esc 路径：恢复临时状态 → `EndUndoMark` → 恰好一次 `command "_.U"` → 读回核对（大字体是否恢复）→ `:recoverFailed` 独立标记；绝不无条件 `UNDO Back`。
- **状态判定**：`已完成 / 无需修改 / 部分完成 / 失败已回滚 / 恢复失败` 与方案第 12 节一致；预检失败不写入任何业务数据。
- **报告**：中文摘要输出样式/宿主/字体段/属性/表格内容项/外参/未覆盖/错误/恢复失败数量；`*OCS:LastReport*` 保留结构化结果。

---

## 4 GB2312 交付构建记录（2026-10-12）

按 `docs/GB2312编码修复与加载复测说明.md` 落实编码交付：

| 项 | 结果 |
| --- | --- |
| UTF-8 开发源码 | `one-click-simsun.lsp`（无 BOM，严格 UTF-8 解码通过） |
| 不可编码字符清理 | 源码中 8 处 `U+2014` 破折号改为 GB2312 可表示写法；`find_non_gb2312.py` 报 0 |
| 交付文件 | `output/gb2312/one-click-simsun.lsp`，严格 GB2312、无 BOM、81903 字节 |
| SHA-256 | `83a294dc23d95c7ac811f2401dfd5e48f26f3fb49f216d688c0b065d6014f005`（2026-10-12T22:19:28+08:00 重建；此前一版 `2d4ff7c9…eeefc` 因加载错误修复被替换） |
| 构建工具样例检查 | `tools/test_build_gb2312.py` 5 项 PASS（中文转换、BOM 去除、行列报错且不覆盖旧交付、非法 UTF-8、源缺失） |
| 静态检查 | `check_lisp.py` PASS（151 form / 139 函数 / 15 用例） |
| 目标 CAD 加载 GB2312 文件 | 曾报 `no function definition: FN`，已定位修复（见 GB2312 说明第 9 节：`defmacro` 死代码被旧引擎当调用求值，已删除；加载提示防御化）；**修复后复测未验证** |
| YJST 功能复测（GB2312 版） | **未验证** |

复测请加载 `output/gb2312/one-click-simsun.lsp` 并核对上表 SHA-256；不要加载仓库根目录的 UTF-8 源文件。

---

## 5 下一步（在可用 AutoCAD 中）

1. `APPLOAD` 加载 **`output/gb2312/one-click-simsun.lsp`**（核对 SHA-256 与构建时间），命令行执行 `OCS_ENV` 记录版本与字体参数（对应本表第 1 节，确认 1071/charset/pf 与实现一致）。
2. 执行 `OCS_SCANNER`（纯函数 15 用例）与 `OCS_T01`…`OCS_T23`，把输出日志（`C:\Temp\ocs\ocs-*.log`）回填本记录。
3. 特别确认：中文长文本在多字节字符串下的 `strlen`/`substr` 行为、大字体组码 4 清空与 COM 读回、表格内容项越界错误文本、MTEXT 长文本往返、一次 `U`、Esc、二次零修改、保存重开与 PDF。
4. 全部回填后，将本文件状态改为「原生验收通过」并更新方案第 10 节阶段进度。
