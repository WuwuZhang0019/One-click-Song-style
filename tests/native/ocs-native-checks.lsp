;;; =====================================================================
;;; ocs-native-checks.lsp
;;; 原生 AutoCAD 检查与故障注入入口（开发/验收用，不是用户入口）
;;; 日期：2026-10-12   状态：待在原生 AutoCAD 中执行并记录结果
;;;
;;; 使用：
;;;   1. APPLOAD 加载 ..\..\one-click-simsun.lsp（先）与本文件（后）
;;;   2. 命令行执行对应检查命令：
;;;        OCS_T01   单行文字 + SHX 样式（T01）
;;;        OCS_T02   SHX + Bigfont 清空（T02）
;;;        OCS_T03   Standard 与注释性样式（T03）
;;;        OCS_T04   多行文字混合字体（T04）
;;;        OCS_T05   嵌套格式/转义/长文本（T05）
;;;        OCS_T06   模型空间与多布局、锁定层（T06）
;;;        OCS_T07   普通块/嵌套块/未插入定义（T07）
;;;        OCS_T08   动态块（T08）
;;;        OCS_T09   属性定义/实例/常量/多行（T09）
;;;        OCS_T10   标注/公差/普通引线（T10）
;;;        OCS_T11   多重引线（T11）
;;;        OCS_T12   表格普通与合并单元格（T12）
;;;        OCS_T13   表格多内容项/字段/公式/数据链接（T13）
;;;        OCS_T14   文字字段与嵌套字段（T14）
;;;        OCS_T15   外部参照（T15，需要参照源文件）
;;;        OCS_T16   竖排/镜像/Fit/Aligned（T16）
;;;        OCS_T17   特殊符号与私用区字符（T17）
;;;        OCS_T18   二次运行与空图纸（T18）
;;;        OCS_T19   字体缺失与前置条件失败（T19）
;;;        OCS_T20   一次撤销（T20）
;;;        OCS_T21   中途错误/Esc/恢复失败（T21）
;;;        OCS_T22   保存重开/动态状态/PDF（T22）
;;;        OCS_T23   专业实体与代理对象（T23）
;;;        OCS_SCANNER   纯函数扫描器自检（不依赖图纸）
;;;        OCS_FAULT     设置故障注入点（样式写入/内容写入/再生检查）
;;;        OCS_ENV       环境与字体参数记录
;;; =====================================================================

(vl-load-com)

(setq *OCS:NativeLog* nil)

(defun OCS:log (msg)
  (setq *OCS:NativeLog* (append *OCS:NativeLog* (list msg)))
  (princ (strcat "\n" msg))
  (princ)
)

;; 结果写入磁盘，供验收记录收集
(defun OCS:dumpLog (path / f)
  (setq f (open path "w"))
  (foreach m *OCS:NativeLog*
    (write-line m f)
  )
  (close f)
  (princ (strcat "\n日志已写入 " path))
  (princ)
)

;; 判断样式当前字体族
(defun OCS:styleFontInfo (name / ent e)
  (setq ent (tblobjname "STYLE" name))
  (if (not ent)
    (list :exists nil)
    (progn
      (setq e (entget ent))
      (list :exists T
            :fontFile (OCS:assocd 3 e "")
            :bigFont  (OCS:assocd 4 e "")
            :height    (OCS:assocd 40 e nil)
            :width     (OCS:assocd 41 e nil)
            :oblique   (OCS:assocd 50 e nil)
            :flags     (OCS:assocd 70 e 0)
            :genFlags  (OCS:assocd 71 e 0)
            :1071      (OCS:assocd 1071 e nil))
    )
  )
)

;; 创建测试样式
(defun OCS:mkStyle (name fontfile bigfont height width oblique / doc ent)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq ent (tblobjname "STYLE" name))
  (if ent (entdel ent))
  (vla-AddTextStyle doc name fontfile :vlax-true)
  (setq ent (tblobjname "STYLE" name))
  (if (and ent bigfont (/= bigfont ""))
    (vla-put-BigFontFile (vlax-ename->vla-object ent) bigfont)
  )
  (if (and ent height)
    (progn
      (vla-put-Height (vlax-ename->vla-object ent) height)
    )
  )
  (if (and ent width)
    (vla-put-Width (vlax-ename->vla-object ent) width)
  )
  (if (and ent oblique)
    (vla-put-ObliqueAngle (vlax-ename->vla-object ent) oblique)
  )
  ent
)

