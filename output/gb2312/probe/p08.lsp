;;; probe p08 (08/13) - 引擎特性测试：中文字符串 + strcat 中文
;;; 由 tools/build_diag.py 生成；加载成功应看到 PROBE-08-OK 标记
;;; probe p08 - Chinese text inside strings
(defun OCS-P8 ( / s )
  (setq s (strcat "中文测试" "宋体"))
  (princ "\nPROBE-08-OK chinese-strings")
  (princ (strcat " strlen=" (itoa (strlen s))))
)
(OCS-P8)
