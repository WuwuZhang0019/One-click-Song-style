;;; part2 - 主源码第 80-196 行（顶层 form 15-28，共 159 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART2
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

;; 注意：不使用 defmacro / 反引号宏。部分 CAD 引擎不把 defmacro 当特殊形式，
;; 加载时会把 (fn &rest args) 参数表当普通调用求值，报 "no function definition: FN"。
;; 报错包装直接用 vl-catch-all-apply（见各调用点），此处只保留 errp/errmsg。

;; 报错判断
(defun OCS:errp (x)
  (and (OCS:consp x) (equal (car x) "error"))
)

;; 错误信息取文本
(defun OCS:errmsg (x)
  (if (OCS:errp x) (cdr x) "")
)
(princ "\nOK-PART2 lines 80-196")
(princ)