;; 在模型空间添加单行文字
(defun OCS:mkText (str style height pt / ms)
  (setq ms (vla-get-ModelSpace (vla-get-ActiveDocument (vlax-get-acad-object))))
  (setq e (vla-AddText ms str (vlax-3d-point pt) height))
  (vla-put-StyleName e style)
  e
)

;; 在模型空间添加多行文字（原始格式串）
(defun OCS:mkMText (raw style height pt / ms)
  (setq ms (vla-get-ModelSpace (vla-get-ActiveDocument (vlax-get-acad-object))))
  (setq e (vla-AddMText ms (vlax-3d-point pt) 200.0 raw))
  (vla-put-StyleName e style)
  (if height (vla-put-Height e height))
  e
)

;; 读取 MTEXT 原始内容
(defun OCS:getRaw (e)
  (vla-get-TextString e)
)

;;; ----------------------------------------------------------------------
;;; OCS_ENV：记录环境与字体参数（S01 产物）
;;; ----------------------------------------------------------------------
(defun c:OCS_ENV ( / f font )
  (OCS:log "--- OCS_ENV 环境与字体参数 ---")
  (OCS:log (strcat "ACADVER=" (getvar "ACADVER")))
  (OCS:log (strcat "PRODUCT=" (getvar "PRODUCT")))
  (OCS:log (strcat "MENUNAME=" (getvar "MENUNAME")))
  (OCS:log (strcat "PLATFORM=" (getvar "PLATFORM")))
  (OCS:log (strcat "LISPSYS=" (itoa (getvar "LISPSYS"))))
  (OCS:log (strcat "UNDOCTL=" (itoa (getvar "UNDOCTL"))))
  (OCS:log (strcat "FONTALT(读取)=" (getvar "FONTALT")))
  (OCS:log (strcat "FONTMAP(读取)=" (getvar "FONTMAP")))
  (OCS:log (strcat "SECURELOAD(读取)=" (itoa (getvar "SECURELOAD"))))
  (setq font (OCS:ResolveSongFont))
  (OCS:log (strcat "字体解析 :ok=" (if (OCS:getVal font :ok) "T" "NIL")))
  (OCS:log (strcat "  :family=" (OCS:fmt (OCS:getVal font :family))))
  (OCS:log (strcat "  :fontFile=" (OCS:fmt (OCS:getVal font :fontFile))))
  (OCS:log (strcat "  :fontFileSource=" (OCS:fmt (OCS:getVal font :fontFileSource))))
  (OCS:log (strcat "  :fontFileReadback=" (OCS:fmt (OCS:getVal font :fontFileReadback))))
  (OCS:log (strcat "  :bigFontEmpty=" (if (OCS:getVal font :bigFontEmpty) "T" "NIL")))
  (foreach item font
    (if (and (consp item) (eq (car item) :problem))
      (OCS:log (strcat "  问题[" (vl-symbol-name (cadr item)) "] " (caddr item)))
    )
  )
  (OCS:log (strcat "1071(常规)=" (itoa (OCS:pack1071 134 nil nil 36))
                   "  1071(b1)=" (itoa (OCS:pack1071 134 T nil 36))))
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-env.log")
  (princ)
)

;;; ----------------------------------------------------------------------
;;; OCS_SCANNER：纯函数扫描器自检（S02）
;;; ----------------------------------------------------------------------
(defun c:OCS_SCANNER ( / n )
  (OCS:log "--- OCS_SCANNER 纯函数扫描器自检 ---")
  (setq n (OCS:SelfTest))
  (if (= n 0)
    (OCS:log "扫描器自检：全部通过")
    (OCS:log (strcat "扫描器自检：失败 " (itoa n) " 项"))
  )
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-scanner.log")
  (princ)
)

;;; ----------------------------------------------------------------------
;;; OCS_FAULT：故障注入点
;;; 可用点："style-write"  "content-write"  "regen-check"
;;; ----------------------------------------------------------------------
(defun c:OCS_FAULT ( / pt)
  (princ "\n故障注入点 (style-write / content-write / regen-check / 空=清除)：")
  (setq pt (getstring T))
  (if (= pt "")
    (progn (setq *OCS:FaultPoint* nil) (princ "\n已清除故障注入点"))
    (progn (setq *OCS:FaultPoint* pt) (princ (strcat "\n故障注入点=" pt)))
  )
  (princ)
)

