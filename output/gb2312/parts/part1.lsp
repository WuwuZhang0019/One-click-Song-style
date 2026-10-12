;;; part1 - 主源码第 20-71 行（顶层 form 1-13，共 151 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART1
(vl-load-com)

;;; ------------------------- 全局状态 -------------------------
(setq *OCS:Version*      "0.1.0")
(setq *OCS:Plan*         nil)   ; 修改计划
(setq *OCS:Report*       nil)   ; 结构化报告
(setq *OCS:LastReport*   nil)   ; 最近一次运行（供调试/自动验收读取）
(setq *OCS:Running*      nil)   ; 重入保护
(setq *OCS:UndoMark*     nil)   ; 本次 Undo 分组标记
(setq *OCS:TempState*    nil)   ; 临时状态（锁定层、表格再生、OSMODE 等）
(setq *OCS:EscRequested* nil)   ; Esc/取消请求
(setq *OCS:FaultPoint*   nil)   ; 故障注入点（OCS:TestFault 用）

;;; ------------------------- 小工具 -------------------------

;; 字符串包含
(defun OCS:strContains (s sub / ls lsub)
  (setq ls (strlen s) lsub (strlen sub))
  (if (or (= lsub 0) (< ls lsub))
    (= s sub)
    (progn
      (setq i 1 result nil)
      (while (and (<= i (1+ (- ls lsub))) (not result))
        (if (= (substr s i lsub) sub) (setq result T))
        (setq i (1+ i))
      )
      result
    )
  )
)

;; 字符串中第 n 次出现 sub 的起始位置，找不到返回 nil
(defun OCS:strFindNth (s sub n / ls lsub i c)
  (setq ls (strlen s) lsub (strlen sub) i 1 c 0)
  (if (= lsub 0) nil
    (progn
      (while (and (<= i (1+ (- ls lsub))) (< c n))
        (if (= (substr s i lsub) sub) (setq c (1+ c)))
        (if (< c n) (setq i (1+ i)))
      )
      (if (= c n) i nil)
    )
  )
)

;; 是否为十六进制字符
(defun OCS:isHexChar (ch)
  (and (= (strlen ch) 1)
       (or (and (>= ch "0") (<= ch "9"))
           (and (>= ch "a") (<= ch "f"))
           (and (>= ch "A") (<= ch "F"))))
)
(princ "\nOK-PART1 lines 20-71")
(princ)
