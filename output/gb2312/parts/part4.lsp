;;; part4 - 主源码第 410-675 行（顶层 form 43-56，共 159 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART4
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
;;;   s       ： 文字原始内容（MTEXT 全量原始串 / 属性内容等）
;;;   target  ： (list (cons :family "SimSun") (cons :charSet 134)
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
  (if (not (OCS:stringp s))
    (list "text" s "changes" 0 "issues" (list (list "BAD_INPUT" 0 0 "输入不是字符串")))
    (progn
      (setq len (strlen s))
      (setq st  (list "i" 1 "issues" nil "changes" 0 "len" len))
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
      (list "text" out
            "changes" (OCS:assocd "changes" st 0)
            "issues" (OCS:assocd "issues" st nil))
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
  (list "i" (OCS:assocd "i" st 1)
        "issues" (OCS:assocd "issues" st nil)
        "changes" (1+ (OCS:assocd "changes" st 0))
        "len" (OCS:assocd "len" st 0))
)

;; 重写字体描述：替换族名，保留 b/i，按目标覆盖/追加 c、pf
(defun OCS:rewriteDesc (desc target / parts out first p fam)
  (setq parts (OCS:splitDesc desc) out nil first T fam nil)
  (foreach p parts
    (cond
      ((= p "") nil)
      (first
        (setq fam p)
        (setq out (list (OCS:assocd "family" target "SimSun")))
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
  (setq res (list "ok" nil "family" "SimSun" "charSet" 134 "pitchFamily" 36
                  "fontFile" nil "fontFileSource" nil "bigFontEmpty" nil
                  "problems" nil "appendParams" T))
  ;; 候选字体文件（顺序即优先级；不接受 NSimSun/SimHei/STSong 顶替）
  (setq res (OCS:addProblem res "info" "候选字体文件扫描"))
  (setq f (OCS:findSimSunFile))
  (if (not f)
    (setq res (OCS:addProblem res "error"
      "未找到 SimSun 字体文件（simsun.ttc / simsun.ttf / SIMSUN.TTF），不能用其他字体替代"))
    (progn
      (setq res (OCS:putPair res "fontFile" f))
      (setq res (OCS:putPair res "fontFileSource" (OCS:fontFileSource f)))
    )
  )
  ;; 试验样式写入验证
  (setq res (OCS:verifyFontWrite res))
  res
)

(defun OCS:addProblem (res level msg)
  (append res (list (list "problem" level msg)))
)
(defun OCS:putPair (res key val / out done)
  ;; 若键已存在则替换，否则追加（保证 plist 键唯一）
  (setq out nil done nil)
  (foreach pair res
    (if (and (not done) (OCS:consp pair) (equal (car pair) key))
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
(princ "\nOK-PART4 lines 410-675")
(princ)