;;; ----------------------------------------------------------------------
;;; T01 单行文字与原有 SHX 样式
;;; ----------------------------------------------------------------------
(defun c:OCS_T01 ( / ent before after ok)
  (OCS:log "--- T01 单行文字 + SHX 样式 ---")
  (OCS:mkStyle "OCSSHX" "txt.shx" "" 0.0 1.0 0.0)
  (setq ent (OCS:mkText "T01 单行文字 hello" "OCSSHX" 3.5 (list 0.0 0.0 0.0)))
  (setq before (OCS:styleFontInfo "OCSSHX"))
  (c:YJST)
  (setq after (OCS:styleFontInfo "OCSSHX"))
  (setq ok (and (OCS:containsSimsunFont (OCS:assocd :fontFile after ""))
                (equal (OCS:assocd :width before nil) (OCS:assocd :width after nil) 1e-9)
                (equal (OCS:oblique before nil) (OCS:oblique after nil) 1e-9)))
  (OCS:log (strcat "T01 字高=" (rtos (vla-get-Height ent) 2 4)
                   " 宽度因子=" (rtos (vla-get-Width ent) 2 4)
                   " 旋转=" (rtos (vla-get-Rotation ent) 2 4)
                   " 对齐=" (itoa (vla-get-Alignment ent))))
  (OCS:log (strcat "T01 样式读回 fontFile=" (OCS:fmt (OCS:assocd :fontFile after ""))
                   " bigFont=[" (OCS:fmt (OCS:assocd :bigFont after "")) "]"))
  (OCS:log (if ok "T01 结果：通过（待人工核对字形）" "T01 结果：失败"))
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t01.log")
  (princ)
)

(defun OCS:containsSimsunFont (s)
  (or (OCS:strContains (OCS:lower s) "simsun")
      (OCS:strContains s "宋体"))
)

;;; ----------------------------------------------------------------------
;;; T02 SHX + Bigfont
;;; ----------------------------------------------------------------------
(defun c:OCS_T02 ( / ent before after)
  (OCS:log "--- T02 SHX 加 Bigfont ---")
  (OCS:mkStyle "OCSSHXBF" "txt.shx" "hz.shx" 0.0 1.0 0.0)
  (setq ent (OCS:mkText "T02 大字体测试" "OCSSHXBF" 3.5 (list 0.0 20.0 0.0)))
  (setq before (OCS:styleFontInfo "OCSSHXBF"))
  (OCS:log (strcat "T02 转换前 bigFont=[" (OCS:fmt (OCS:assocd :bigFont before "")) "]"))
  (c:YJST)
  (setq after (OCS:styleFontInfo "OCSSHXBF"))
  (OCS:log (strcat "T02 转换后 fontFile=" (OCS:fmt (OCS:assocd :fontFile after ""))
                   " bigFont=[" (OCS:fmt (OCS:assocd :bigFont after "")) "]"))
  (if (= "" (OCS:assocd :bigFont after ""))
    (OCS:log "T02 结果：大字体已清空（保存重开后需人工复查）")
    (OCS:log "T02 结果：失败（大字体未清空）")
  )
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t02.log")
  (princ)
)

;;; ----------------------------------------------------------------------
;;; T03 Standard 与注释性样式
;;; ----------------------------------------------------------------------
(defun c:OCS_T03 ( / ent okStd okAnn)
  (OCS:log "--- T03 Standard 与注释性样式 ---")
  (OCS:mkText "T03 Standard 文字" "Standard" 3.5 (list 0.0 40.0 0.0))
  ;; 注释性样式
  (OCS:mkStyle "OCSANN" "txt.shx" "" 0.0 1.0 0.0)
  (setq ent (tblobjname "STYLE" "OCSANN"))
  (if ent
    (progn
      (vla-put-Annotative (vlax-ename->vla-object ent) :vlax-true)
      (OCS:mkText "T03 注释性文字" "OCSANN" 3.5 (list 0.0 60.0 0.0))
    )
  )
  (c:YJST)
  (setq okStd (OCS:containsSimsunFont (OCS:assocd :fontFile (OCS:styleFontInfo "Standard") "")))
  (setq okAnn (OCS:containsSimsunFont (OCS:assocd :fontFile (OCS:styleFontInfo "OCSANN") "")))
  (OCS:log (strcat "T03 Standard 转换=" (if okStd "通过" "失败")))
  (OCS:log (strcat "T03 注释性样式转换=" (if okAnn "通过" "失败")
                   "（注释性状态需人工核对比例）"))
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t03.log")
  (princ)
)

