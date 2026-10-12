;;; probe p04 (04/13) - 引擎特性测试：关键字符号 :error（plist 模式的基石）
;;; 由 tools/build_diag.py 生成；加载成功应看到 PROBE-04-OK 标记
;;; probe p04 - keyword symbols
(defun OCS-P4 ( / x )
  (setq x (list :error "msg" :ok T))
  (if (eq (car x) :error)
    (princ "\nPROBE-04-OK keyword-symbols")
    (princ "\nPROBE-04-FAIL")
  )
)
(OCS-P4)
