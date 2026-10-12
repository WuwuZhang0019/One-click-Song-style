;;; sub12/f04 - 主源码第 2325-2332 行（part12 第 4 个顶层 form）
;;; 由 tools/build_diag.py 生成；加载成功打印 OK-F04
(defun OCS:TestFault (point)
  (if (and *OCS:FaultPoint* (= *OCS:FaultPoint* point))
    (progn
      (setq *OCS:FaultPoint* nil)
      (error (strcat "OCS 故障注入：" point))
    )
  )
)
(princ "\nOK-F04 lines 2325-2332")
(princ)
