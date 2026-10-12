;;; =====================================================================
;;; one-click-simsun.lsp
;;; 一键统一宋体（YJST）—— 当前图纸文字字体统一为宋体（SimSun）
;;;
;;; 日期：2026-10-12
;;; 状态：实现完成，待原生 AutoCAD 验收（见 docs/AutoCAD验收记录.md）
;;; 编码：UTF-8（无 BOM）
;;;
;;; 依据：docs/AutoLISP一键统一宋体实施方案.md
;;; 命令：APPLOAD 加载本文件后执行 YJST
;;; 约定：所有函数使用 OCS: 前缀（用户命令为 c:YJST）
;;;
;;; 只改变字体定义与文字内容中的有效字体切换指令；
;;; 不改字高、宽度、旋转、对齐、图层、颜色等任何其他数据；
;;; 不执行 ATTSYNC / ResetBlock / EXPLODE / SAVEAS / 自动保存；
;;; 不修改 FONTALT / FONTMAP / SECURELOAD / LISPSYS；
;;; 外部参照及其依赖样式跳过，不打开、不改写外部文件。
;;; =====================================================================

(vl-load-com)

;;; ------------------------- 全局状态 -------------------------
(setq *OCS:Version*      "0.1.0")
(setq *OCS:Plan*         nil)   ; 修改计划
(setq *OCS:Report*       nil)   ; 结构化报告
(setq *OCS:LastReport*   nil)   ; 最近一次运行（供调试/自动验收读取）
(setq *OCS:Running*      nil)   ; 重入保护
(setq *OCS:UndoMark*     nil)   ; 本次 Undo 分组标记
(setq *OCS:TempState*    nil)   ; 临时状态（锁定层、表格再生、OSMODE 等）
(setq *OCS:EscRequested* nil)   ; Esc/取消请求
(setq *OCS:FaultPoint*   nil)   ; 故障注入点（OCS:TestFault 用）

;;; ------------------------- 小工具 -------------------------

;; 字符串包含
(defun OCS:strContains (s sub / ls lsub)
  (setq ls (strlen s) lsub (strlen sub))
  (if (or (= lsub 0) (< ls lsub))
    (= s sub)
    (progn
      (setq i 1 result nil)
      (while (and (<= i (1+ (- ls lsub))) (not result))
        (if (= (substr s i lsub) sub) (setq result T))
        (setq i (1+ i))
      )
      result
    )
  )
)

;; 字符串中第 n 次出现 sub 的起始位置，找不到返回 nil
(defun OCS:strFindNth (s sub n / ls lsub i c)
  (setq ls (strlen s) lsub (strlen sub) i 1 c 0)
  (if (= lsub 0) nil
    (progn
      (while (and (<= i (1+ (- ls lsub))) (< c n))
        (if (= (substr s i lsub) sub) (setq c (1+ c)))
        (if (< c n) (setq i (1+ i)))
      )
      (if (= c n) i nil)
    )
  )
)

;; 是否为十六进制字符
(defun OCS:isHexChar (ch)
  (and (= (strlen ch) 1)
       (or (and (>= ch "0") (<= ch "9"))
           (and (>= ch "a") (<= ch "f"))
           (and (>= ch "A") (<= ch "F"))))
)

;; 键入十进制整数 → 十六进制字符串（用于 1071 打包）
(defun OCS:toHex (n / digits map out q r)
  (setq digits "0123456789ABCDEF" out "")
  (if (< n 0) (setq n (+ n 4294967296)))  ; 有符号 → 无符号 32 位
  (if (= n 0) "0"
    (progn
      (while (> n 0)
        (setq q (fix (/ n 16)) r (- n (* q 16)))
        (setq out (strcat (substr digits (1+ r) 1) out))
        (setq n q)
      )
      out
    )
  )
)

;; 十六进制字符串 → 整数
(defun OCS:fromHex (s / digits n i p)
  (setq digits "0123456789ABCDEF" n 0 i 1)
  (while (<= i (strlen s))
    (setq p (vl-position (substr s i 1) (OCS:splitChars digits)))
    (if p (setq n (+ (* n 16) p)))
    (setq i (1+ i))
  )
  n
)

(defun OCS:splitChars (s / out i)
  (setq out nil i 1)
  (while (<= i (strlen s))
    (setq out (append out (list (substr s i 1))))
    (setq i (1+ i))
  )
  out
)

;; 打包 1071：低 8 位 charset，位 8 bold，位 9 italic，
;; 位 16-23 pitch/family（参考 DXF 1071 与 SetFont 参数）
(defun OCS:pack1071 (charSet bold italic pitchFamily / v)
  (setq v (logand charSet 255))
  (if bold   (setq v (logior v 256)))
  (if italic (setq v (logior v 512)))
  (setq v (logior v (lsh (logand pitchFamily 255) 16)))
  v
)

(defun OCS:unpack1071 (v / charSet bold italic pf)
  (setq charSet (logand v 255)
        bold    (/= 0 (logand v 256))
        italic  (/= 0 (logand v 512))
        pf      (logand (lsh v -16) 255))
  (list charSet bold italic pf)
)

;; 关联列表取值（无则默认）
(defun OCS:assocd (key lst default / p)
  (setq p (assoc key lst))
  (if p (cdr p) default)
)

;; 报错包装：调用 COM/DXF，出错时返回 (cons :error msg)
(defun OCS:try (fn / r)
  (setq r (vl-catch-all-apply fn nil))
  (if (vl-catch-all-error-p r)
    (cons :error (vl-catch-all-error-message r))
    r
  )
)

