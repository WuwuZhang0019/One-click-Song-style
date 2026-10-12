;;; probe p03 (03/13) - 引擎特性测试：字符串转义：反斜杠 \\、转义引号 \"、\n、\t
;;; 由 tools/build_diag.py 生成；加载成功应看到 PROBE-03-OK 标记
;;; probe p03 - string escapes: backslash, escaped quote, newline, tab
(defun OCS-P3 ( / s )
  (setq s (strcat "a\\b" "\"q\"" "x\ty" "x\ny"))
  (princ "\nPROBE-03-OK string-escapes")
  (princ s)
)
(OCS-P3)
