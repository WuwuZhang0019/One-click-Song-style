;;; probe p05 (05/13) - 引擎特性测试：quote 简写 'symbol 与通过变量调用函数
;;; 由 tools/build_diag.py 生成；加载成功应看到 PROBE-05-OK 标记
;;; probe p05 - quote shorthand and calling function held in variable
(defun OCS-P5fn ( / ) (princ "\nPROBE-05-OK quote-shorthand"))
(defun OCS-P5 ( / f )
  (setq f 'OCS-P5fn)
  (if f (f) (princ "\nPROBE-05-FAIL"))
)
(OCS-P5)
