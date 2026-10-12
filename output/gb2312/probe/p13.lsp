;;; probe p13 (13/13) - 引擎特性测试：大整数 4294967296（toHex 用）与负数 -16（lsh 用）
;;; 由 tools/build_diag.py 生成；加载成功应看到 PROBE-13-OK 标记
;;; probe p13 - large integer and negative literal
(defun OCS-P13 ( / a b )
  (setq a 4294967296 b -16)
  (if (and (> a 0) (< b 0))
    (princ "\nPROBE-13-OK bigint-negative")
    (princ "\nPROBE-13-FAIL")
  )
)
(OCS-P13)
