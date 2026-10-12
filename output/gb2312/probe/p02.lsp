;;; probe p02 (02/13) - 引擎特性测试：注释内含 ASCII 括号与引号（模拟主源码 133-135 行注释）
;;; 由 tools/build_diag.py 生成；加载成功应看到 PROBE-02-OK 标记
;;; probe p02 - comment containing ASCII parens and quotes
;; 注意：不使用 defmacro / 反引号宏。加载时会把 (fn &rest args) 参数表
;; 当普通调用求值，报 "no function definition: FN"。
(defun OCS-P2 ( / )
  (princ "\nPROBE-02-OK comment-parens-quotes")
)
(OCS-P2)
