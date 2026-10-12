;;; probe p06 (06/13) - 引擎特性测试：科学计数法 1e-9（equal 容差用）
;;; 由 tools/build_diag.py 生成；加载成功应看到 PROBE-06-OK 标记
;;; probe p06 - scientific notation real literal
(defun OCS-P6 ( / e )
  (setq e 1e-9)
  (if (and (< e 1.0) (> e 0.0))
    (princ "\nPROBE-06-OK scientific-notation")
    (princ "\nPROBE-06-FAIL")
  )
)
(OCS-P6)
