;;; ocs-diag-all.lsp - 一键诊断 v3：加载本文件即自动执行全部测试（vanilla LISP）
;;; v3：所有 load 均用 vl-catch-all-apply 包裹，硬错误（语法错误/函数错误）
;;;     也能接住并继续，一次跑完全部诊断，不再中途断掉。
;;; A. 引擎特性探针 probe/p01..p13
;;; B. part12 测试用例逐条探针 cases/c01..cNN
;;; C. part12 逐顶层 form 探针 sub12/f01..fNN
;;; D. 行尾实验：CRLF 版与 LF 版整文件 LOAD
;;; 程序自动临时关闭 SECURELOAD，全程无安全弹窗；若中途中断，
;;; 请手动执行 (setvar "SECURELOAD" 1) 恢复。
(princ "\n==== OCS 一键诊断 v3 开始 ====")
(princ "\n(SECURELOAD 已由程序临时关闭；若中途中断请执行 (setvar \"SECURELOAD\" 1) 恢复)")
(vl-catch-all-apply 'setvar (list "SECURELOAD" 0))

;; 单个文件安全加载：硬错误/软失败都能识别且不中断驱动
(defun OCS:DIAG-TRYLOAD (f soft / r)
  (setq r (vl-catch-all-apply 'load (list f soft)))
  (if (vl-catch-all-error-p r)
    (princ "<<< 硬错误（原因见上方引擎输出）")
    (if (= r soft)
      (princ "<<< LOAD FAILED（软失败）")
      (princ "ok")
    )
  )
)

;; ---- A. 引擎特性探针 ----
(princ "\n---- A. 引擎特性探针（13 项）----")
(setq OCS-DIAG-I 1)
(while (<= OCS-DIAG-I 13)
  (setq OCS-DIAG-NM (itoa OCS-DIAG-I))
  (if (< OCS-DIAG-I 10) (setq OCS-DIAG-NM (strcat "0" OCS-DIAG-NM)))
  (setq OCS-DIAG-F (strcat "H:/coding/一键改宋体/One-click-Song-style/output/gb2312/probe/p" OCS-DIAG-NM ".lsp"))
  (princ (strcat "\n== PROBE " OCS-DIAG-NM "/13 == "))
  (OCS:DIAG-TRYLOAD OCS-DIAG-F "PROBE-LOAD-FAILED")
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
  (OCS:DIAG-TRYLOAD OCS-DIAG-F "CASE-LOAD-FAILED")
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
  (OCS:DIAG-TRYLOAD OCS-DIAG-F "FORM-LOAD-FAILED")
  (setq OCS-DIAG-I (1+ OCS-DIAG-I))
)

;; ---- D. 行尾实验（整文件加载） ----
(princ "\n---- D. 行尾实验 ----")
(princ "\n== CRLF 版 == ")
(OCS:DIAG-TRYLOAD "H:/coding/一键改宋体/One-click-Song-style/output/gb2312/crlf/one-click-simsun.lsp" "CRLF-LOAD-FAILED")
(princ "\n== LF 版（当前交付）== ")
(OCS:DIAG-TRYLOAD "H:/coding/一键改宋体/One-click-Song-style/output/gb2312/one-click-simsun.lsp" "MAIN-LOAD-FAILED")

(princ "\n==== OCS 一键诊断 v3 结束：请把以上全部输出发给开发 ====")
(vl-catch-all-apply 'setvar (list "SECURELOAD" 1))
(princ "\n(SECURELOAD 已恢复为 1)")
(princ)