;;; ----------------------------------------------------------------------
;;; T04 多行文字混合字体
;;; ----------------------------------------------------------------------
(defun c:OCS_T04 ( / e raw after)
  (OCS:log "--- T04 多行文字混合字体 ---")
  (OCS:mkStyle "OCSMIX" "txt.shx" "" 0.0 1.0 0.0)
  (setq e (OCS:mkMText "{\\fArial|b1|i0;标题}\\P{\\H0.7x;\\fSimHei|b0|i1;说明}"
                       "OCSMIX" nil (list 0.0 80.0 0.0)))
  (setq raw (OCS:getRaw e))
  (OCS:log (strcat "T04 原始内容=" raw))
  (c:YJST)
  (setq after (OCS:getRaw e))
  (OCS:log (strcat "T04 转换后=" after))
  (OCS:log (strcat "T04 字高=" (rtos (vla-get-Height e) 2 4)
                   " 宽度=" (rtos (vla-get-Width e) 2 4)))
  (if (and (OCS:strContains after "SimSun")
           (not (OCS:strContains after "\\fArial"))
           (not (OCS:strContains after "\\fSimHei"))
           (OCS:strContains after "\\H0.7x;"))
    (OCS:log "T04 结果：通过（字体已替换、字高覆盖保持）")
    (OCS:log "T04 结果：失败")
  )
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t04.log")
  (princ)
)

;;; ----------------------------------------------------------------------
;;; T05 嵌套格式/转义/长文本
;;; ----------------------------------------------------------------------
(defun c:OCS_T05 ( / e raw after longin longafter)
  (OCS:log "--- T05 嵌套格式、转义与长文本 ---")
  (OCS:mkStyle "OCST5" "txt.shx" "" 0.0 1.0 0.0)
  (setq e (OCS:mkMText "{\\fArial|b1;i;转义 \\\\ 与花括号 \\{\\} 保持}\\P\\S1/2;"
                       "OCST5" nil (list 0.0 100.0 0.0)))
  (setq raw (OCS:getRaw e))
  (c:YJST)
  (setq after (OCS:getRaw e))
  (OCS:log (strcat "T05 嵌套转换后=" after))
  ;; 长文本
  (setq longin "")
  (setq n 0)
  (while (< n 60)
    (setq longin (strcat longin "English ABC and Chinese 宋体测试 text "))
    (setq n (1+ n))
  )
  (setq e2 (OCS:mkMText longin "OCST5" nil (list 0.0 130.0 0.0)))
  (c:YJST)
  (setq longafter (OCS:getRaw e2))
  (OCS:log (strcat "T05 长文本长度 前=" (itoa (strlen longin)) " 后=" (itoa (strlen longafter))))
  (if (= (strlen longin) (strlen longafter))
    (OCS:log "T05 长文本：未截断")
    (OCS:log "T05 长文本：失败（长度变化）")
  )
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t05.log")
  (princ)
)

;;; ----------------------------------------------------------------------
;;; T06 模型空间/多布局/锁定层
;;; ----------------------------------------------------------------------
(defun c:OCS_T06 ( / doc layouts i layname layer lockedOK)
  (OCS:log "--- T06 布局与锁定层 ---")
  ;; 锁定层上的文字
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (if (not (tblsearch "LAYER" "OCSLOCK"))
    (command "_.-LAYER" "_M" "OCSLOCK" "")
  )
  (command "_.-LAYER" "_L" "ON" "OCSLOCK" "")
  (setq laylocked (vla-Item (vla-get-Layers doc) "OCSLOCK"))
  (vla-put-Lock laylocked :vlax-true)
  ;; 在锁定层加文字
  (setq ms (vla-get-ModelSpace doc))
  (setq e (vla-AddText ms "T06 锁定层文字" (vlax-3d-point (list 0.0 160.0 0.0)) 3.5))
  (vla-put-Layer e "OCSLOCK")
  (vla-put-StyleName e "Standard")
  ;; 第二个布局
  (setq layname (OCS:newLayout "OCS_LAYOUT_T06"))
  (c:YJST)
  (setq lockedOK (vla-get-Lock laylocked))
  (OCS:log (strcat "T06 锁定层状态恢复=" (if (equal lockedOK :vlax-true) "通过" "失败")))
  (OCS:log (strcat "T06 布局=" (OCS:fmt layname) "（布局内文字需人工核对）"))
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t06.log")
  (princ)
)

(defun OCS:newLayout (name)
  (if (not (tblsearch "LAYOUT" name))
    (command "_.-LAYOUT" "_N" name)
  )
  name
)

