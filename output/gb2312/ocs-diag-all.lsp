;;; ocs-diag-all.lsp - 一键诊断 v2：加载本文件即自动执行全部测试（vanilla LISP）
;;; A. 引擎特性探针 probe/p01..p13（13 项语法特性；v1 的 p1..p9 文件名 bug 已修）
;;; B. part12 测试用例逐条探针 cases/c01..cNN（15 条 MTEXT 用例字符串）
;;; C. part12 逐顶层 form 探针 sub12/f01..fNN（定位到具体 defun）
;;; D. 行尾实验：CRLF 版与 LF 版各 LOAD 一次（可能中断驱动，放最后）
;;; 程序自动临时关闭 SECURELOAD，全程无安全弹窗；若中途中断，
;;; 请手动执行 (setvar "SECURELOAD" 1) 恢复。
(princ "\n==== OCS 一键诊断 v2 开始 ====")
(princ "\n(SECURELOAD 已由程序临时关闭；若中途中断请执行 (setvar \"SECURELOAD\" 1) 恢复)")
(vl-catch-all-apply 'setvar (list "SECURELOAD" 0))

;; ---- A. 引擎特性探针 ----
(princ "\n---- A. 引擎特性探针（13 项）----")
(setq OCS-DIAG-I 1)
(while (<= OCS-DIAG-I 13)
  (setq OCS-DIAG-NM (itoa OCS-DIAG-I))
  (if (< OCS-DIAG-I 10) (setq OCS-DIAG-NM (strcat "0" OCS-DIAG-NM)))
  (setq OCS-DIAG-F (strcat "H:/coding/一键改宋体/One-click-Song-style/output/gb2312/probe/p" OCS-DIAG-NM ".lsp"))
  (princ (strcat "\n== PROBE " OCS-DIAG-NM "/13 == "))
  (setq OCS-DIAG-R (load OCS-DIAG-F "PROBE-LOAD-FAILED"))
  (if (= OCS-DIAG-R "PROBE-LOAD-FAILED")
    (princ "<<< LOAD FAILED（软失败）")
    (princ "ok")
  )
  (setq OCS-DIAG-I (1+ OCS-DIAG-I))
)

;; ---- B. part12 测试用例逐条探针 ----
(princ "\n---- B. part12 用例逐条探针（15 条）----")
(setq OCS-DIAG-I 1)
(while (<= OCS-DIAG-I 15)
  (setq OCS-DIAG-NM (itoa OCS-DIAG-I))
  (if (< OCS-DIAG-I 10) (setq OCS-DIAG-NM (strcat "0" OCS-DIAG-NM)))
  (setq OCS-DIAG-F (strcat "H:/coding/一键改宋体/One-click-Song-style/output/gb2312/cases/c" OCS-DIAG-NM ".lsp"))
  (princ (strcat "\n== CASE " OCS-DIAG-NM "/15 == "))
  (setq OCS-DIAG-R (load OCS-DIAG-F "CASE-LOAD-FAILED"))
  (if (= OCS-DIAG-R "CASE-LOAD-FAILED")
    (princ "<<< LOAD FAILED（软失败）")
    (princ "ok")
  )
  (setq OCS-DIAG-I (1+ OCS-DIAG-I))
)

;; ---- C. part12 逐顶层 form 探针 ----
(princ "\n---- C. part12 逐 form 探针（8 个）----")
(setq OCS-DIAG-I 1)
(while (<= OCS-DIAG-I 8)
  (setq OCS-DIAG-NM (itoa OCS-DIAG-I))
  (if (< OCS-DIAG-I 10) (setq OCS-DIAG-NM (strcat "0" OCS-DIAG-NM)))
  (setq OCS-DIAG-F (strcat "H:/coding/一键改宋体/One-click-Song-style/output/gb2312/sub12/f" OCS-DIAG-NM ".lsp"))
  (princ (strcat "\n== FORM " OCS-DIAG-NM "/8 == "))
  (setq OCS-DIAG-R (load OCS-DIAG-F "FORM-LOAD-FAILED"))
  (if (= OCS-DIAG-R "FORM-LOAD-FAILED")
    (princ "<<< LOAD FAILED（软失败）")
    (princ "ok")
  )
  (setq OCS-DIAG-I (1+ OCS-DIAG-I))
)

;; ---- D. 行尾实验（整文件加载，若触发语法错误会中断驱动，属预期） ----
(princ "\n---- D. 行尾实验（若中断属预期，诊断数据已全部打出）----")
(setq OCS-DIAG-R (load "H:/coding/一键改宋体/One-click-Song-style/output/gb2312/crlf/one-click-simsun.lsp" "CRLF-LOAD-FAILED"))
(if (= OCS-DIAG-R "CRLF-LOAD-FAILED")
  (princ "\nD 结果：主文件 CRLF 版 = LOAD FAILED（行尾不是根因）")
  (princ "\nD 结果：主文件 CRLF 版 = LOAD OK（行尾就是根因，交付改用 CRLF）")
)
(load "H:/coding/一键改宋体/One-click-Song-style/output/gb2312/one-click-simsun.lsp" "MAIN-LOAD-FAILED")

(princ "\n==== OCS 一键诊断 v2 结束 ====")
(vl-catch-all-apply 'setvar (list "SECURELOAD" 1))
(princ "\n(SECURELOAD 已恢复为 1)")
(princ)
