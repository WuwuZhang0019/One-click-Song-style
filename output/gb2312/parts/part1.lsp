;;; part1 - 主源码第 20-79 行（顶层 form 1-14，共 159 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART1
(vl-load-com)

;;; =====================================================================
;;; 引擎兼容垫片：适配天正/浩辰等精简 LISP 引擎缺失的标准函数
;;; 已知缺失：consp、stringp、error；vlax-method-applicable-p 返 NIL
;;; 但方法实际可用（如 GetBlocks 接口检查返 NIL 但直接调用 OK）
;;; =====================================================================

;; consp：(and (listp x) (not (atom x)))
;;   原子（数/串/符号/T/nil）会被 atom 视为 T，正好让空表 () 通过，
;;   标准 AutoLISP 里空表是 nil（atom=nil=()），consp 返 nil，
;;   我们的实现 (and (listp nil) (not (atom nil))) = (and T (not T)) = nil，一致。
(defun OCS:consp (x)
  (and (listp x) (not (atom x)))
)

;; stringp：用 type 返回的符号判断。各引擎行为不一，先探测再缓存。
;; 探测方法：(type "x") 的返回值比较。标准 AutoLISP 返回 SYM一笔 STR。
;; 无 type 时回退到：不是数、不是符号、不是 nil、能 strlen 则当作字符串。
(setq *OCS:StrType* nil)
(if (not (boundp '*OCS:StrType*))
  (setq *OCS:StrType* nil))
;; 探测：求 (type "abc")，若返回符号 STR 则用 type 判别；否则用回退法。
(if (not *OCS:StrType*)
  (progn
    (setq *OCS:StrType* (vl-catch-all-apply 'type (list "abc")))
    (if (vl-catch-all-error-p *OCS:StrType*)
      (setq *OCS:StrType* nil))
  )
)
(defun OCS:stringp (x)
  (if *OCS:StrType*
    (equal (type x) *OCS:StrType*)
    (and (not (numberp x))
         (not (atom x))
         (not (listp x))))
)

;; error：用 (exit) 硬退（引擎无 error 函数时）
(defun OCS:fail (msg)
  (princ (strcat "\nOCS 错误：" msg))
  (exit)
)

;; vlax-method-applicable-p 在某些克隆引擎上返 NIL 但方法实际可用：
;; OCS:methodOk 用试调一空参列表替代：能调通即认为可用。
(defun OCS:methodOk (obj meth / r)
  (setq r (vl-catch-all-apply meth (list obj)))
  (not (vl-catch-all-error-p r))
)
;; 改写预检里的接口检查；it was: (if (not (vlax-method-applicable-p doc 'GetBlocks))
;;   (setq res (OCS:addProblem res "error" "Blocks 集合接口不可用")))

;;; ------------------------- 全局状态 -------------------------
(setq *OCS:Version*      "0.1.0")
(setq *OCS:Plan*         nil)   ; 修改计划
(setq *OCS:Report*       nil)   ; 结构化报告
(setq *OCS:LastReport*   nil)   ; 最近一次运行（供调试/自动验收读取）
(setq *OCS:Running*      nil)   ; 重入保护
(setq *OCS:UndoMark*     nil)   ; 本次 Undo 分组标记
(princ "\nOK-PART1 lines 20-79")
(princ)
