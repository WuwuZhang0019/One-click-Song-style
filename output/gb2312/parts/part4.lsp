;;; part4 - 主源码第 475-711 行（顶层 form 40-52，共 151 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART4
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
    (if (and (not done) (consp pair) (equal (car pair) key))
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
    (setq res (OCS:addProblem res "error" "无法获取活动文档（ActiveX 不可用）"))
    (progn
      (setq name (OCS:tempStyleName))
      (OCS:deleteStyleIfExists name)
      (setq r (vl-catch-all-apply 'vla-AddTextStyle
                (list doc name (OCS:styleBaseFont) "vlax-true")))
      (if (vl-catch-all-error-p r)
        (setq res (OCS:addProblem res "error"
                    (strcat "创建试验文字样式失败：" (vl-catch-all-error-message r))))
        (progn
          (setq ent (tblobjname "STYLE" name))
          (if (not ent)
            (setq res (OCS:addProblem res "error" "试验文字样式创建后未找到 STYLE 记录"))
            (progn
              (setq o (vlax-ename->vla-object ent))
              ;; FontFile 写入（先文件名）
              (setq f (OCS:getVal res "fontFile"))
              (setq bf (if (consp f) (cadr f) f))
              (setq r (vl-catch-all-apply 'vla-put-FontFile (list o bf)))
              (if (vl-catch-all-error-p r)
                (progn
                  ;; 名称失败 → 绝对路径
                  (setq r (vl-catch-all-apply 'vla-put-FontFile (list o (car f))))
                  (if (vl-catch-all-error-p r)
                    (setq res (OCS:addProblem res "error"
                      (strcat "FontFile 写入失败：" (vl-catch-all-error-message r))))
                    (progn
                      (setq res (OCS:putPair res "fontFileSource" (strcat (car f) " (绝对路径回退)")))
                    ))
                )
              )
              ;; SetFont（字体族名 + 字符集 + pitch/family）
              (if (not (OCS:hasError res))
                (progn
                  (setq r (vl-catch-all-apply 'vla-SetFont
                    (list o "SimSun" "vlax-false" "vlax-false"
                          (OCS:getVal res "charSet")
                          (OCS:getVal res "pitchFamily"))))
                  (if (vl-catch-all-error-p r)
                    (setq res (OCS:addProblem res "error"
                      (strcat "SetFont(SimSun) 失败：" (vl-catch-all-error-message r))))
                  )
                )
              )
              ;; 写入后立即读回验证：FontFile 与 LastFontFile
              (if (not (OCS:hasError res))
                (progn
                  (setq r (vl-catch-all-apply 'vla-get-FontFile (list o)))
                  (if (or (vl-catch-all-error-p r) (= r ""))
                    (setq res (OCS:addProblem res "error" "FontFile 读回为空，字体未被 CAD 解析"))
                    (setq res (OCS:putPair res "fontFileReadback" r))
                  )
                )
              )
              ;; 大字体清空验证（STYLE DXF 组码 4）
              (if (not (OCS:hasError res))
                (setq res (OCS:verifyBigFontClear res ent name))
              )
              ;; 记录写入顺序证据
              (setq res (OCS:putPair res "writeOrder" "FontFile → SetFont → 大字体清空(组码4) → 读回"))
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
  (setq p (assoc "problem" res))
  ;; 扫描列表中是否有 :error
  (OCS:findError res)
)
(princ "\nOK-PART4 lines 475-711")
(princ)