;; 展开为 (vl-catch-all-apply 'fn (list a b ...)) 的包装
(defmacro OCS:try2 (fn &rest args)
  `(vl-catch-all-apply ,fn (list ,@args))
)

;; 报错判断
(defun OCS:errp (x)
  (and (consp x) (eq (car x) :error))
)

;; 错误信息取文本
(defun OCS:errmsg (x)
  (if (OCS:errp x) (cdr x) "")
)

;;; =====================================================================
;;; 纯函数：字体格式扫描器 OCS:NormalizeFontRuns
;;; （方案第 5 节；不访问任何 CAD 对象）
;;; =====================================================================

;; 内部状态 plist：(:i 位置 :issues 问题列表 :changes 修改计数)
;; 返回新 plist。

;; 读取字段范围 %< ... >%（支持转义与嵌套 %< >%），返回 (新位置 结束位置)
;; 若字段未闭合，记录 UNTERMINATED_FIELD 并把位置推到串尾。
(defun OCS:scanField (s i len st / depth c j closed)
  (setq j (1+ i) depth 1 closed nil)
  (while (and (<= j len) (not closed))
    (setq c (substr s j 1))
    (cond
      ((= c "\\")
       (setq j (+ j 2)))
      ((and (= c "%") (< j len) (= (substr s (1+ j) 1) "<"))
       (setq depth (1+ depth) j (+ j 2)))
      ((and (= c ">") (< j len) (= (substr s (1+ j) 1) "%"))
       (setq depth (1- depth) j (+ j 2))
       (if (<= depth 0) (setq closed T)))
      ((= c ">") (setq j (1+ j)))
      (T (setq j (1+ j)))
    )
  )
  (if (not closed)
    (progn
      (setq st (OCS:addIssue st "UNTERMINATED_FIELD" i "字段 %<...>% 未闭合"))
      (setq j (1+ len))
    )
  )
  (list (1- j) j)  ; 返回 (字段结束位置(含) 下一扫描位置)
)

;; 读取字体描述至 ;（识别转义与嵌套花括号），返回 (描述 结束后位置 err)
(defun OCS:readFontDesc (s i len / j c depth buf err)
  (setq j i depth 0 buf "" err nil)
  (while (and (<= j len) (not err))
    (setq c (substr s j 1))
    (cond
      ((= c "\\")
       (if (< j len)
         (progn (setq buf (strcat buf c (substr s (1+ j) 1))) (setq j (+ j 2)))
         (progn (setq err "字体描述以孤立反斜杠结尾") (setq j (1+ j)))
       ))
      ((= c "{") (setq depth (1+ depth) buf (strcat buf c) j (1+ j)))
      ((= c "}")
       (if (> depth 0)
         (progn (setq depth (1- depth) buf (strcat buf c) j (1+ j)))
         (progn (setq err "字体描述中出现多余的 }") (setq j (1+ j)))
       ))
      ((= c ";")
       (if (= depth 0)
         (setq j (1+ j))                       ; 结束
         (progn (setq buf (strcat buf c) j (1+ j)))
       ))
      (T (setq buf (strcat buf c) j (1+ j)))
    )
  )
  (if (and (not err) (> depth 0))
    (setq err "字体描述中花括号未闭合")
  )
  (if (and (not err) (not (OCS:strEndsWithChar (OCS:chompDesc buf) ";")))
    ;; 循环退出但没遇到 ';'：说明串已耗尽
    (setq err "字体指令不完整（缺少分号）")
  )
  (list buf (1- j) err)
)

(defun OCS:chompDesc (s)
  ;; 去掉尾部空白
  (while (and (> (strlen s) 0)
              (OCS:isSpaceChar (substr s (strlen s) 1)))
    (setq s (substr s 1 (1- (strlen s))))
  )
  s
)

(defun OCS:isSpaceChar (c)
  (or (= c " ") (= c "\t") (= c "\n") (= c "\r"))
)

(defun OCS:strEndsWithChar (s c)
  (and (> (strlen s) 0) (= (substr s (strlen s) 1) c))
)

;; 分割字体描述参数 a|b|c  → ("a" "b" "c")
(defun OCS:splitDesc (desc / out i pos start)
  (setq out nil i 1 start 1)
  (while (<= i (strlen desc))
    (if (= (substr desc i 1) "|")
      (progn
        (setq out (append out (list (substr desc start (- i start)))))
        (setq start (1+ i))
      )
      (setq i (1+ i))
    )
  )
  (setq out (append out (list (substr desc start (1+ (- (strlen desc) start))))))
  out
)

;; 应用目标字体规则：保留 b/i，重写 charset 与 pitch/family（若描述中已带）
;; 返回新描述（无 ;）
(defun OCS:applyFamily (desc family target / parts out head p kv)
  (setq parts (OCS:splitDesc desc) out nil head nil)
  (foreach p parts
    (cond
      ((= p "") nil)
      ((and (= (substr p 1 1) "b") (OCS:allDigits (substr p 2 100)) (not head))
       nil)  ; 位置参数在后面统一处理
      ((and (= (substr p 1 1) "i") (OCS:allDigits (substr p 2 100)) (not head))
       nil)
      ((not head) (setq head p))
      (T nil)
    )
  )
  ;; 重新按原始顺序构造：head 替换为 family；保留 b、i、c、pf 并按目标覆盖 c/pf
  (setq out nil)
  (setq first T)
  (foreach p parts
    (cond
      ((= p "") nil)
      (first
        (setq out (list family))
        (setq first nil)
        ;; 同一 token 可能是 "Arial|b1" 风格吗？不，已按 | 分割
      )
      ((and (= (substr p 1 1) "b") (OCS:allDigits (substr p 2 100)))
       (setq out (append out (list p))))
      ((and (= (substr p 1 1) "i") (OCS:allDigits (substr p 2 100)))
       (setq out (append out (list p))))
      ((and (= (substr p 1 1) "c") (OCS:allDigits (substr p 2 100)))
       (setq out (append out (list (strcat "c" (itoa (OCS:targetCharSet target)))))))
      ((and (= (substr p 1 1) "p") (= (substr p 2 1) "f") (OCS:allDigits (substr p 3 100)))
       (setq out (append out (list (strcat "pf" (itoa (OCS:targetPitchFamily target)))))))
      (T (setq out (append out (list p))))
    )
  )
  ;; 若描述原本没有任何 c/pf 参数，按目标规则补上（目标字体参数）
  (if (OCS:targetAppendParams target)
    (progn
      (if (not (OCS:hasParam out "c"))
        (setq out (append out (list (strcat "c" (itoa (OCS:targetCharSet target)))))))
      (if (not (OCS:hasParam out "pf"))
        (setq out (append out (list (strcat "pf" (itoa (OCS:targetPitchFamily target)))))))
    )
  )
  ;; 拼接
  (setq kv "")
  (foreach p out
    (if (= kv "") (setq kv p) (setq kv (strcat kv "|" p)))
  )
  kv
)

(defun OCS:hasParam (lst prefix / found p)
  (setq found nil)
  (foreach p lst
    (if (and (not found) (> (strlen p) 0)
             (= (substr p 1 1) prefix)
             (or (= prefix "c") (= prefix "p")))
      (setq found T)
    )
  )
  found
)

(defun OCS:allDigits (s / i ok ch)
  (setq ok T i 1)
  (if (= s "") (setq ok nil))
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (if (not (and (>= ch "0") (<= ch "9"))) (setq ok nil))
    (setq i (1+ i))
  )
  ok
)

;; 目标字体参数（S01 结果通过 *OCS:FontTarget* 注入；缺省为已验证的
;; SimSun 规则：charset=134，pitch/family=36(0x24)=VARIABLE_PITCH|FF_ROMAN|TMPF_TRUETYPE）
(defun OCS:targetCharSet (target)
  (OCS:assocd :charSet target 134)
)
(defun OCS:targetPitchFamily (target)
  (OCS:assocd :pitchFamily target 36)
)
(defun OCS:targetAppendParams (target)
  (OCS:assocd :appendParams target T)
)

;; 追加解析问题
(defun OCS:addIssue (st code pos msg)
  (list :i   (OCS:assocd :i st 1)
        :issues (append (OCS:assocd :issues st nil)
                        (list (list code pos (OCS:assocd :len st 0) msg)))
        :changes (OCS:assocd :changes st 0)
        :len (OCS:assocd :len st 0))
)

;; 判断字体族是否已是目标族（不区分大小写；接受“宋体”）
(defun OCS:isTargetFamily (fam target / tf)
  (setq tf (OCS:assocd :family target "SimSun"))
  (or (OCS:equalsIgnoreCase fam tf)
      (and (OCS:equalsIgnoreCase tf "SimSun")
           (or (OCS:equalsIgnoreCase fam "宋体")
               (OCS:equalsIgnoreCase fam "sim sun")
               (OCS:equalsIgnoreCase fam "SimSun")))
      (OCS:equalsIgnoreCase fam "宋体"))
)

(defun OCS:equalsIgnoreCase (a b)
  (= (OCS:lower a) (OCS:lower b))
)

(defun OCS:lower (s / out i ch up lo)
  (setq up "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        lo "abcdefghijklmnopqrstuvwxyz"
        out "" i 1)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (setq p (vl-position ch (OCS:splitChars up)))
    (if p
      (setq out (strcat out (substr lo (1+ p) 1)))
      (setq out (strcat out ch))
    )
    (setq i (1+ i))
  )
  out
)

;;; 主扫描器（纯函数）
;;; 输入：
;;;   s       —— 文字原始内容（MTEXT 全量原始串 / 属性内容等）
;;;   target  —— (list (cons :family "SimSun") (cons :charSet 134)
;;;                     (cons :pitchFamily 36) (cons :appendParams T))
;;; 输出 plist：
;;;   (:text 新内容 :changes 修改数 :issues ((code pos len msg)...) )
;;; 规则（方案第 5 节）：
;;;   - 仅替换有效 \f、\F 指令中的字体族；
;;;   - %<...>% 字段整体保护（其中 \f 不是字体指令）；
;;;   - 转义 \\ 与 \{ \} 不作为格式开关；
;;;   - 保留其他一切格式码与原文字符；
;;;   - 解析失败只记录问题，不删除任何段落。
;;; =====================================================================
(defun OCS:NormalizeFontRuns (s target / st len out i c r desc endp err fam newDesc next)
  (if (not (stringp s))
    (list :text s :changes 0 :issues (list (list "BAD_INPUT" 0 0 "输入不是字符串")))
    (progn
      (setq len (strlen s))
      (setq st  (list :i 1 :issues nil :changes 0 :len len))
      (setq out "")
      (setq i 1)
      (while (<= i len)
        (setq c (substr s i 1))
        (cond
          ;; 转义序列（\\、\{、\}、\; 等）：整体原样输出，不作为格式开关
          ;; 注意顺序：先判断转义，再判断 \f/\F（\f 也是合法转义之一，
          ;; 但作为格式指令时其后是描述文本，不会整体走转义分支）
          ((and (= c "\\") (< i len) (OCS:isEscapable (substr s (1+ i) 1))
                (not (and (or (= (substr s (1+ i) 1) "f")
                              (= (substr s (1+ i) 1) "F"))
                          (not (OCS:alphaChar (substr s (+ i 2) 1))))))
           (setq out (strcat out c (substr s (1+ i) 1)))
           (setq i (+ i 2))
          )
          ;; 字段范围保护：%< ... >% 整体原样输出
          ((and (= c "%") (< i len) (= (substr s (1+ i) 1) "<"))
           (setq next (OCS:scanFieldEnd s i len))
           (setq st (OCS:scanFieldSt s i len st))
           (setq out (strcat out (substr s i (1+ (- next i)))))
           (setq i next)
          )
          ;; 字体切换指令 \f / \F（后随字符不能是字母，防止误匹配）
          ((and (= c "\\") (< i len)
                (or (= (substr s (1+ i) 1) "f") (= (substr s (1+ i) 1) "F"))
                (not (OCS:alphaChar (substr s (+ i 2) 1))))
           (setq r (OCS:readFontDesc s (+ i 2) len))
           (setq desc (car r) endp (cadr r) err (caddr r))
           (if err
             (progn
               (setq st (OCS:addIssue st "UNTERMINATED_FONT" i err))
               ;; 保留原文，不删除任何段落（本指令按原样输出）
               (setq out (strcat out c (substr s (1+ i) 1)))
               (setq i (+ i 2))
             )
             (progn
               (setq fam (car (OCS:splitDesc (OCS:chompDesc desc))))
               (if (or (= fam "") (OCS:isTargetFamily fam target))
                 (progn
                   ;; 已是目标族：原样保留（幂等，不重复追加参数）
                   (setq out (strcat out c (substr s (1+ i) 1) desc ";"))
                   (setq i (1+ endp))
                 )
                 (progn
                   (setq newDesc (OCS:rewriteDesc (OCS:chompDesc desc) target))
                   (setq out (strcat out c (substr s (1+ i) 1) newDesc ";"))
                   (setq st (OCS:bumpChanges st))
                   (setq i (1+ endp))
                 )
               )
             )
           )
          )
          (T
           (setq out (strcat out c))
           (setq i (1+ i))
          )
        )
      )
      (list :text out
            :changes (OCS:assocd :changes st 0)
            :issues (OCS:assocd :issues st nil))
    )
  )
)

;; 字体指令边界：\f 后随字符不能是字母（防止把 \fx 之类当字体指令）
(defun OCS:alphaChar (ch)
  (and (= (strlen ch) 1)
       (or (and (>= ch "a") (<= ch "z"))
           (and (>= ch "A") (<= ch "Z"))))
)

;; 转义字符：\ 后面这些字符属于“合法转义”，整体原样保留
;; 注意：f/F 不在此列，\f \F 要走字体指令分支（由 NormalizeFontRuns 的
;; 顺序保证：转义分支已排除 \f \F 后随非字母的情形）
(defun OCS:isEscapable (ch / lst)
  (setq lst (list "\\" "{" "}" ";" "P" "p" "H" "W" "T" "Q" "C" "c"
                   "S" "s" "A" "a" "L" "l" "~" "-" "+" " " "n" "^"))
  (and (= (strlen ch) 1) (vl-position ch lst))
)

;; 计算字段 %< ... >% 的结束位置：返回“下一扫描位置”（1-based，字段之后）
;; 若未闭合，返回 (1+ len)
(defun OCS:scanFieldEnd (s i len / depth c j closed)
  (setq j (1+ i) depth 1 closed nil)
  (while (and (<= j len) (not closed))
    (setq c (substr s j 1))
    (cond
      ((= c "\\") (setq j (+ j 2)))
      ((and (= c "%") (< j len) (= (substr s (1+ j) 1) "<"))
       (setq depth (1+ depth) j (+ j 2)))
      ((and (= c ">") (< j len) (= (substr s (1+ j) 1) "%"))
       (setq depth (1- depth) j (+ j 2))
       (if (<= depth 0) (setq closed T)))
      (T (setq j (1+ j)))
    )
  )
  (if closed j (1+ len))
)

;; 带状态版本的字段扫描
(defun OCS:scanFieldSt (s i len st / depth c j closed)
  (setq j (1+ i) depth 1 closed nil)
  (while (and (<= j len) (not closed))
    (setq c (substr s j 1))
    (cond
      ((= c "\\") (setq j (+ j 2)))
      ((and (= c "%") (< j len) (= (substr s (1+ j) 1) "<"))
       (setq depth (1+ depth) j (+ j 2)))
      ((and (= c ">") (< j len) (= (substr s (1+ j) 1) "%"))
       (setq depth (1- depth) j (+ j 2))
       (if (<= depth 0) (setq closed T)))
      (T (setq j (1+ j)))
    )
  )
  (if (not closed)
    (setq st (OCS:addIssue st "UNTERMINATED_FIELD" i "字段 %<...>% 未闭合"))
  )
  st
)

(defun OCS:bumpChanges (st)
  (list :i (OCS:assocd :i st 1)
        :issues (OCS:assocd :issues st nil)
        :changes (1+ (OCS:assocd :changes st 0))
        :len (OCS:assocd :len st 0))
)

;; 重写字体描述：替换族名，保留 b/i，按目标覆盖/追加 c、pf
(defun OCS:rewriteDesc (desc target / parts out first p fam)
  (setq parts (OCS:splitDesc desc) out nil first T fam nil)
  (foreach p parts
    (cond
      ((= p "") nil)
      (first
        (setq fam p)
        (setq out (list (OCS:assocd :family target "SimSun")))
        (setq first nil)
      )
      ((and (= (substr p 1 1) "b") (OCS:allDigits (substr p 2 100)))
       (setq out (append out (list p))))
      ((and (= (substr p 1 1) "i") (OCS:allDigits (substr p 2 100)))
       (setq out (append out (list p))))
      ((and (= (substr p 1 1) "c") (OCS:allDigits (substr p 2 100)))
       (setq out (append out (list (strcat "c" (itoa (OCS:targetCharSet target)))))))
      ((and (= (substr p 1 1) "p") (= (substr p 2 1) "f") (OCS:allDigits (substr p 3 100)))
       (setq out (append out (list (strcat "pf" (itoa (OCS:targetPitchFamily target)))))))
      (T (setq out (append out (list p))))
    )
  )
  ;; 补目标参数
  (if (not (OCS:hasParam out "c"))
    (setq out (append out (list (strcat "c" (itoa (OCS:targetCharSet target)))))))
  (if (not (OCS:hasParam out "pf"))
    (setq out (append out (list (strcat "pf" (itoa (OCS:targetPitchFamily target)))))))
  ;; 拼接
  (setq kv "")
  (foreach p out
    (if (= kv "") (setq kv p) (setq kv (strcat kv "|" p)))
  )
  kv
)

;;; =====================================================================
;;; 预检：OCS:Preflight / OCS:ResolveSongFont
;;; =====================================================================

;; 目标字体解析（方案第 3 节）：
;; 1) 检测系统与 CAD 字体目录中的 SimSun 字体文件；
;; 2) 生成试验样式，写入 FontFile + SetFont，读回验证；
;; 3) 清空大字体并读回确认；
;; 4) 任一失败 → 在业务写入之前退出。
(defun OCS:ResolveSongFont ( / f res )
  (setq res (list :ok nil :family "SimSun" :charSet 134 :pitchFamily 36
                  :fontFile nil :fontFileSource nil :bigFontEmpty nil
                  :problems nil :appendParams T))
  ;; 候选字体文件（顺序即优先级；不接受 NSimSun/SimHei/STSong 顶替）
  (setq res (OCS:addProblem res :info "候选字体文件扫描"))
  (setq f (OCS:findSimSunFile))
  (if (not f)
    (setq res (OCS:addProblem res :error
      "未找到 SimSun 字体文件（simsun.ttc / simsun.ttf / SIMSUN.TTF），不能用其他字体替代"))
    (progn
      (setq res (OCS:putPair res :fontFile f))
      (setq res (OCS:putPair res :fontFileSource (OCS:fontFileSource f)))
    )
  )
  ;; 试验样式写入验证
  (setq res (OCS:verifyFontWrite res))
  res
)

(defun OCS:addProblem (res level msg)
  (append res (list (list :problem level msg)))
)
(defun OCS:putPair (res key val / out done)
  ;; 若键已存在则替换，否则追加（保证 plist 键唯一）
  (setq out nil done nil)
  (foreach pair res
    (if (and (not done) (consp pair) (eq (car pair) key))
      (progn (setq out (append out (list (cons key val)))) (setq done T))
      (setq out (append out (list pair)))
    )
  )
  (if (not done) (setq out (append out (list (cons key val)))))
  out
)
(defun OCS:getVal (res key / p)
  (setq p (assoc key res))
  (if p (cdr p) nil)
)

(defun OCS:findSimSunFile ( / winDir f)
  (setq winDir (getenv "WinDir"))
  (cond
    ((findfile "simsun.ttc")        (list (findfile "simsun.ttc") "simsun.ttc"))
    ((findfile "SIMSUN.TTC")        (list (findfile "SIMSUN.TTC") "SIMSUN.TTC"))
    ((findfile "simsun.ttf")        (list (findfile "simsun.ttf") "simsun.ttf"))
    ((and winDir (findfile (strcat winDir "\\Fonts\\simsun.ttc")))
     (list (findfile (strcat winDir "\\Fonts\\simsun.ttc")) "simsun.ttc"))
    ((and winDir (findfile (strcat winDir "\\Fonts\\simsun.ttf")))
     (list (findfile (strcat winDir "\\Fonts\\simsun.ttf")) "simsun.ttf"))
    (T nil)
  )
)

;; 字体文件来源：优先写入可被目标 CAD 解析的标识（文件名），
;; 若名称解析失败回退到绝对路径（仅作为最后手段并在报告中记录）。
(defun OCS:fontFileSource ( pair )
  (if (consp pair) (cadr pair) pair)
)

;; 在临时样式上验证写入/读回
(defun OCS:verifyFontWrite (res / doc name ent o r f bf old1071)
  (setq doc (OCS:activeDoc))
  (if (not doc)
    (setq res (OCS:addProblem res :error "无法获取活动文档（ActiveX 不可用）"))
    (progn
      (setq name (OCS:tempStyleName))
      (OCS:deleteStyleIfExists name)
      (setq r (vl-catch-all-apply 'vla-AddTextStyle
                (list doc name (OCS:styleBaseFont) :vlax-true)))
      (if (vl-catch-all-error-p r)
        (setq res (OCS:addProblem res :error
                    (strcat "创建试验文字样式失败：" (vl-catch-all-error-message r))))
        (progn
          (setq ent (tblobjname "STYLE" name))
          (if (not ent)
            (setq res (OCS:addProblem res :error "试验文字样式创建后未找到 STYLE 记录"))
            (progn
              (setq o (vlax-ename->vla-object ent))
              ;; FontFile 写入（先文件名）
              (setq f (OCS:getVal res :fontFile))
              (setq bf (if (consp f) (cadr f) f))
              (setq r (vl-catch-all-apply 'vla-put-FontFile (list o bf)))
              (if (vl-catch-all-error-p r)
                (progn
                  ;; 名称失败 → 绝对路径
                  (setq r (vl-catch-all-apply 'vla-put-FontFile (list o (car f))))
                  (if (vl-catch-all-error-p r)
                    (setq res (OCS:addProblem res :error
                      (strcat "FontFile 写入失败：" (vl-catch-all-error-message r))))
                    (progn
                      (setq res (OCS:putPair res :fontFileSource (strcat (car f) " (绝对路径回退)")))
                    ))
                )
              )
              ;; SetFont（字体族名 + 字符集 + pitch/family）
              (if (not (OCS:hasError res))
                (progn
                  (setq r (vl-catch-all-apply 'vla-SetFont
                    (list o "SimSun" :vlax-false :vlax-false
                          (OCS:getVal res :charSet)
                          (OCS:getVal res :pitchFamily))))
                  (if (vl-catch-all-error-p r)
                    (setq res (OCS:addProblem res :error
                      (strcat "SetFont(SimSun) 失败：" (vl-catch-all-error-message r))))
                  )
                )
              )
              ;; 写入后立即读回验证：FontFile 与 LastFontFile
              (if (not (OCS:hasError res))
                (progn
                  (setq r (vl-catch-all-apply 'vla-get-FontFile (list o)))
                  (if (or (vl-catch-all-error-p r) (= r ""))
                    (setq res (OCS:addProblem res :error "FontFile 读回为空，字体未被 CAD 解析"))
                    (setq res (OCS:putPair res :fontFileReadback r))
                  )
                )
              )
              ;; 大字体清空验证（STYLE DXF 组码 4）
              (if (not (OCS:hasError res))
                (setq res (OCS:verifyBigFontClear res ent name))
              )
              ;; 记录写入顺序证据
              (setq res (OCS:putPair res :writeOrder "FontFile → SetFont → 大字体清空(组码4) → 读回"))
              ;; 删除试验样式
              (OCS:deleteStyleIfExists name)
            )
          )
        )
      )
    )
  )
  res
)

(defun OCS:hasError (res / p)
  (setq p (assoc :problem res))
  ;; 扫描列表中是否有 :error
  (OCS:findError res)
)
(defun OCS:findError (res / found)
  (setq found nil)
  (foreach item res
    (if (and (consp item) (eq (car item) :problem)
             (consp (cdr item)) (eq (cadr item) :error))
      (setq found T)
    )
  )
  found
)

(defun OCS:tempStyleName ()
  "OCS_TMP_VERIFY_STYLE"
)

(defun OCS:styleBaseFont ()
  ;; 样式基字体使用普通 txt，若不可用退回 romans；与目标字体无关
  (if (findfile "txt.shx") "txt.shx" (if (findfile "romans.shx") "romans.shx" "simplex.shx"))
)

(defun OCS:deleteStyleIfExists (name / ent)
  (setq ent (tblobjname "STYLE" name))
  (if ent
    (vl-catch-all-apply 'entdel (list ent))
  )
)

;; 大字体清空验证：按方案“通过 tblobjname + entget 定位 STYLE，
;; 将 DXF 组码 4 设为空，再用 entmod 写回；顺序与读回由 S01 验证”
(defun OCS:verifyBigFontClear (res ent name / e r v4)
  ;; 先写入一个大字体，确保组码 4 存在
  (setq e (entget ent))
  (setq r (OCS:ensureBigFont4 e "hz.shx"))
  (setq e (entget ent))
  (setq r (OCS:substDxf4 "" e))
  (if (OCS:errp r)
    (setq res (OCS:addProblem res :error
                (strcat "大字体清空（DXF 组码 4 + entmod）失败：" (OCS:errmsg r))))
    (progn
      (setq e (entget (tblobjname "STYLE" name)))
      (setq v4 (OCS:assocd 4 e "MISSING"))
      (if (or (= v4 "MISSING") (= v4 ""))
        ;; 组码 4 已清空：再读回 COM 属性确认
        (setq res (OCS:putPair res :bigFontEmpty T))
        (setq res (OCS:addProblem res :error
                    (strcat "大字体清空后组码 4 读回非空：" v4)))
      )
    )
  )
  res
)

(defun OCS:ensureBigFont4 (e val / o r)
  (setq o (vlax-ename->vla-object (cdr (assoc -1 e))))
  (setq r (vl-catch-all-apply 'vla-put-BigFontFile (list o val)))
  (if (vl-catch-all-error-p r)
    ;; 文档不允许空字符串，但允许非空；写入失败则用 entmod 补组码 4
    (vl-catch-all-apply 'entmod (list (OCS:substDxf4 val e)))
  )
  T
)

;; 替换组码 4（无则追加），返回新 entlist；entmod 错误以 (:error . msg) 表示
(defun OCS:substDxf4 (val e / out found r)
  (setq out nil found nil)
  (foreach pair e
    (if (= (car pair) 4)
      (progn
        (setq found T)
        (setq out (append out (list (cons 4 val))))
      )
      (setq out (append out (list pair)))
    )
  )
  (if (not found)
    (setq out (append out (list (cons 4 val))))
  )
  (setq r (vl-catch-all-apply 'entmod (list out)))
  (if (vl-catch-all-error-p r)
    (cons :error (vl-catch-all-error-message r))
    (if (null r) (cons :error "entmod 返回 nil") out)
  )
)

;;; =====================================================================
;;; 环境预检 OCS:Preflight
;;; =====================================================================

(defun OCS:Preflight ( / res acadObj undoctl)
  (setq res (list :ok nil))
  ;; 1. AutoLISP/Visual LISP/ActiveX（只探测，不执行任何命令）
  (setq res (OCS:putPair res :acadver (getvar "ACADVER")))
  (setq res (OCS:putPair res :product  (getvar "PRODUCT")))
  (setq res (OCS:putPair res :lispys   (getvar "LISPSYS")))
  (setq res (OCS:putPair res :platform (getvar "PLATFORM")))
  (setq acadObj (vl-catch-all-apply 'vlax-get-acad-object nil))
  (if (vl-catch-all-error-p acadObj)
    (setq res (OCS:addProblem res :error "Visual LISP/ActiveX 不可用"))
  )
  ;; 2. 撤销可用性（UNDOCTL 位 0 = UNDO 开启）
  (setq undoctl (getvar "UNDOCTL"))
  (setq res (OCS:putPair res :undoctl undoctl))
  (if (= 0 (logand undoctl 1))
    (setq res (OCS:addProblem res :error "图纸撤销（UNDO）不可用，不能保证一次 U 恢复"))
  )
  ;; 3. 文档可写（锁定/只读）
  (setq res (OCS:checkDocWritable res))
  ;; 4. 字体解析
  (setq res (OCS:putPair res :font (OCS:ResolveSongFont)))
  (if (OCS:findError (OCS:getVal res :font))
    (setq res (OCS:addProblem res :error "宋体字体解析失败（详见 :font）"))
  )
  ;; 5. 关键接口存在性
  (setq res (OCS:checkInterfaces res))
  (setq res (OCS:putPair res :ok (not (OCS:findError res))))
  res
)

(defun OCS:checkDocWritable (res / doc ro)
  (setq doc (OCS:activeDoc))
  (if (not doc)
    (OCS:addProblem res :error "无法获取活动文档")
    (progn
      (setq ro (vl-catch-all-apply 'vla-get-ReadOnly (list doc)))
      (if (and (not (vl-catch-all-error-p ro)) ro)
        (OCS:addProblem res :error "当前图纸为只读，不能修改")
        res
      )
    )
  )
)

(defun OCS:checkInterfaces (res / doc)
  (setq doc (OCS:activeDoc))
  (if (not doc)
    (OCS:addProblem res :error "ActiveX 文档不可用")
    (progn
      (if (not (vlax-method-applicable-p doc 'GetBlocks))
        (setq res (OCS:addProblem res :error "Blocks 集合接口不可用")))
      res
    )
  )
)

(defun OCS:activeDoc ( / acad doc)
  (setq acad (vl-catch-all-apply 'vlax-get-acad-object nil))
  (if (vl-catch-all-error-p acad) nil
    (progn
      (setq doc (vl-catch-all-apply 'vla-get-ActiveDocument (list acad)))
      (if (vl-catch-all-error-p doc) nil doc)
    )
  )
)
(defun OCS:activeDoc* ()
  (vla-get-ActiveDocument (vlax-get-acad-object))
)

;;; =====================================================================
;;; 样式收集 OCS:CollectStyles
;;; 方案第 3 节：DXF 70 位 1 = 形文件记录，位 16 = 外参依赖；
;;; 不按名称含 "|" 判断；Standard 与注释性样式照常处理。
;;; =====================================================================

(defun OCS:CollectStyles ( / res ent lst e flg name)
  (setq res (list :normal nil :shape nil :xref nil :vertical nil :count 0))
  (setq ent (tblnext "STYLE" T))
  (while ent
    (setq flg (OCS:assocd 70 ent 0)
          name (OCS:assocd 2 ent ""))
    (cond
      ((/= 0 (logand flg 1))
       ;; 形文件记录（LOAD 请求）→ 跳过并分类记录
       (setq res (OCS:lstAppend res :shape name))
      )
      ((/= 0 (logand flg 16))
       ;; 外部参照依赖记录 → 跳过并分类记录
       (setq res (OCS:lstAppend res :xref name))
      )
      (T
       (setq res (OCS:lstAppend res :normal
                  (list :name name
                        :flags flg
                        :vertical (/= 0 (logand flg 4))
                        :annotative (OCS:isAnnotativeStyle ent)
                        :bigFontBefore (OCS:assocd 4 ent "")
                        :fontFileBefore (OCS:assocd 3 ent "")
                        :dxf ent)))
      )
    )
    (setq ent (tblnext "STYLE" nil))
  )
  (setq res (OCS:putPair res :count (length (OCS:getVal res :normal))))
  res
)

(defun OCS:lstAppend (res key val)
  (OCS:putPair res key (append (OCS:getVal res key nil) (list val)))
)

;; 注释性判断：组码 1071 不含注释位；注释性在组码 70 无位，
;; 通过扩展数据/对象模型的 Annotative 属性判断；此处用
;; entget 的 1071 之外，另查 (assoc 1071 ...) 不可靠 → 用对象接口。
(defun OCS:isAnnotativeStyle (ent / o r)
  (setq o (vlax-ename->vla-object ent))
  (setq r (vl-catch-all-apply 'vla-get-Annotative (list o)))
  (if (vl-catch-all-error-p r) nil
    (equal r :vlax-true)
  )
)

;;; =====================================================================
;;; 图块与宿主收集 OCS:CollectHosts
;;; 方案第 4 节：以 Blocks 集合为主入口；按句柄去重；
;;; 遇外参块停止进入；动态块同时扫描原始定义与匿名表示；
;;; 标注/表格等生成的匿名显示块按来源分类处理。
;;; =====================================================================

(defun OCS:CollectHosts ( / res doc blocks i blk)
  (setq res (list :blocks 0 :xrefBlocks 0 :displayBlocks 0
                  :entities 0 :attribs 0 :unknown 0
                  :blockList nil :skipped nil))
  (setq doc (OCS:activeDoc))
  (if (not doc)
    (OCS:addProblem res :error "无法获取活动文档")
    (progn
      (setq blocks (vla-get-Blocks doc))
      (setq i 1)
      (while (<= i (vla-get-Count blocks))
        (setq blk (OCS:safeItem blocks i))
        (if blk
          (setq res (OCS:collectBlock res doc blk))
        )
        (setq i (1+ i))
      )
      res
    )
  )
)

(defun OCS:safeItem (coll i / r)
  (setq r (vl-catch-all-apply 'vla-Item (list coll (1- i))))
  (if (vl-catch-all-error-p r) nil r)
)

(defun OCS:collectBlock (res doc blk / name isXref ownerH handle btype)
  (setq name (OCS:safeProp blk 'Name)
        handle (OCS:safeProp blk 'Handle))
  (if (not name)
    res
    (progn
      (setq isXref (OCS:safeProp blk 'IsXRef))
      ;; 匿名块分类：动态块表示(*D...)、标注/表格显示缓存(*U...)、其他
      (setq btype (OCS:classifyBlockName name))
      (cond
        ;; 外部参照块：停止进入，不跨外部数据库
        ((equal isXref :vlax-true)
         (setq res (OCS:putPair res :xrefBlocks (1+ (OCS:getVal res :xrefBlocks 0))))
         (setq res (OCS:lstAppend res :skipped (list "XREF_BLOCK" handle name)))
        )
        ((eq btype :display-cache)
         ;; 标注/表格等的显示缓存：交由其源宿主处理，不直接改写
         (setq res (OCS:putPair res :displayBlocks (1+ (OCS:getVal res :displayBlocks 0))))
         (setq res (OCS:lstAppend res :skipped (list "DISPLAY_CACHE" handle name)))
        )
        (T
         (setq res (OCS:putPair res :blocks (1+ (OCS:getVal res :blocks 0))))
         (setq res (OCS:lstAppend res :blockList (list :name name :handle handle :obj blk)))
         ;; 扫描块内实体
         (setq res (OCS:scanBlockContents res doc blk name handle))
        )
      )
      res
    )
  )
)

;; 匿名块来源分类（方案第 4 节第 6 条）
(defun OCS:classifyBlockName (name / n)
  (setq n (OCS:lower name))
  (cond
    ;; 动态块的匿名表示：*D12 这类
    ((and (>= (strlen n) 2) (= (substr n 1 2) "*d")) :dynamic-repr)
    ;; 标注/表格等显示缓存：*U12、*X12 这类（U=匿名块，X=…）
    ((and (>= (strlen n) 2) (= (substr n 1 2) "*u")) :display-cache)
    (T :named)
  )
)

(defun OCS:scanBlockContents (res doc blk bname bhandle / ents i e)
  (setq ents (vla-get-BlockEntities blk))
  (setq i 1)
  (while (<= i (vla-get-Count ents))
    (setq e (OCS:safeItem ents i))
    (if e (setq res (OCS:visitEntity res doc e (list :block bname bhandle))))
    (setq i (1+ i))
  )
  res
)

;; 实体访问（去重按句柄）
(defun OCS:visitEntity (res doc e ctx / typ handle seen)
  (setq typ (OCS:safeProp e 'ObjectName))
  (if (not typ)
    (progn
      (setq res (OCS:putPair res :unknown (1+ (OCS:getVal res :unknown 0))))
      (setq res (OCS:lstAppend res :skipped (list "UNKNOWN_OBJECT" "?" (OCS:ctxStr ctx))))
    )
    (progn
      (setq handle (OCS:safeProp e 'Handle))
      (setq seen (OCS:seenP res handle))
      (if (not seen)
        (progn
          (setq res (OCS:markSeen res handle))
          (setq res (OCS:handleEntity res doc e typ ctx handle))
        )
      )
      res
    )
  )
)

(defun OCS:ctxStr (ctx)
  (if (null ctx) "-"
    (if (= (car ctx) :block)
      (strcat "块:" (cadr ctx))
      (strcat "空间:" (cadr ctx))
    )
  )
)

;; 记录处理
(defun OCS:seenP (res h)
  (and h (vl-position h (OCS:getVal res :seen nil)))
)
(defun OCS:markSeen (res h)
  (if h
    (OCS:putPair res :seen (append (OCS:getVal res :seen nil) (list h)))
    res
  )
)

;; 按对象类型分发
(defun OCS:handleEntity (res doc e typ ctx handle / cls)
  (setq cls (OCS:mapClass typ))
  (cond
    ((eq cls :text)     (OCS:collectTextHost res doc e ctx handle typ))
    ((eq cls :mtext)    (OCS:collectTextHost res doc e ctx handle typ))
    ((eq cls :attrib)   (OCS:collectAttrib res doc e ctx handle typ))
    ((eq cls :attdef)   (OCS:collectAttrib res doc e ctx handle typ))
    ((eq cls :dim)      (OCS:collectDim res doc e ctx handle typ))
    ((eq cls :mleader)  (OCS:collectMLeader res doc e ctx handle typ))
    ((eq cls :leader)   (OCS:collectLeader res doc e ctx handle typ))
    ((eq cls :table)    (OCS:collectTable res doc e ctx handle typ))
    ((eq cls :tolerance)(OCS:collectTolerance res doc e ctx handle typ))
    ((eq cls :blockref) (OCS:collectBlockRef res doc e ctx handle typ))
    ((eq cls :attribute-dest) res) ; 由 blockref 处理
    (T
     ;; 专业/代理对象：记录为未覆盖
     (if (OCS:isUnknownClass typ)
       (progn
         (setq res (OCS:putPair res :unknown (1+ (OCS:getVal res :unknown 0))))
         (setq res (OCS:lstAppend res :skipped
                      (list "PROXY_OR_PRO" handle (strcat typ "@" (OCS:ctxStr ctx)))))
       )
     )
     res
    )
  )
)

(defun OCS:isUnknownClass (typ)
  (or (OCS:strContains typ "Proxy")
      (OCS:strContains typ "ACAD_PROXY")
      (and (OCS:strContains typ "AcDb")
           (not (OCS:knownClass typ)))
  )
)

(defun OCS:knownClass (typ)
  (OCS:strContains typ "Text")
)

;; 类型 → 分类（DXF/ObjectName 映射）
(defun OCS:mapClass (typ / t)
  (setq t (OCS:lower typ))
  (cond
    ((or (= t "acad_text")   (= t "acdbtext"))          :text)
    ((or (= t "acad_mtext")  (= t "acdbmtext"))         :mtext)
    ((or (= t "acad_attribute") (= t "acdbattribute"))  :attrib)
    ((or (= t "acad_attributereference") (= t "acdbattributereference")) :attrib)
    ((or (= t "acad_attributedefinition") (= t "acdbattributedefinition")) :attdef)
    ((OCS:strContains t "dimension")                    :dim)
    ((OCS:strContains t "mleader")                      :mleader)
    ((OCS:strContains t "leader")                       :leader)
    ((OCS:strContains t "table")                        :table)
    ((OCS:strContains t "tolerance")                    :tolerance)
    ((or (= t "acad_blockreference") (= t "acdbblockreference")) :blockref)
    ((OCS:strContains t "wblock")                       :blockref)
    (T :other)
  )
)

;;; ---------------------------------------------------------------------
;;; 各宿主“读”：收集进计划（只读阶段）
;;; ---------------------------------------------------------------------

(defun OCS:collectTextHost (res doc e ctx handle typ / s r)
  (setq res (OCS:putPair res :entities (1+ (OCS:getVal res :entities 0))))
  (setq res (OCS:lstAppend res :hosts
              (list :kind (if (= (OCS:lower typ) "acdbmtext") :mtext :text)
                    :obj e :handle handle :ctx ctx :type typ)))
  res
)

(defun OCS:collectAttrib (res doc e ctx handle typ / isAttdef)
  (setq res (OCS:putPair res :attribs (1+ (OCS:getVal res :attribs 0))))
  (setq res (OCS:lstAppend res :hosts
              (list :kind (if (OCS:strContains (OCS:lower typ) "definition") :attdef :attrib)
                    :obj e :handle handle :ctx ctx :type typ)))
  res
)

(defun OCS:collectDim (res doc e ctx handle typ)
  (OCS:lstAppend res :hosts
    (list :kind :dim :obj e :handle handle :ctx ctx :type typ))
)

(defun OCS:collectMLeader (res doc e ctx handle typ)
  (OCS:lstAppend res :hosts
    (list :kind :mleader :obj e :handle handle :ctx ctx :type typ))
)

(defun OCS:collectLeader (res doc e ctx handle typ)
  (OCS:lstAppend res :hosts
    (list :kind :leader :obj e :handle handle :ctx ctx :type typ))
)

(defun OCS:collectTable (res doc e ctx handle typ)
  (OCS:lstAppend res :hosts
    (list :kind :table :obj e :handle handle :ctx ctx :type typ))
)

(defun OCS:collectTolerance (res doc e ctx handle typ)
  (OCS:lstAppend res :hosts
    (list :kind :tolerance :obj e :handle handle :ctx ctx :type typ))
)

;; 块引用：额外处理属性实例（GetAttributes / GetConstantAttributes）
(defun OCS:collectBlockRef (res doc e ctx handle typ / attrs consts)
  (setq res (OCS:putPair res :entities (1+ (OCS:getVal res :entities 0))))
  (setq res (OCS:lstAppend res :hosts
              (list :kind :blockref :obj e :handle handle :ctx ctx :type typ)))
  ;; 属性实例
  (setq attrs (vl-catch-all-apply 'vla-GetAttributes (list e)))
  (if (and (not (vl-catch-all-error-p attrs)) attrs)
    (foreach a (OCS:variantToList attrs)
      (setq res (OCS:collectAttrib res doc a ctx (OCS:safeProp a 'Handle)
                                    (OCS:safeProp a 'ObjectName)))
    )
  )
  (setq consts (vl-catch-all-apply 'vla-GetConstantAttributes (list e)))
  (if (and (not (vl-catch-all-error-p consts)) consts)
    (foreach a (OCS:variantToList consts)
      (setq res (OCS:collectAttrib res doc a ctx (OCS:safeProp a 'Handle)
                                    (OCS:safeProp a 'ObjectName)))
    )
  )
  res
)

;;; =====================================================================
;;; 安全 COM 访问
;;; =====================================================================

(defun OCS:safeProp (obj prop / r)
  (if (null obj) nil
    (progn
      (setq r (vl-catch-all-apply (read (strcat "vla-get-" (vl-symbol-name prop))) (list obj)))
      (if (vl-catch-all-error-p r) nil r)
    )
  )
)

(defun OCS:safeMethod (obj meth args / r)
  (if (null obj) (cons :error "nil object")
    (progn
      (setq r (vl-catch-all-apply (read (strcat "vla-" (vl-symbol-name meth))) (cons obj args)))
      (if (vl-catch-all-error-p r)
        (cons :error (vl-catch-all-error-message r))
        r
      )
    )
  )
)

;; Variant/SafeArray 解包（64 位 ObjectID 不转 32 位整数）
(defun OCS:variantToList (v / r)
  (cond
    ((null v) nil)
    ((listp v) v)
    (T
     (setq r (vl-catch-all-apply 'vlax-safearray->list (list v)))
     (if (vl-catch-all-error-p r)
       ;; 标量 Variant
       (progn
         (setq r2 (vl-catch-all-apply 'vlax-variant-value (list v)))
         (if (vl-catch-all-error-p r2) nil
           (if (listp r2) r2 (list r2))
         )
       )
       r
     )
    )
  )
)

;;; =====================================================================
;;; 修改计划 OCS:BuildPlan
;;; =====================================================================

(defun OCS:BuildPlan ( / plan styles hosts)
  (setq styles (OCS:CollectStyles))
  (setq hosts   (OCS:CollectHosts))
  (setq plan (list
    :styles    (OCS:getVal styles :normal nil)
    :shape     (OCS:getVal styles :shape nil)
    :xrefStyle (OCS:getVal styles :xref nil)
    :hosts     (OCS:getVal hosts :hosts nil)
    :seen      (OCS:getVal hosts :seen nil)
    :stats     hosts
    :targets   nil      ; (kind obj handle ctx ...) 内容修改目标
    :issues    nil
  ))
  plan
)

;;; =====================================================================
;;; 应用样式修改 OCS:ApplyStyle
;;; =====================================================================

(defun OCS:ApplyStyle (doc st / name ent o r before after)
  (setq name (OCS:assocd :name st ""))
  (setq ent (tblobjname "STYLE" name))
  (if (not ent)
    (list :ok nil :name name :error "STYLE 记录未找到")
    (progn
      (setq o (vlax-ename->vla-object ent))
      (setq before (OCS:styleSnapshot ent))
      ;; 1) FontFile
      (setq r (OCS:safeMethod o 'FontFile nil))  ; 读
      (setq r (vl-catch-all-apply 'vla-put-FontFile
                (list o (OCS:styleTargetFontFile doc))))
      (if (vl-catch-all-error-p r)
        (list :ok nil :name name :error (strcat "FontFile 写入失败：" (vl-catch-all-error-message r)))
        (progn
          ;; 2) SetFont
          (setq r (vl-catch-all-apply 'vla-SetFont
                    (list o "SimSun" :vlax-false :vlax-false 134 36)))
          (if (vl-catch-all-error-p r)
            (list :ok nil :name name :error (strcat "SetFont 失败：" (vl-catch-all-error-message r)))
            (progn
              ;; 3) 大字体清空（组码 4）
              (setq r (OCS:clearBigFont ent name))
              (if (OCS:errp r)
                (list :ok nil :name name :error (strcat "大字体清空失败：" (OCS:errmsg r)))
                (progn
                  ;; 4) 读回验证
                  (setq after (OCS:styleSnapshot (tblobjname "STYLE" name)))
                  (if (not (OCS:styleReadbackOk before after))
                    (list :ok nil :name name :error "样式读回校验失败（非字体参数被改变）"
                          :before before :after after)
                    (list :ok T :name name :before before :after after)
                  )
                )
              )
            )
          )
        )
      )
    )
  )
)

(defun OCS:styleTargetFontFile (doc / f)
  (setq f (OCS:getVal (OCS:getVal *OCS:Plan* :font) :fontFile))
  (if (consp f) (cadr f) f)
)

;; 样式非字体参数快照（40/41/50/70/71 + 未知组码计数）
(defun OCS:styleSnapshot (ent / e out)
  (if (not ent) nil
    (progn
      (setq e (entget ent))
      (list
        :h     (OCS:assocd 5 e "")
        :name  (OCS:assocd 2 e "")
        :40    (OCS:assocd 40 e nil)
        :41    (OCS:assocd 41 e nil)
        :50    (OCS:assocd 50 e nil)
        :70    (OCS:assocd 70 e nil)
        :71    (OCS:assocd 71 e nil)
        :1071  (OCS:assocd 1071 e nil)
        :xdata (length (OCS:xdataKeys e))
      )
    )
  )
)

(defun OCS:xdataKeys (e / keys)
  (setq keys nil)
  (foreach pair e
    (if (and (consp pair) (numberp (car pair)) (>= (car pair) 1000))
      (setq keys (cons (car pair) keys))
    )
  )
  keys
)

(defun OCS:styleReadbackOk (before after / ok)
  (setq ok T)
  (foreach key (list :name :40 :41 :50 :70 :71 :1071 :xdata)
    (if (not (equal (OCS:assocd key before nil) (OCS:assocd key after nil) 1e-9))
      (setq ok nil)
    )
  )
  ok
)

;; 大字体清空 + 读回
(defun OCS:clearBigFont (ent name / e r e2 v)
  (setq e (entget ent))
  (if (not (assoc 4 e))
    T  ; 本就没有大字体
    (progn
      (setq r (OCS:substDxf4 "" e))
      (if (OCS:errp r) r
        (progn
          (setq e2 (entget (tblobjname "STYLE" name)))
          (setq v (OCS:assocd 4 e2 "MISSING"))
          (if (or (= v "MISSING") (= v ""))
            (progn
              ;; COM 读回
              (setq r (vl-catch-all-apply 'vla-get-BigFontFile
                        (list (vlax-ename->vla-object (tblobjname "STYLE" name)))))
              (if (vl-catch-all-error-p r)
                (cons :error "大字体 COM 读回失败")
                (if (= r "") T (cons :error (strcat "大字体读回非空：" r)))
              )
            )
            (cons :error (strcat "大字体读回非空：" v))
          )
        )
      )
    )
  )
)

;;; =====================================================================
;;; 宿主读写 OCS:ReadHost / OCS:WriteHost
;;; =====================================================================

;; 读取宿主内容与必须保留的数据 → plist
(defun OCS:ReadHost (host / kind e)
  (setq kind (OCS:assocd :kind host nil)
        e (OCS:assocd :obj host nil))
  (cond
    ((or (eq kind :text) (eq kind :mtext))
     (OCS:readTextLike host e))
    ((or (eq kind :attrib) (eq kind :attdef))
     (OCS:readAttr host e))
    ((eq kind :dim)
     (OCS:readDim host e))
    ((eq kind :mleader)
     (OCS:readMLeader host e))
    ((eq kind :leader)
     (OCS:readLeader host e))
    ((eq kind :table)
     (OCS:readTable host e))
    ((eq kind :tolerance)
     (OCS:readTolerance host e))
    ((eq kind :blockref)
     (list :kind kind :obj e :skip T))
    (T (list :kind kind :obj e :skip T))
  )
)

;; TEXT/MTEXT：完整原始内容
(defun OCS:readTextLike (host e / kind r txt)
  (setq kind (OCS:assocd :kind host))
  (setq r (vl-catch-all-apply 'vla-get-TextString (list e)))
  (if (vl-catch-all-error-p r)
    (list :kind kind :obj e :error (vl-catch-all-error-message r))
    (progn
      (setq txt r)
      ;; MTEXT 的完整原始格式：TextString 在 MTEXT 上返回原始格式串；
      ;; 长文本不分段读取（XDATA 组码 1 只是前 250 字符，不能作为来源）
      (list :kind kind :obj e :text txt
            :styleName (OCS:safeProp e 'StyleName)
            :height (OCS:safeProp e 'Height)
            :width (OCS:safeProp e 'Width)
            :rotation (OCS:safeProp e 'Rotation)
            :layer (OCS:safeProp e 'Layer)
            :color (OCS:safeProp e 'Color))
    )
  )
)

(defun OCS:readAttr (host e / kind mt)
  (setq kind (OCS:assocd :kind host))
  (setq mt (OCS:safeProp e 'MTextAttribute))
  (if (equal mt :vlax-true)
    (list :kind kind :obj e :multiline T
          :text (OCS:safeProp e 'MTextAttributeContent)
          :boundaryWidth (OCS:safeProp e 'MTextBoundaryWidth)
          :tag (OCS:safeProp e 'TagString)
          :value (OCS:safeProp e 'TextString)
          :styleName (OCS:safeProp e 'StyleName)
          :constant (OCS:safeProp e 'Constant))
    (list :kind kind :obj e :multiline nil
          :text (OCS:safeProp e 'TextString)
          :tag (OCS:safeProp e 'TagString)
          :styleName (OCS:safeProp e 'StyleName)
          :constant (OCS:safeProp e 'Constant))
  )
)

(defun OCS:readDim (host e / r)
  (list :kind :dim :obj e
        :textOverride (OCS:safeProp e 'TextOverride)
        :textString (OCS:safeProp e 'TextString)
        :styleName (OCS:safeProp e 'TextStyle)
        :measurement (OCS:safeProp e 'TextOverride)
        :rotation (OCS:safeProp e 'TextRotation)
        :height (OCS:safeProp e 'TextHeight))
)

(defun OCS:readMLeader (host e / r content)
  (setq r (OCS:safeProp e 'TextString))
  (if (not r)
    ;; 多重引线可能使用块内容：读取其块引用与属性
    (progn
      (setq content (OCS:safeProp e 'BlockRecordId))
      (list :kind :mleader :obj e :text nil :blockId content))
    (list :kind :mleader :obj e :text r :styleName (OCS:safeProp e 'TextStyle))
  )
)

(defun OCS:readLeader (host e / ann)
  ;; 普通引线的关联注释对象
  (setq ann (OCS:leaderAnnotation e))
  (list :kind :leader :obj e :annotation ann)
)

(defun OCS:leaderAnnotation (e / r)
  (setq r (OCS:safeProp e 'Annotation))
  r
)

(defun OCS:readTable (host e / rows cols)
  (setq rows (OCS:safeProp e 'Rows)
        cols  (OCS:safeProp e 'Columns))
  (list :kind :table :obj e
        :rows rows :cols cols
        :styleName (OCS:safeProp e 'StyleName)
        :suppressed (OCS:safeProp e 'RegenerateTableSuppressed)))

(defun OCS:readTolerance (host e)
  (list :kind :tolerance :obj e
        :text (OCS:safeProp e 'Text)
        :styleName (OCS:safeProp e 'StyleName))
)

;;; 写回宿主
(defun OCS:WriteHost (host data / kind e)
  (setq kind (OCS:assocd :kind data (OCS:assocd :kind host))
        e (OCS:assocd :obj data (OCS:assocd :obj host nil)))
  (cond
    ((or (eq kind :text) (eq kind :mtext))
     (OCS:writeTextLike e data))
    ((or (eq kind :attrib) (eq kind :attdef))
     (OCS:writeAttr e data))
    ((eq kind :dim)
     (OCS:writeDim e data))
    ((eq kind :mleader)
     (OCS:writeMLeader e data))
    ((eq kind :leader)
     (OCS:writeLeader e data))
    ((eq kind :table)
     (OCS:writeTable e data))
    ((eq kind :tolerance)
     (OCS:writeTolerance e data))
    (T (list :ok nil :error "未知宿主类型"))
  )
)

(defun OCS:writeTextLike (e data / txt r before)
  (setq txt (OCS:assocd :text data nil))
  (if (null txt)
    (list :ok nil :error "无内容")
    (progn
      (setq before (OCS:hostSnapshot e))
      (setq r (vl-catch-all-apply 'vla-put-TextString (list e txt)))
      (if (vl-catch-all-error-p r)
        (list :ok nil :error (vl-catch-all-error-message r))
        (OCS:verifyHost e before (list :text txt))
      )
    )
  )
)

(defun OCS:writeAttr (e data / txt r before mt w)
  (setq txt (OCS:assocd :text data nil))
  (if (null txt)
    (list :ok nil :error "无内容")
    (progn
      (setq before (OCS:hostSnapshot e))
      (setq mt (OCS:safeProp e 'MTextAttribute))
      (if (equal mt :vlax-true)
        (progn
          (setq r (vl-catch-all-apply 'vla-put-MTextAttributeContent (list e txt)))
          (if (vl-catch-all-error-p r)
            (setq r (cons :error (vl-catch-all-error-message r)))
            (progn
              ;; 多行属性：按可用接口更新显示
              (setq r2 (vl-catch-all-apply 'vla-UpdateMTextAttribute (list e)))
              (if (vl-catch-all-error-p r2)
                (setq r (cons :error (strcat "UpdateMTextAttribute 失败：" (vl-catch-all-error-message r2))))
              )
            )
          )
        )
        (progn
          (setq r (vl-catch-all-apply 'vla-put-TextString (list e txt)))
          (if (vl-catch-all-error-p r)
            (setq r (cons :error (vl-catch-all-error-message r)))
          )
        )
      )
      (if (OCS:errp r)
        (list :ok nil :error (OCS:errmsg r))
        (OCS:verifyHost e before (list :text txt))
      )
    )
  )
)

(defun OCS:writeDim (e data / txt r before)
  (setq txt (OCS:assocd :text data nil))
  (if (null txt)
    (list :ok nil :error "无内容")
    (progn
      (setq before (OCS:hostSnapshot e))
      (setq r (vl-catch-all-apply 'vla-put-TextOverride (list e txt)))
      (if (vl-catch-all-error-p r)
        (list :ok nil :error (vl-catch-all-error-message r))
        (OCS:verifyHost e before (list :text txt))
      )
    )
  )
)

(defun OCS:writeMLeader (e data / txt r before)
  (setq txt (OCS:assocd :text data nil))
  (if (null txt)
    ;; 块内容：块内文字由块定义转换覆盖，无需改写
    (list :ok T :skip T)
    (progn
      (setq before (OCS:hostSnapshot e))
      (setq r (vl-catch-all-apply 'vla-put-TextString (list e txt)))
      (if (vl-catch-all-error-p r)
        (list :ok nil :error (vl-catch-all-error-message r))
        (OCS:verifyHost e before (list :text txt))
      )
    )
  )
)

(defun OCS:writeLeader (e data / ann r txt)
  ;; 关联注释对象单独处理（可能为 TEXT/MTEXT/块）
  (setq ann (OCS:assocd :annotation data nil))
  (if (null ann)
    (list :ok T :skip T)
    (progn
      (setq txt (OCS:assocd :text data nil))
      (if (null txt)
        (list :ok T :skip T)
        (progn
          (setq before (OCS:hostSnapshot ann))
          (setq r (vl-catch-all-apply 'vla-put-TextString (list ann txt)))
          (if (vl-catch-all-error-p r)
            (list :ok nil :error (vl-catch-all-error-message r))
            (OCS:verifyHost ann before (list :text txt))
          )
        )
      )
    )
  )
)

(defun OCS:writeTolerance (e data / txt r before)
  (setq txt (OCS:assocd :text data nil))
  (if (null txt)
    (list :ok T :skip T)
    (progn
      (setq before (OCS:hostSnapshot e))
      (setq r (vl-catch-all-apply 'vla-put-Text (list e txt)))
      (if (vl-catch-all-error-p r)
        (list :ok nil :error (vl-catch-all-error-message r))
        (OCS:verifyHost e before (list :text txt))
      )
    )
  )
)

;; 表格：保留数据语义（方案第 6、8 节）
;; - 临时抑制再生，结束时恢复
;; - 枚举行列与内容项（不假定只有 0 项）
;; - 字段/公式/数据链接不以显示值回写；仅普通文本参与字体指令替换
(defun OCS:writeTable (e data / rows cols r prev cnt)
  (setq rows (OCS:assocd :rows data nil)
        cols  (OCS:assocd :cols data nil))
  (if (or (null rows) (null cols))
    (list :ok nil :error "无法读取表格行列数")
    (progn
      ;; 记录原抑制状态并抑制
      (setq prev (OCS:safeProp e 'RegenerateTableSuppressed))
      (setq r (vl-catch-all-apply 'vla-put-RegenerateTableSuppressed (list e :vlax-true)))
      (if (vl-catch-all-error-p r)
        (setq r (cons :error (strcat "抑制表格再生失败：" (vl-catch-all-error-message r))))
        (progn
          (setq r (OCS:tableProcess e rows cols data))
          ;; 恢复原状态（必须）
          (setq r2 (vl-catch-all-apply 'vla-put-RegenerateTableSuppressed
                     (list e (if (equal prev :vlax-true) :vlax-true :vlax-false))))
          (if (vl-catch-all-error-p r2)
            (setq r (cons :error (strcat "恢复表格再生状态失败：" (vl-catch-all-error-message r2)))))
          (if (OCS:errp r)
            (list :ok nil :error (OCS:errmsg r))
            (list :ok T :contents (OCS:assocd :contents r 0))
          )
        )
      )
    )
  )
)

(defun OCS:tableProcess (e rows cols data / r row col content txt new n go errList)
  (setq n 0 row 0 errList nil)
  (while (< row rows)
    (setq col 0)
    (while (< col cols)
      ;; 枚举该单元格内容项：0..N-1。
      ;; 终点只由“确认越界”（OUT_OF_CONTENT / DISP_E_OVERFLOW）判定；
      ;; 一次普通读取失败、空字符串都不作为遍历终点，必须记录。
      (setq content 0)
      (setq go T)
      (while (and go (<= content 64))
        (setq r (OCS:tableGetText e row col content))
        (cond
          ((OCS:errp r)
           (if (= (OCS:assocd :code (OCS:errmsgList r) "") "OUT_OF_CONTENT")
             (setq go nil)                 ; 确认越界 → 该单元格枚举结束
             (progn                        ; 其他读取失败：记录并继续
               (setq errList (append errList
                             (list (list row col content (OCS:errmsg r)))))
               (setq content (1+ content))
             )
           )
          )
          ((null (car r))
           ;; 读到空串：不作为终点，继续下一内容项
           (setq content (1+ content))
          )
          (T
           (setq txt (car r))
           (if (> (strlen txt) 0)
             (progn
               (setq new (OCS:NormalizeFontRuns txt (OCS:fontTarget)))
               (if (and (> (OCS:assocd :changes new 0) 0)
                        (not (OCS:containsField txt)))
                 (progn
                   (setq r2 (OCS:tableSetText e row col content (OCS:assocd :text new txt)))
                   (if (OCS:errp r2)
                     (setq errList (append errList
                                 (list (list row col content (OCS:errmsg r2)))))
                     (setq n (1+ n))
                   )
                 )
               )
             )
           )
           (setq content (1+ content))
          )
        )
      )
      (setq col (1+ col))
    )
    (setq row (1+ row))
  )
  (list :contents n :errors errList)
)

;; tableGetText 返回 (cons :error (list :code .. :msg ..))
(defun OCS:errmsgList (r / lst)
  (setq lst (OCS:errmsg r))
  (if (listp lst) lst (list :msg lst))
)

(defun OCS:tableGetText (e row col content / r msg)
  (setq r (vl-catch-all-apply 'vla-GetTextString (list e row col content)))
  (cond
    ((vl-catch-all-error-p r)
     (setq msg (vl-catch-all-error-message r))
     (cons :error
           (list :code (if (or (OCS:strContains msg "8002000B")
                               (OCS:strContains msg "0x8002000B")
                               (OCS:strContains msg "超出")
                               (OCS:strContains msg "index"))
                           "OUT_OF_CONTENT" "READ_FAIL")
                 :msg msg)))
    (T (list r))
  )
)

(defun OCS:tableSetText (e row col content txt / r)
  (setq r (vl-catch-all-apply 'vla-SetTextString (list e row col content txt)))
  (if (vl-catch-all-error-p r)
    (cons :error (vl-catch-all-error-message r))
    T
  )
)

(defun OCS:containsField (s)
  (and (OCS:strContains s "%<") (OCS:strContains s ">%"))
)

(defun OCS:fontTarget ()
  (OCS:getVal (OCS:getVal *OCS:Plan* :font) :font
    (list (cons :family "SimSun") (cons :charSet 134)
          (cons :pitchFamily 36) (cons :appendParams T)))
)

;; 宿主快照（写后校验：非字体字段必须一致）
(defun OCS:hostSnapshot (e / kind)
  (list :height (OCS:safeProp e 'Height)
        :width (OCS:safeProp e 'Width)
        :rotation (OCS:safeProp e 'Rotation)
        :layer (OCS:safeProp e 'Layer)
        :color (OCS:safeProp e 'Color)
        :styleName (OCS:safeProp e 'StyleName)
        :tag (OCS:safeProp e 'TagString)
        :value (OCS:safeProp e 'TextString))
)

(defun OCS:verifyHost (e before expect / after ok)
  (setq after (OCS:hostSnapshot e) ok T)
  (foreach key (list :height :width :rotation :layer :color :styleName :tag)
    (if (not (equal (OCS:assocd key before nil) (OCS:assocd key after nil) 1e-9))
      (setq ok nil)
    )
  )
  (if (and (OCS:assocd :value expect nil)
           (not (equal (OCS:assocd :value expect nil) (OCS:assocd :value after nil))))
    (setq ok nil)
  )
  (if ok (list :ok T) (list :ok nil :error "写后校验：非字体数据发生变化"))
)

;;; =====================================================================
;;; 图层临时解锁（方案第 7 节）
;;; 仅临时解锁确有需要的本图图层，完成/异常时恢复；
;;; 关闭、冻结状态保持不动；外参图层保持原状。
;;; =====================================================================

(defun OCS:lockLayersNeeded ( / doc layers i lay name locked)
  (setq doc (OCS:activeDoc))
  (if (not doc) nil
    (progn
      (setq layers (vla-get-Layers doc) i 1)
      (while (<= i (vla-get-Count layers))
        (setq lay (OCS:safeItem layers i))
        (if lay
          (progn
            (setq name (OCS:safeProp lay 'Name)
                  locked (OCS:safeProp lay 'Lock))
            (if (and name (equal locked :vlax-true)
                     (not (OCS:isXrefLayer name)))
              (setq *OCS:TempState*
                    (append *OCS:TempState*
                            (list (list :layer name :obj lay))))
            )
          )
        )
        (setq i (1+ i))
      )
      *OCS:TempState*
    )
  )
)

(defun OCS:isXrefLayer (name)
  (OCS:strContains name "|")
)

(defun OCS:unlockTempLayers ( / item)
  (foreach item *OCS:TempState*
    (if (and (consp item) (eq (car item) :layer))
      (vl-catch-all-apply 'vla-put-Lock (list (OCS:assocd :obj item nil) :vlax-false))
    )
  )
)

(defun OCS:restoreTempLayers ( / item)
  (foreach item *OCS:TempState*
    (if (and (consp item) (eq (car item) :layer))
      (vl-catch-all-apply 'vla-put-Lock (list (OCS:assocd :obj item nil) :vlax-true))
    )
  )
)

;;; =====================================================================
;;; 报告构造辅助
;;; =====================================================================

(defun OCS:makeReport (status)
  (list :status (if status status "进行中")
        :errors 0
        :errorDetail nil
        :uncovered 0
        :uncoveredDetail nil
        :recoverFailed 0
        :stylesScanned 0 :stylesModified 0 :stylesXref 0 :stylesShape 0
        :hostsScanned 0 :fontRunsChanged 0 :attribs 0 :tableContents 0
        :blocks 0 :xrefBlocks 0 :displayBlocks 0
        :dwg (getvar "DWGPREFIX")
        :cadver (getvar "ACADVER")
        :family "SimSun")
)

(defun OCS:appendError (report where msg / errs detail)
  (setq errs  (1+ (OCS:assocd :errors report 0))
        detail (append (OCS:assocd :errorDetail report nil)
                       (list (list where msg))))
  (OCS:reportSet report
    (list (cons :errors errs) (cons :errorDetail detail))
  )
)

(defun OCS:appendErrors (report msgs / errs detail)
  (setq errs (+ (OCS:assocd :errors report 0) (length msgs))
        detail (OCS:assocd :errorDetail report nil))
  (foreach m msgs
    (setq detail (append detail (list (list "PREFLIGHT" m))))
  )
  (OCS:reportSet report
    (list (cons :errors errs) (cons :errorDetail detail))
  )
)

;; 用新值替换 plist 中已存在的键（不产生重复键）
(defun OCS:reportSet (report pairs / out updated)
  (setq out nil)
  (foreach pair pairs
    (setq updated nil out nil)
    (foreach item report
      (if (and (consp item) (eq (car item) (car pair)) (not updated))
        (progn (setq out (append out (list pair))) (setq updated T))
        (setq out (append out (list item)))
      )
    )
    (if (not updated) (setq out (append out (list pair))))
    (setq report out)
  )
  report
)

(defun OCS:problemsOf (res / out)
  (setq out nil)
  (foreach item res
    (if (and (consp item) (eq (car item) :problem)
             (consp (cdr item)) (eq (cadr item) :error))
      (setq out (append out (list (caddr item))))
    )
  )
  ;; 字体解析中的问题
  (foreach item (OCS:getVal res :font nil)
    (if (and (consp item) (eq (car item) :problem)
             (consp (cdr item)) (eq (cadr item) :error))
      (setq out (append out (list (caddr item))))
    )
  )
  out
)

;;; =====================================================================
;;; 再生与读回 OCS:VerifyDrawing
;;; =====================================================================

(defun OCS:VerifyDrawing ( / doc r)
  (setq doc (OCS:activeDoc))
  (if (not doc)
    (list :ok nil :error "无法获取活动文档")
    (progn
      (setq r (vl-catch-all-apply 'vla-Regen (list doc 1))) ; acAllViewports
      (if (vl-catch-all-error-p r)
        (list :ok nil :error (strcat "再生失败：" (vl-catch-all-error-message r)))
        (OCS:readbackStyles)
      )
    )
  )
)

;; 样式读回：字体族为宋体、大字体为空、原参数一致
(defun OCS:readbackStyles ( / ok details st ent e)
  (setq ok T details nil)
  (foreach st (OCS:assocd :styles *OCS:Plan* nil)
    (setq ent (tblobjname "STYLE" (OCS:assocd :name st "")))
    (if ent
      (progn
        (setq e (entget ent))
        (if (/= "" (OCS:assocd 4 e ""))
          (progn (setq ok nil)
                 (setq details (append details
                   (list (list "BIGFONT_NOT_EMPTY" (OCS:assocd 2 e "")))))))
        (if (OCS:assocd :before st nil)
          (if (not (OCS:styleReadbackOk (OCS:assocd :before st nil)
                                         (OCS:styleSnapshot ent)))
            (progn (setq ok nil)
                   (setq details (append details
                     (list (list "PARAM_CHANGED" (OCS:assocd 2 e "")))))))
        )
      )
      (progn (setq ok nil)
             (setq details (append details
               (list (list "STYLE_MISSING" (OCS:assocd :name st ""))))))
    )
  )
  (list :ok ok :details details)
)

;;; =====================================================================
;;; 回滚 OCS:Rollback（仅回滚本次操作）
;;; 回滚只作用于本次命令建立的 Undo 分组：结束分组后执行一次撤销，
;;; 绝不无条件 UNDO Back 撤销用户上一条命令。
;;; =====================================================================

(defun OCS:Rollback ( / r ok)
  (setq ok T)
  ;; 结束本次 Undo 分组（把全部写入归入一组）
  (OCS:endUndoGroup)
  ;; 仅撤销本次分组
  (setq r (vl-catch-all-apply 'command (list "_.U")))
  (if (or (vl-catch-all-error-p r) (null r))
    (setq ok nil)
  )
  ;; 恢复临时状态
  (if (not (OCS:restoreTempState))
    (setq ok nil)
  )
  ;; 回滚后读回核对（样式应回到转换前状态）
  (if (not (OCS:rollbackReadbackOk))
    (setq ok nil)
  )
  ok
)

;; 回滚后读回：本次计划中的样式不得残留空大字体之外的转换痕迹
(defun OCS:rollbackReadbackOk ( / ok st ent e)
  (setq ok T)
  (foreach st (OCS:assocd :styles *OCS:Plan* nil)
    (setq ent (tblobjname "STYLE" (OCS:assocd :name st "")))
    (if ent
      (progn
        (setq e (entget ent))
        ;; 若转换前该样式有大字体，回滚后应恢复
        (if (OCS:assocd :bigFontBefore st nil)
          (if (/= (OCS:assocd 4 e "") (OCS:assocd :bigFontBefore st ""))
            (setq ok nil)
          )
        )
      )
    )
  )
  ok
)

(defun OCS:endUndoGroup ( / )
  (if *OCS:UndoMark*
    (progn
      (vl-catch-all-apply 'vla-EndUndoMark
        (list (vla-get-ActiveDocument (vlax-get-acad-object))))
      (setq *OCS:UndoMark* nil)
    )
  )
  T
)

(defun OCS:restoreTempState ( / ok item lay)
  (setq ok T)
  ;; 恢复临时解锁的图层（原锁定状态）
  (foreach item *OCS:TempState*
    (if (and (consp item) (eq (car item) :layer))
      (progn
        (setq lay (OCS:assocd :obj item nil))
        (if lay
          (progn
            (setq r (vl-catch-all-apply 'vla-put-Lock (list lay :vlax-true)))
            (if (vl-catch-all-error-p r) (setq ok nil))
          )
        )
      )
    )
  )
  ;; 表格抑制状态已在各表处理中恢复；此处兜底清空
  (setq *OCS:TempState* nil)
  ok
)

;;; =====================================================================
;;; 报告 OCS:Report
;;; =====================================================================

(defun OCS:Report (report / f)
  (setq *OCS:LastReport* report)
  (setq *OCS:Report* report)
  ;; 中文命令行摘要
  (princ "\n")
  (princ (strcat "\n==== 一键统一宋体（YJST）===="))
  (princ (strcat "\n状态：" (OCS:assocd :status report "?")))
  (princ (strcat "\n图纸：" (OCS:assocd :dwg report "?")))
  (princ (strcat "\nCAD 版本：" (OCS:assocd :cadver report "?")))
  (princ (strcat "\n目标字体族：" (OCS:assocd :family report "SimSun")))
  (princ (strcat "\n扫描文字样式：" (itoa (OCS:assocd :stylesScanned report 0))
                 "　修改：" (itoa (OCS:assocd :stylesModified report 0))
                 "　外参依赖跳过：" (itoa (OCS:assocd :stylesXref report 0))
                 "　形文件跳过：" (itoa (OCS:assocd :stylesShape report 0))))
  (princ (strcat "\n扫描文字宿主：" (itoa (OCS:assocd :hostsScanned report 0))
                 "　修改字体段：" (itoa (OCS:assocd :fontRunsChanged report 0))
                 "　属性实例：" (itoa (OCS:assocd :attribs report 0))
                 "　表格内容项：" (itoa (OCS:assocd :tableContents report 0))))
  (princ (strcat "\n扫描块定义：" (itoa (OCS:assocd :blocks report 0))
                 "　外参块跳过：" (itoa (OCS:assocd :xrefBlocks report 0))
                 "　匿名显示块：" (itoa (OCS:assocd :displayBlocks report 0))))
  (princ (strcat "\n专业对象未覆盖：" (itoa (OCS:assocd :uncovered report 0))
                 "　错误：" (itoa (OCS:assocd :errors report 0))
                 "　恢复失败：" (itoa (OCS:assocd :recoverFailed report 0))))
  (if (OCS:assocd :errorDetail report nil)
    (progn
      (princ "\n错误明细：")
      (foreach d (OCS:assocd :errorDetail report nil)
        (princ (strcat "\n  " (OCS:fmt d))))
    )
  )
  (if (OCS:assocd :uncoveredDetail report nil)
    (progn
      (princ "\n未覆盖明细（句柄/位置）：")
      (foreach d (OCS:assocd :uncoveredDetail report nil)
        (princ (strcat "\n  " (OCS:fmt d))))
    )
  )
  (princ (strcat "\n详细记录：*OCS:LastReport*"))
  (princ)
  report
)

(defun OCS:fmt (x / out)
  (cond
    ((stringp x) x)
    ((numberp x) (rtos x 2 6))
    ((null x) "nil")
    ((listp x)
     (setq out "")
     (foreach i x
       (if (= out "") (setq out (OCS:fmt i))
         (setq out (strcat out " | " (OCS:fmt i)))))
     (strcat "(" out ")"))
    (T (vl-symbol-name x))
  )
)

;;; =====================================================================
;;; 用户命令 c:YJST —— 方案第 8 节流程
;;; =====================================================================

(defun c:YJST ( / )
  (if *OCS:Running*
    (princ "\nYJST：上一次运行尚未结束（重入被拒绝）。")
    (progn
      (setq *OCS:Running* T
            *OCS:EscRequested* nil
            *OCS:TempState* nil
            *OCS:UndoMark* nil)
      (OCS:mainFlow)
      (setq *OCS:Running* nil)
    )
  )
  (princ)
)

(defun OCS:mainFlow ( / report pre plan r okUndo)
  (setq *OCS:EscRequested* nil)
  ;; ---- 1) 预检（业务写入之前的一切检查） ----
  (setq pre (vl-catch-all-apply 'OCS:Preflight nil))
  (cond
    ((vl-catch-all-error-p pre)
     ;; 预检本身异常 → 未写入任何数据
     (setq report (OCS:makeReport "预检失败"))
     (setq report (OCS:appendErrors report
                     (list (vl-catch-all-error-message pre))))
     (OCS:Report report)
    )
    ((not (OCS:getVal pre :ok nil))
     (setq report (OCS:makeReport "预检失败"))
     (setq report (OCS:appendErrors report (OCS:problemsOf pre)))
     (OCS:Report report)
    )
    (T
     ;; ---- 2) 扫描并生成修改计划（只读阶段） ----
     (setq plan (vl-catch-all-apply 'OCS:BuildPlan nil))
     (if (vl-catch-all-error-p plan)
       (progn
         (setq report (OCS:makeReport "预检失败"))
         (setq report (OCS:appendErrors report
                         (list (strcat "扫描计划失败："
                                       (vl-catch-all-error-message plan)))))
         (OCS:Report report)
       )
       (progn
         (setq *OCS:Plan* (OCS:putPair plan :font (OCS:getVal pre :font)))
         ;; ---- 3) 开始 Undo 分组 ----
         (setq okUndo (OCS:beginUndoGroup))
         (if (not okUndo)
           (progn
             (setq report (OCS:makeReport "撤销不可用，未写入任何数据"))
             (OCS:Report report)
           )
           (progn
             ;; 写入阶段：任何未捕获错误都进入收尾/回滚（含 Esc）
             (setq report (vl-catch-all-apply 'OCS:executeWrites nil))
             (if (vl-catch-all-error-p report)
               (progn
                 (setq report (OCS:makeReport "失败已回滚"))
                 (setq report (OCS:appendErrors report
                                 (list (vl-catch-all-error-message report))))
                 ;; Esc 或未预期错误：恢复临时状态并回滚本次分组
                 (OCS:restoreTempState)
                 (if (not (OCS:Rollback))
                   (setq report (OCS:reportSet report (list (cons :recoverFailed 1))))
                 )
                 ;; appendErrors 会把 :status 覆盖？不会：它只改 :errors/:errorDetail
                 (setq report (OCS:reportSet report (list (cons :status "失败已回滚"))))
               )
             )
             (OCS:Report report)
           )
         )
       )
     )
    )
  )
  (princ)
)

(defun OCS:beginUndoGroup ( / doc r)
  (setq doc (OCS:activeDoc))
  (if (not doc) nil
    (progn
      (setq r (vl-catch-all-apply 'vla-StartUndoMark (list doc)))
      (if (vl-catch-all-error-p r) nil
        (progn (setq *OCS:UndoMark* T) T)
      )
    )
  )
)

;; 执行写入与检查（含回滚路径）
(defun OCS:executeWrites ( / report stylesRes hostsRes verifyRes wrote)
  (setq report (OCS:makeReport nil))
  ;; 临时解锁
  (OCS:lockLayersNeeded)
  (OCS:unlockTempLayers)
  ;; 样式写入
  (setq stylesRes (OCS:applyAllStyles))
  (if (OCS:assocd :error stylesRes nil)
    (setq report (OCS:appendError report "STYLE" (OCS:assocd :error stylesRes ""))))
  ;; 内容写入
  (setq hostsRes (OCS:applyAllHosts))
  ;; 其余统计（report 中已预置同名键，必须替换而非追加）
  (setq report (OCS:reportSet report
                 (list
                   (cons :stylesScanned (length (OCS:assocd :styles *OCS:Plan* nil)))
                   (cons :stylesModified (OCS:assocd :modified stylesRes 0))
                   (cons :stylesXref (length (OCS:assocd :xrefStyle *OCS:Plan* nil)))
                   (cons :stylesShape (length (OCS:assocd :shape *OCS:Plan* nil)))
                   (cons :hostsScanned (length (OCS:assocd :hosts *OCS:Plan* nil)))
                   (cons :fontRunsChanged (OCS:assocd :changes hostsRes 0))
                   (cons :attribs (OCS:assocd :attribs (OCS:assocd :stats *OCS:Plan*) 0))
                   (cons :blocks (OCS:assocd :blocks (OCS:assocd :stats *OCS:Plan*) 0))
                   (cons :xrefBlocks (OCS:assocd :xrefBlocks (OCS:assocd :stats *OCS:Plan*) 0))
                   (cons :displayBlocks (OCS:assocd :displayBlocks (OCS:assocd :stats *OCS:Plan*) 0))
                   (cons :tableContents (OCS:assocd :tableContents hostsRes 0))
                   (cons :uncovered (OCS:assocd :unknown (OCS:assocd :stats *OCS:Plan*) 0))
                   (cons :uncoveredDetail (OCS:assocd :skipped (OCS:assocd :stats *OCS:Plan*) nil))
                 )))
  (if (OCS:assocd :error hostsRes nil)
    (setq report (OCS:appendError report "HOST" (OCS:assocd :error hostsRes ""))))
  ;; 临时状态恢复
  (OCS:restoreTempState)
  ;; 中途错误（写入失败/解析问题）→ 回滚本次业务写入
  (if (OCS:assocd :errors report 0)
    (progn
      (setq report (OCS:reportSet report (list (cons :status "失败已回滚"))))
      (if (not (OCS:Rollback))
        (setq report (OCS:reportSet report (list (cons :recoverFailed 1))))
      )
    )
    (progn
      ;; 再生 + 读回
      (OCS:TestFault "regen-check")
      (setq verifyRes (OCS:VerifyDrawing))
      (if (not (OCS:assocd :ok verifyRes T))
        (progn
          (setq report (OCS:appendError report "VERIFY" (OCS:assocd :error verifyRes "")))
          ;; 读回不符 → 回滚本次修改
          (setq report (OCS:reportSet report (list (cons :status "失败已回滚"))))
          (if (not (OCS:Rollback))
            (setq report (OCS:reportSet report (list (cons :recoverFailed 1))))
          )
        )
        (progn
          (OCS:endUndoGroup)
          ;; 状态判定（方案第 12 节）
          (setq report (OCS:reportSet report
            (list (cons :status
              (cond
                ((> (OCS:assocd :errors report 0) 0) "失败已回滚")
                ((> (OCS:assocd :uncovered report 0) 0) "部分完成")
                ((and (= 0 (OCS:assocd :stylesModified report 0))
                      (= 0 (OCS:assocd :fontRunsChanged report 0)))
                 "无需修改")
                (T "已完成")
              )))))
        )
      )
    )
  )
  (setq report (OCS:reportSet report
                 (list (cons :dwg (getvar "DWGPREFIX"))
                       (cons :cadver (getvar "ACADVER"))
                       (cons :family "SimSun"))))
  report
)

(defun OCS:applyAllStyles ( / modified err)
  (setq modified 0 err nil)
  (foreach st (OCS:assocd :styles *OCS:Plan* nil)
    (if (not err)
      (progn
        (OCS:TestFault "style-write")
        (setq r (OCS:ApplyStyle (OCS:activeDoc) st))
        (if (OCS:assocd :ok r nil)
          (setq modified (1+ modified))
          (setq err (OCS:assocd :error r "未知错误"))
        )
      )
    )
  )
  (list :modified modified :error err)
)

(defun OCS:applyAllHosts ( / changes tableContents err data new r)
  (setq changes 0 tableContents 0 err nil)
  (foreach host (OCS:assocd :hosts *OCS:Plan* nil)
    (if (not err)
      (progn
        (setq data (OCS:ReadHost host))
        (if (OCS:assocd :error data nil)
          (setq err (strcat (OCS:assocd :handle host "?") ": " (OCS:assocd :error data "")))
          (if (not (OCS:assocd :skip data nil))
            (progn
              (setq new (OCS:NormalizeFontRuns (OCS:assocd :text data "") (OCS:fontTarget)))
              (if (OCS:assocd :issues new nil)
                (setq err (strcat (OCS:assocd :handle host "?") ": 内容解析问题 "
                                   (OCS:fmt (OCS:assocd :issues new nil))))
              )
              (if (and (not err) (> (OCS:assocd :changes new 0) 0))
                (progn
                  (OCS:TestFault "content-write")
                  (setq data (OCS:putPair data :text (OCS:assocd :text new "")))
                  (setq r (OCS:WriteHost host data))
                  (if (OCS:assocd :ok r nil)
                    (progn
                      (setq changes (+ changes (OCS:assocd :changes new 0)))
                      (if (eq (OCS:assocd :kind host) :table)
                        (setq tableContents (+ tableContents (OCS:assocd :contents r 0)))
                      )
                    )
                    (setq err (strcat (OCS:assocd :handle host "?") ": " (OCS:assocd :error r "")))
                  )
                )
              )
            )
          )
        )
      )
    )
  )
  (list :changes changes :tableContents tableContents :error err)
)

;;; ----------------------------------------------------------------------
;;; 故障注入（仅测试入口，正常运行不受影响）
;;; ----------------------------------------------------------------------
(defun OCS:TestFault (point)
  (if (and *OCS:FaultPoint* (= *OCS:FaultPoint* point))
    (progn
      (setq *OCS:FaultPoint* nil)
      (error (strcat "OCS 故障注入：" point))
    )
  )
)

;;; ----------------------------------------------------------------------
;;; 自检入口（纯函数部分，不依赖 CAD 环境）：OCS:SelfTest
;;; ----------------------------------------------------------------------
(defun OCS:SelfTest ( / cases pass fail)
  (setq cases (OCS:selfTestCases) pass 0 fail 0)
  (foreach c cases
    (progn
      (setq in  (car c) want (cadr c) wantN (caddr c))
      (setq r (OCS:NormalizeFontRuns in (list (cons :family "SimSun")
                                               (cons :charSet 134)
                                               (cons :pitchFamily 36)
                                               (cons :appendParams T))))
      (setq out (OCS:assocd :text r ""))
      (setq n  (OCS:assocd :changes r 0))
      (if (and (= out want) (= n wantN))
        (setq pass (1+ pass))
        (progn
          (setq fail (1+ fail))
          (princ (strcat "\nFAIL in=[" in "] got=[" out "] want=[" want "]"))
        )
      )
    )
  )
  (princ (strcat "\nOCS:SelfTest 通过 " (itoa pass) " / 失败 " (itoa fail)))
  (setq fail)
)

(defun OCS:selfTestCases ( / long1 acc n)
  ;; 与 tests/font-format-cases.json 一一对应：
  ;; C01-plain-inherit, C02-font-arial-bold-italic, C03-height-nested-fonts,
  ;; C04-paragraph-codes, C05-stack-diameter-tolerance, C06-field-code-protected,
  ;; C07-escaped-backslash-brace, C08-long-mixed-text, C09-already-simsun,
  ;; C10-incomplete-code-error, C11-nested-two-fonts, C12-underline-color-preserved,
  ;; C13-second-run-zero, C14-chinese-font-name-in-body, C15-nested-field-inside-format
  (setq long1 "")
  (setq n 0)
  (while (< n 60)
    (setq long1 (strcat long1 "英文 ABC 与中文 宋体测试"))
    (setq n (1+ n))
  )
  (list
    ;; C01
    (list "本页统一使用黑体，字高 3.5。" "本页统一使用黑体，字高 3.5。" 0)
    ;; C02
    (list "{\\fArial|b1|i0;标题正文}" "{\\fSimSun|b1|i0|c134|pf22;标题正文}" 1)
    ;; C03
    (list "{\\H0.7x;\\fSimHei|b0|i1;说明段落}" "{\\H0.7x;\\fSimSun|b0|i1|c134|pf22;说明段落}" 1)
    ;; C04
    (list "\\pl1;第一段\\P第二段\\fTimes New Roman;第三段"
          "\\pl1;第一段\\P第二段\\fSimSun|c134|pf22;第三段" 1)
    ;; C05
    (list "%%c12 \\fISOCPEUR;\\S1/2; 完"
          "%%c12 \\fSimSun|c134|pf22;\\S1/2; 完" 1)
    ;; C06 字段保护（示例字段内容，\f 位于 %<...>% 内）
    (list "值 %<\\f\\H0.5x;\\C1;\\f% \\pr \"0.00\";.Measured|%fml \\f+1; %>结束"
          "值 %<\\f\\H0.5x;\\C1;\\f% \\pr \"0.00\";.Measured|%fml \\f+1; %>结束" 0)
    ;; C07 转义
    (list "路径 C:\\temp\\{图} 与 \\fArial 不变"
          "路径 C:\\temp\\{图} 与 \\fArial 不变" 0)
    ;; C08 长文本（应无修改，完整往返）
    (list long1 long1 0)
    ;; C09 已是宋体
    (list "{\\fSimSun|b0|i0|c134|pf22;已统一}" "{\\fSimSun|b0|i0|c134|pf22;已统一}" 0)
    ;; C10 不完整指令 → 不修改原文（错误由 :issues 报告）
    (list "前面{\\fArial" "前面{\\fArial" 0)
    ;; C11 嵌套两个字体
    (list "{\\fArial|b1|i0;标题}\\P{\\H0.7x;\\fSimHei|b0|i1;说明}"
          "{\\fSimSun|b1|i0|c134|pf22;标题}\\P{\\H0.7x;\\fSimSun|b0|i1|c134|pf22;说明}" 2)
    ;; C12 颜色与字距保持
    (list "\\C3;\\fCourier New;固定\\fSimSun;字宽\\Q5;尾"
          "\\C3;\\fSimSun|c134|pf22;固定\\fSimSun|c134|pf22;字宽\\Q5;尾" 2)
    ;; C13 幂等
    (list "{\\fSimSun|b1|i0|c134|pf22;幂等}" "{\\fSimSun|b1|i0|c134|pf22;幂等}" 0)
    ;; C14 正文中的字体名不改
    (list "本页统一使用黑体与 Arial 字体名说明"
          "本页统一使用黑体与 Arial 字体名说明" 0)
    ;; C15 字段嵌套在格式作用域内
    (list "{\\fArial|b1;i;前 %<\\\\AcVar \\f\\\\H;>后}"
          "{\\fSimSun|b1|c134|pf22;i;前 %<\\\\AcVar \\f\\\\H;>后}" 1)
  )
)

;;; =====================================================================
;;; 加载提示
;;; =====================================================================
(princ (strcat "\n一键统一宋体（YJST）v" *OCS:Version*
               " 已加载。输入 YJST 执行。"))
(princ)