;;; ----------------------------------------------------------------------
;;; T07 普通块/嵌套块/未插入定义
;;; ----------------------------------------------------------------------
(defun c:OCS_T07 ( / ms e1 e2 bname)
  (OCS:log "--- T07 图块定义与嵌套 ---")
  (setq ms (vla-get-ModelSpace (vla-get-ActiveDocument (vlax-get-acad-object))))
  ;; 嵌套块：B2 内含文字，B1 引用 B2
  (setq b2 (vla-AddBlock (vla-get-Blocks (vla-get-ActiveDocument (vlax-get-acad-object)))
                         "OCS_B2" (vlax-3d-point (list 0.0 0.0 0.0)) T))
  (setq e (vla-AddText b2 "T07 内层块文字" (vlax-3d-point (list 0.0 0.0 0.0)) 3.5))
  (vla-put-StyleName e "Standard")
  (setq b1 (vla-AddBlock (vla-get-Blocks (vla-get-ActiveDocument (vlax-get-acad-object)))
                         "OCS_B1" (vlax-3d-point (list 0.0 0.0 0.0)) T))
  (setq e (vla-AddText b1 "T07 外层块文字" (vlax-3d-point (list 0.0 0.0 0.0)) 3.5))
  (vla-put-StyleName e "Standard")
  (setq ins (vla-InsertBlock ms (vlax-3d-point (list 200.0 0.0 0.0)) "OCS_B1" 1.0 1.0 1.0 0.0))
  ;; 未插入定义
  (setq b3 (vla-AddBlock (vla-get-Blocks (vla-get-ActiveDocument (vlax-get-acad-object)))
                         "OCS_B3_UNINSERTED" (vlax-3d-point (list 0.0 0.0 0.0)) T))
  (setq e (vla-AddText b3 "T07 未插入定义文字" (vlax-3d-point (list 0.0 0.0 0.0)) 3.5))
  (vla-put-StyleName e "Standard")
  (c:YJST)
  ;; 读回块内文字
  (OCS:log (strcat "T07 内层块读回=" (OCS:blockText "OCS_B2")))
  (OCS:log (strcat "T07 外层块读回=" (OCS:blockText "OCS_B1")))
  (OCS:log (strcat "T07 未插入定义读回=" (OCS:blockText "OCS_B3_UNINSERTED")))
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t07.log")
  (princ)
)

(defun OCS:blockText (bname / blk ents i e txt)
  (setq blk (vla-Item (vla-get-Blocks (vla-get-ActiveDocument (vlax-get-acad-object))) bname))
  (setq ents (vla-get-BlockEntities blk) i 1 txt "")
  (while (<= i (vla-get-Count ents))
    (setq e (vla-Item ents (1- i)))
    (if (vlax-method-applicable-p e 'TextString)
      (setq txt (strcat txt " | " (vla-get-TextString e)))
    )
    (setq i (1+ i))
  )
  txt
)

;;; ----------------------------------------------------------------------
;;; T08 动态块
;;; ----------------------------------------------------------------------
(defun c:OCS_T08 ( / )
  (OCS:log "--- T08 动态块 ---")
  (OCS:log "需要包含可见性参数的动态块样例（tests/native/fixtures/）。")
  (OCS:log "执行步骤：插入动态块 → YJST → 切换可见性状态 → 检查文字仍为宋体。")
  (OCS:log "状态：未执行（需样例 DWG）")
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t08.log")
  (princ)
)

;;; ----------------------------------------------------------------------
;;; T09 属性定义/实例/常量/多行
;;; ----------------------------------------------------------------------
(defun c:OCS_T09 ( / ms blk att)
  (OCS:log "--- T09 属性定义与属性实例 ---")
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq ms (vla-get-ModelSpace doc))
  (setq ab (vla-AddBlock (vla-get-Blocks doc) "OCS_ATTBLOCK" (vlax-3d-point (list 0.0 0.0 0.0)) T))
  (setq att (vla-AddAttribute ab 3.5 1 "提示 T09" (vlax-3d-point (list 0.0 0.0 0.0)) "TAG_T09" "T09 属性值"))
  (vla-put-StyleName att "Standard")
  ;; 多行属性
  (setq att2 (vla-AddAttribute ab 3.5 1 "多行提示" (vlax-3d-point (list 0.0 -10.0 0.0)) "TAG_ML" "T09 多行值"))
  (vla-put-MTextAttribute att2 :vlax-true)
  (vla-put-MTextAttributeContent att2 "T09 多行属性内容\\P第二行")
  (vla-put-StyleName att2 "Standard")
  (setq ins (vla-InsertBlock ms (vlax-3d-point (list 300.0 0.0 0.0)) "OCS_ATTBLOCK" 1.0 1.0 1.0 0.0))
  (c:YJST)
  (OCS:log (strcat "T09 实例属性值=" (vla-get-TextString (vla-Item ins 0))))
  (OCS:log (strcat "T09 多行属性内容=" (vla-get-MTextAttributeContent (vla-Item ins 1))))
  (OCS:log "T09 属性标签/值保持检查：人工核对")
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t09.log")
  (princ)
)

