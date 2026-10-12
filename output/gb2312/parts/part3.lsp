;;; part3 - 主源码第 208-408 行（顶层 form 29-42，共 159 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART3
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
  (OCS:assocd "charSet" target 134)
)
(defun OCS:targetPitchFamily (target)
  (OCS:assocd "pitchFamily" target 36)
)
(defun OCS:targetAppendParams (target)
  (OCS:assocd "appendParams" target T)
)

;; 追加解析问题
(defun OCS:addIssue (st code pos msg)
  (list "i"   (OCS:assocd "i" st 1)
        "issues" (append (OCS:assocd "issues" st nil)
                        (list (list code pos (OCS:assocd "len" st 0) msg)))
        "changes" (OCS:assocd "changes" st 0)
        "len" (OCS:assocd "len" st 0))
)

;; 判断字体族是否已是目标族（不区分大小写；接受“宋体”）
(defun OCS:isTargetFamily (fam target / tf)
  (setq tf (OCS:assocd "family" target "SimSun"))
  (or (OCS:equalsIgnoreCase fam tf)
      (and (OCS:equalsIgnoreCase tf "SimSun")
           (or (OCS:equalsIgnoreCase fam "宋体")
               (OCS:equalsIgnoreCase fam "sim sun")
               (OCS:equalsIgnoreCase fam "SimSun")))
      (OCS:equalsIgnoreCase fam "宋体"))
)
(princ "\nOK-PART3 lines 208-408")
(princ)
