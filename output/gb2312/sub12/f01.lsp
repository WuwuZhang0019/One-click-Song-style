;;; sub12/f01 - 主源码第 2448-2455 行（part12 第 1 个顶层 form）
;;; 由 tools/build_diag.py 生成；加载成功打印 OK-F01
(defun OCS:TestFault (point)
  (if (and *OCS:FaultPoint* (= *OCS:FaultPoint* point))
    (progn
      (setq *OCS:FaultPoint* nil)
      (OCS:fail (strcat "OCS 故障注入：" point))
    )
  )
)
(princ "\nOK-F01 lines 2448-2455")
(princ)