;;; ----------------------------------------------------------------------
;;; T10 标注/公差/普通引线
;;; ----------------------------------------------------------------------
(defun c:OCS_T10 ( / ms d1 p1 p2 p3)
  (OCS:log "--- T10 标注、公差与普通引线 ---")
  (setq ms (vla-get-ModelSpace (vla-get-ActiveDocument (vlax-get-acad-object))))
  (setq d1 (vla-AddDimAligned ms (vlax-3d-point (list 400.0 0.0 0.0))
                                   (vlax-3d-point (list 460.0 0.0 0.0))
                                   (vlax-3d-point (list 400.0 20.0 0.0))))
  (vla-put-TextOverride d1 "T01值 <> mm")
  (c:YJST)
  (OCS:log (strcat "T10 标注覆盖读回=" (vla-get-TextOverride d1)))
  (OCS:log "T10 关联/占位符保持检查：人工核对 <> 是否仍求值")
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t10.log")
  (princ)
)

;;; ----------------------------------------------------------------------
;;; T11 多重引线
;;; ----------------------------------------------------------------------
(defun c:OCS_T11 ( / ms ml)
  (OCS:log "--- T11 多重引线 ---")
  (OCS:log "需要包含多重引线（文字型与块型）的样例图纸。")
  (OCS:log "状态：未执行（需样例 DWG）")
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t11.log")
  (princ)
)

;;; ----------------------------------------------------------------------
;;; T12/T13 表格
;;; ----------------------------------------------------------------------
(defun c:OCS_T12 ( / ms tbl)
  (OCS:log "--- T12 表格普通与合并单元格 ---")
  (setq ms (vla-get-ModelSpace (vla-get-ActiveDocument (vlax-get-acad-object))))
  (setq tbl (vla-AddTable ms (vlax-3d-point (list 0.0 200.0 0.0)) 3 2 300.0 40.0))
  (vla-SetTextString tbl 0 0 "T12 表头")
  (vla-SetTextString tbl 1 0 "行1列1")
  (vla-SetTextString tbl 1 1 "行1列2")
  (vla-SetTextString tbl 2 0 "行2列1")
  (c:YJST)
  (OCS:log (strcat "T12 单元格(0,0)读回=" (vla-GetTextString tbl 0 0 0)))
  (OCS:log (strcat "T12 单元格(1,0)读回=" (vla-GetTextString tbl 1 0 0)))
  (OCS:log (strcat "T12 行数=" (itoa (vla-get-Rows tbl)) " 列数=" (itoa (vla-get-Columns tbl))))
  (OCS:log "T12 合并关系/边框/行高列宽：人工核对（本用例未合并）")
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t12.log")
  (princ)
)

(defun c:OCS_T13 ( / ms tbl)
  (OCS:log "--- T13 表格多内容项、字段与公式 ---")
  (setq ms (vla-get-ModelSpace (vla-get-ActiveDocument (vlax-get-acad-object))))
  (setq tbl (vla-AddTable ms (vlax-3d-point (list 400.0 200.0 0.0)) 3 3 300.0 40.0))
  (vla-SetTextString tbl 0 0 "T13 表头")
  (vla-SetTextString tbl 1 0 "公式 =1+2")
  (vla-SetTextString tbl 1 1 "%<\\AcVar \\$Area|\\f\"%pr1\",\"unitM\">%")
  (vla-SetTextString tbl 2 0 "普通文字内容")
  (c:YJST)
  (OCS:log (strcat "T13 公式单元读回=" (vla-GetTextString tbl 1 0 0)))
  (OCS:log (strcat "T13 字段单元读回=" (vla-GetTextString tbl 1 1 0)))
  (OCS:log "T13 数据链接：需链接样例（状态：未执行）")
  (OCS:log "T13 内容项枚举：读失败时不得当作遍历终点（实现层检查）")
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t13.log")
  (princ)
)

