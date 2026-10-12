;;; ocs-bisect.lsp - 主文件二分定位驱动（vanilla LISP）
;;; 用法：APPLOAD 加载本文件后，命令行执行 OCS_BISECT
;;; 输出：逐部加载 parts/part1..part12.lsp，第一个 LOAD FAILED 的部件
;;;      即包含目标引擎无法读入的语法构造；把该部件行号范围反馈给开发。
(defun c:OCS_BISECT ( / i f r )
  (setq i 1)
  (while (<= i 12)
    (setq f (strcat "H:/coding/一键改宋体/One-click-Song-style/output/gb2312/parts/part" (itoa i) ".lsp"))
    (princ (strcat "\n== PART " (itoa i) "/12 == "))
    (setq r (load f "PART-LOAD-FAILED"))
    (if (= r "PART-LOAD-FAILED")
      (princ "<<< LOAD FAILED")
      (princ "ok")
    )
    (setq i (1+ i))
  )
  (princ "\n== BISECT DONE ==")
  (princ)
)
(princ "\nOCS 二分驱动已加载：执行 OCS_BISECT 逐部定位主文件错误区间。")
(princ)
