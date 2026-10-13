;;; 原生 CAD 只读检查入口
;;; 日期：2026-10-13
;;; 状态：待目标 CAD 执行
;;; 先加载 output/gb2312/one-click-simsun.lsp，再加载本文件的 GB2312 交付版。
;;; 旧 OCS_T01..T23 包含无效 API，已撤除；本文件不创建或改写图纸对象。
(vl-load-com)
(defun c:OCS_SCANNER ( / n)
  (setq n (OCS:SelfTest))
  (princ (strcat "\n扫描器失败项：" (itoa n)))
  (princ)
)
(defun c:OCS_ENV ( / name value)
  (princ (strcat "\nYJST 版本：" *OCS:Version*))
  (foreach name (list "ACADVER" "PRODUCT" "PLATFORM" "LISPSYS" "UNDOCTL")
    (setq value (vl-catch-all-apply 'getvar (list name)))
    (princ (strcat "\n" name " = "))
    (if (vl-catch-all-error-p value) (princ "不可读取") (princ value)))
  (princ "\n宋体文件：")
  (princ (OCS:ResolveSongFont))
  (princ)
)
(defun c:OCS_REPORT ()
  (if *OCS:LastReport* (OCS:Report *OCS:LastReport*) (princ "\n尚无 YJST 执行报告。"))
  (princ)
)
(princ "\n只读检查已加载：OCS_SCANNER / OCS_ENV / OCS_REPORT。")
(princ)