;;; ----------------------------------------------------------------------
;;; T14 字段
;;; ----------------------------------------------------------------------
(defun c:OCS_T14 ( / ms e)
  (OCS:log "--- T14 文字字段与嵌套字段 ---")
  (setq ms (vla-get-ModelSpace (vla-get-ActiveDocument (vlax-get-acad-object))))
  (setq e (vla-AddMText ms (vlax-3d-point (list 0.0 260.0 0.0)) 300.0
                        "字段 %<\\AcVar \\$Date|\\f\"yyyy-M-d\">% 保持"))
  (c:YJST)
  (OCS:log (strcat "T14 字段内容读回=" (vla-get-TextString e)))
  (OCS:log "T14 字段求值与关联：人工核对（更新字段后仍可求值）")
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t14.log")
  (princ)
)

;;; ----------------------------------------------------------------------
;;; T15 外部参照（需要源文件）
;;; ----------------------------------------------------------------------
(defun c:OCS_T15 ( / )
  (OCS:log "--- T15 外部参照 ---")
  (OCS:log "需要外部参照样例（fixtures/xref-source.dwg）。")
  (OCS:log "状态：未执行（本机暂无参照样例）")
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t15.log")
  (princ)
)

;;; ----------------------------------------------------------------------
;;; T16 竖排/镜像/Fit/Aligned
;;; ----------------------------------------------------------------------
(defun c:OCS_T16 ( / ms e)
  (OCS:log "--- T16 竖排、镜像、Fit 与 Aligned ---")
  (setq ms (vla-get-ModelSpace (vla-get-ActiveDocument (vlax-get-acad-object))))
  (setq e (vla-AddText ms "T16 竖排前" (vlax-3d-point (list 600.0 0.0 0.0)) 3.5))
  (vla-put-StyleName e "Standard")
  (c:YJST)
  (OCS:log (strcat "T16 字高=" (rtos (vla-get-Height e) 2 4)
                   " 旋转=" (rtos (vla-get-Rotation e) 2 4)
                   " 对齐=" (itoa (vla-get-Alignment e))))
  (OCS:log "T16 竖排样式标志与 Fit/Aligned 锚点：人工核对")
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t16.log")
  (princ)
)

;;; ----------------------------------------------------------------------
;;; T17 特殊符号与私用区字符
;;; ----------------------------------------------------------------------
(defun c:OCS_T17 ( / ms e raw after)
  (OCS:log "--- T17 特殊符号与私用区字符 ---")
  (setq ms (vla-get-ModelSpace (vla-get-ActiveDocument (vlax-get-acad-object))))
  (setq e (vla-AddMText ms (vlax-3d-point (list 600.0 40.0 0.0)) 300.0
                        (strcat "%%c12 %%d30 %%p0.5 U+E000 私用区 "
                                (chr 57344) " 结束")))
  (setq raw (OCS:getRaw e))
  (c:YJST)
  (setq after (OCS:getRaw e))
  (OCS:log (strcat "T17 前=" raw))
  (OCS:log (strcat "T17 后=" after))
  (if (= raw after)
    (OCS:log "T17 字符未被替换：通过（字形可用性需打印核对）")
    (OCS:log "T17 失败：字符内容变化")
  )
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t17.log")
  (princ)
)

;;; ----------------------------------------------------------------------
;;; T18 二次运行与空图纸
;;; ----------------------------------------------------------------------
(defun c:OCS_T18 ( / r1 r2)
  (OCS:log "--- T18 二次运行与空图纸 ---")
  ;; 第一次
  (OCS:mkStyle "OCST18" "txt.shx" "" 0.0 1.0 0.0)
  (OCS:mkText "T18 文字" "OCST18" 3.5 (list 800.0 0.0 0.0))
  (setq r1 (OCS:runYJSTCapturing))
  (setq r2 (OCS:runYJSTCapturing))
  (OCS:log (strcat "T18 第一次状态=" (OCS:fmt (OCS:assocd :status r1 nil))
                   " 修改样式=" (itoa (OCS:assocd :stylesModified r1 0))
                   " 字体段=" (itoa (OCS:assocd :fontRunsChanged r1 0))))
  (OCS:log (strcat "T18 第二次状态=" (OCS:fmt (OCS:assocd :status r2 nil))
                   " 修改样式=" (itoa (OCS:assocd :stylesModified r2 0))
                   " 字体段=" (itoa (OCS:assocd :fontRunsChanged r2 0))))
  (if (and (= 0 (OCS:assocd :stylesModified r2 0))
           (= 0 (OCS:assocd :fontRunsChanged r2 0)))
    (OCS:log "T18 结果：二次运行零有效修改，通过")
    (OCS:log "T18 结果：失败（二次运行仍有修改）")
  )
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t18.log")
  (princ)
)

