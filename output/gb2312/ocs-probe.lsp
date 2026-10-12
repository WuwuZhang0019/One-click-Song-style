;;; ocs-probe.lsp - 引擎特性探针驱动（vanilla LISP）
;;; 用法：APPLOAD 加载本文件后，命令行执行 OCS_PROBE
;;; 输出：逐个加载 probe/p01..p13.lsp，任一探针加载失败即指出
;;;      目标引擎不支持（或处理不同）的语法特性。
(defun c:OCS_PROBE ( / i f r nm)
  (setq i 1)
  (while (<= i 13)
    (setq nm (itoa i))
    (if (< i 10) (setq nm (strcat "0" nm)))
    (setq f (strcat "H:/coding/一键改宋体/One-click-Song-style/output/gb2312/probe/p" nm ".lsp"))
    (princ (strcat "\n== PROBE " (itoa i) "/13 == "))
    (setq r (load f "PROBE-LOAD-FAILED"))
    (if (= r "PROBE-LOAD-FAILED")
      (princ "<<< LOAD FAILED")
      (princ "ok")
    )
    (setq i (1+ i))
  )
  (princ "\n== PROBE DONE ==")
  (princ)
)
(princ "\nOCS 探针驱动已加载：执行 OCS_PROBE 逐项测试引擎语法特性。")
(princ)
