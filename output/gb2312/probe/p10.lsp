;;; probe p10 (10/13) - 引擎特性测试：vl-catch-all-apply + quote 传函数符号
;;; 由 tools/build_diag.py 生成；加载成功应看到 PROBE-10-OK 标记
;;; probe p10 - vl-catch-all-apply with quoted symbol
(defun OCS-P10 ( / r )
  (setq r (vl-catch-all-apply 'princ (list "\nPROBE-10-OK vl-catch-all-apply")))
  (if (vl-catch-all-error-p r)
    (princ "\nPROBE-10-FAIL")
  )
)
(OCS-P10)