(defun OCS:runYJSTCapturing ( / )
  (c:YJST)
  *OCS:LastReport*
)

;;; ----------------------------------------------------------------------
;;; T19 字体缺失与前置条件失败
;;; ----------------------------------------------------------------------
(defun c:OCS_T19 ( / )
  (OCS:log "--- T19 字体缺失与前置条件失败 ---")
  (OCS:log "步骤：临时把 *OCS:SimSunOverride* 设为不存在的文件名后执行 YJST，")
  (OCS:log "      确认业务数据未写入、原因明确、未使用其他字体替代。")
  (OCS:log "状态：未执行（需临时改动字体候选）")
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t19.log")
  (princ)
)

;;; ----------------------------------------------------------------------
;;; T20 一次撤销
;;; ----------------------------------------------------------------------
(defun c:OCS_T20 ( / r)
  (OCS:log "--- T20 一次撤销 ---")
  (OCS:mkStyle "OCST20" "txt.shx" "" 0.0 1.0 0.0)
  (OCS:mkText "T20 撤销检查" "OCST20" 3.5 (list 0.0 300.0 0.0))
  (setq before (OCS:styleFontInfo "OCST20"))
  (setq r (OCS:runYJSTCapturing))
  (setq after (OCS:styleFontInfo "OCST20"))
  (OCS:log (strcat "T20 执行后 fontFile=" (OCS:fmt (OCS:assocd :fontFile after ""))))
  ;; 一次 U
  (command "_.U")
  (setq undone (OCS:styleFontInfo "OCST20"))
  (OCS:log (strcat "T20 一次 U 后 fontFile=" (OCS:fmt (OCS:assocd :fontFile undone ""))
                   " bigFont=[" (OCS:fmt (OCS:assocd :bigFont undone "")) "]"))
  (if (equal (OCS:assocd :fontFile before "") (OCS:assocd :fontFile undone ""))
    (OCS:log "T20 结果：一次 U 恢复本次修改，通过（用户此前操作需人工确认未被撤销）")
    (OCS:log "T20 结果：失败")
  )
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t20.log")
  (princ)
)

;;; ----------------------------------------------------------------------
;;; T21 中途错误/Esc/恢复失败
;;; ----------------------------------------------------------------------
(defun c:OCS_T21 ( / r)
  (OCS:log "--- T21 中途错误与 Esc ---")
  (OCS:log "步骤1：设置故障注入点 content-write 后执行 YJST，确认回滚且临时状态恢复。")
  (setq *OCS:FaultPoint* "content-write")
  (setq r (OCS:runYJSTCapturing))
  (OCS:log (strcat "T21 故障注入状态=" (OCS:fmt (OCS:assocd :status r nil))
                   " 错误数=" (itoa (OCS:assocd :errors r 0))))
  (OCS:log "步骤2：Esc 中断需在交互式 AutoCAD 中人工测试。")
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t21.log")
  (princ)
)

;;; ----------------------------------------------------------------------
;;; T22 保存重开/动态状态/PDF（人工步骤）
;;; ----------------------------------------------------------------------
(defun c:OCS_T22 ( / )
  (OCS:log "--- T22 保存重开与 PDF ---")
  (OCS:log "步骤：YJST → QSAVE → 关闭重开 → 检查字体持久化、字段、动态块状态；")
  (OCS:log "      打印预览与导出 PDF 检查字形（不修改打印配置）。")
  (OCS:log "状态：未执行（需人工交互）")
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t22.log")
  (princ)
)

;;; ----------------------------------------------------------------------
;;; T23 专业实体与代理对象
;;; ----------------------------------------------------------------------
(defun c:OCS_T23 ( / )
  (OCS:log "--- T23 专业实体与代理对象 ---")
  (OCS:log "步骤：插入天正/代理对象 → YJST → 检查报告是否列为“未覆盖”。")
  (OCS:log "状态：未执行（本机暂无专业对象样例）")
  (OCS:dumpLog "C:\\Temp\\ocs\\ocs-t23.log")
  (princ)
)

(princ "\nocs-native-checks.lsp 已加载。")
(princ)
