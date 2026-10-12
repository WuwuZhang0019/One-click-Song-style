;;; part2 - 主源码第 74-232 行（顶层 form 14-26，共 151 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART2
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

;; 注意：不使用 defmacro / 反引号宏。部分 CAD 引擎不把 defmacro 当特殊形式，
;; 加载时会把 (fn &rest args) 参数表当普通调用求值，报 "no function definition: FN"。
;; 报错包装直接用 vl-catch-all-apply（见各调用点），此处只保留 errp/errmsg。

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
(princ "\nOK-PART2 lines 74-232")
(princ)
