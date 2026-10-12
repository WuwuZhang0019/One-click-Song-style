;;; part3 - 主源码第 235-470 行（顶层 form 27-39，共 151 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART3
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
(princ "\nOK-PART3 lines 235-470")
(princ)
