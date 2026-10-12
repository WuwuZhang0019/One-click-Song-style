;;; part11 - 主源码第 1872-2185 行（顶层 form 131-143，共 151 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART11
(defun OCS:reportSet (report pairs / out updated)
  (setq out nil)
  (foreach pair pairs
    (setq updated nil out nil)
    (foreach item report
      (if (and (consp item) (equal (car item) (car pair)) (not updated))
        (progn (setq out (append out (list pair))) (setq updated T))
        (setq out (append out (list item)))
      )
    )
    (if (not updated) (setq out (append out (list pair))))
    (setq report out)
  )
  report
)

(defun OCS:problemsOf (res / out)
  (setq out nil)
  (foreach item res
    (if (and (consp item) (equal (car item) "problem")
             (consp (cdr item)) (equal (cadr item) "error"))
      (setq out (append out (list (caddr item))))
    )
  )
  ;; 字体解析中的问题
  (foreach item (OCS:getVal res "font" nil)
    (if (and (consp item) (equal (car item) "problem")
             (consp (cdr item)) (equal (cadr item) "error"))
      (setq out (append out (list (caddr item))))
    )
  )
  out
)

;;; =====================================================================
;;; 再生与读回 OCS:VerifyDrawing
;;; =====================================================================

(defun OCS:VerifyDrawing ( / doc r)
  (setq doc (OCS:activeDoc))
  (if (not doc)
    (list "ok" nil "error" "无法获取活动文档")
    (progn
      (setq r (vl-catch-all-apply 'vla-Regen (list doc 1))) ; acAllViewports
      (if (vl-catch-all-error-p r)
        (list "ok" nil "error" (strcat "再生失败：" (vl-catch-all-error-message r)))
        (OCS:readbackStyles)
      )
    )
  )
)

;; 样式读回：字体族为宋体、大字体为空、原参数一致
(defun OCS:readbackStyles ( / ok details st ent e)
  (setq ok T details nil)
  (foreach st (OCS:assocd "styles" *OCS:Plan* nil)
    (setq ent (tblobjname "STYLE" (OCS:assocd "name" st "")))
    (if ent
      (progn
        (setq e (entget ent))
        (if (/= "" (OCS:assocd 4 e ""))
          (progn (setq ok nil)
                 (setq details (append details
                   (list (list "BIGFONT_NOT_EMPTY" (OCS:assocd 2 e "")))))))
        (if (OCS:assocd "before" st nil)
          (if (not (OCS:styleReadbackOk (OCS:assocd "before" st nil)
                                         (OCS:styleSnapshot ent)))
            (progn (setq ok nil)
                   (setq details (append details
                     (list (list "PARAM_CHANGED" (OCS:assocd 2 e "")))))))
        )
      )
      (progn (setq ok nil)
             (setq details (append details
               (list (list "STYLE_MISSING" (OCS:assocd "name" st ""))))))
    )
  )
  (list "ok" ok "details" details)
)

;;; =====================================================================
;;; 回滚 OCS:Rollback（仅回滚本次操作）
;;; 回滚只作用于本次命令建立的 Undo 分组：结束分组后执行一次撤销，
;;; 绝不无条件 UNDO Back 撤销用户上一条命令。
;;; =====================================================================

(defun OCS:Rollback ( / r ok)
  (setq ok T)
  ;; 结束本次 Undo 分组（把全部写入归入一组）
  (OCS:endUndoGroup)
  ;; 仅撤销本次分组
  (setq r (vl-catch-all-apply 'command (list "_.U")))
  (if (or (vl-catch-all-error-p r) (null r))
    (setq ok nil)
  )
  ;; 恢复临时状态
  (if (not (OCS:restoreTempState))
    (setq ok nil)
  )
  ;; 回滚后读回核对（样式应回到转换前状态）
  (if (not (OCS:rollbackReadbackOk))
    (setq ok nil)
  )
  ok
)

;; 回滚后读回：本次计划中的样式不得残留空大字体之外的转换痕迹
(defun OCS:rollbackReadbackOk ( / ok st ent e)
  (setq ok T)
  (foreach st (OCS:assocd "styles" *OCS:Plan* nil)
    (setq ent (tblobjname "STYLE" (OCS:assocd "name" st "")))
    (if ent
      (progn
        (setq e (entget ent))
        ;; 若转换前该样式有大字体，回滚后应恢复
        (if (OCS:assocd "bigFontBefore" st nil)
          (if (/= (OCS:assocd 4 e "") (OCS:assocd "bigFontBefore" st ""))
            (setq ok nil)
          )
        )
      )
    )
  )
  ok
)

(defun OCS:endUndoGroup ( / )
  (if *OCS:UndoMark*
    (progn
      (vl-catch-all-apply 'vla-EndUndoMark
        (list (vla-get-ActiveDocument (vlax-get-acad-object))))
      (setq *OCS:UndoMark* nil)
    )
  )
  T
)

(defun OCS:restoreTempState ( / ok item lay)
  (setq ok T)
  ;; 恢复临时解锁的图层（原锁定状态）
  (foreach item *OCS:TempState*
    (if (and (consp item) (equal (car item) "layer"))
      (progn
        (setq lay (OCS:assocd "obj" item nil))
        (if lay
          (progn
            (setq r (vl-catch-all-apply 'vla-put-Lock (list lay "vlax-true")))
            (if (vl-catch-all-error-p r) (setq ok nil))
          )
        )
      )
    )
  )
  ;; 表格抑制状态已在各表处理中恢复；此处兜底清空
  (setq *OCS:TempState* nil)
  ok
)

;;; =====================================================================
;;; 报告 OCS:Report
;;; =====================================================================

(defun OCS:Report (report / f)
  (setq *OCS:LastReport* report)
  (setq *OCS:Report* report)
  ;; 中文命令行摘要
  (princ "\n")
  (princ (strcat "\n==== 一键统一宋体（YJST）===="))
  (princ (strcat "\n状态：" (OCS:assocd "status" report "?")))
  (princ (strcat "\n图纸：" (OCS:assocd "dwg" report "?")))
  (princ (strcat "\nCAD 版本：" (OCS:assocd "cadver" report "?")))
  (princ (strcat "\n目标字体族：" (OCS:assocd "family" report "SimSun")))
  (princ (strcat "\n扫描文字样式：" (itoa (OCS:assocd "stylesScanned" report 0))
                 "　修改：" (itoa (OCS:assocd "stylesModified" report 0))
                 "　外参依赖跳过：" (itoa (OCS:assocd "stylesXref" report 0))
                 "　形文件跳过：" (itoa (OCS:assocd "stylesShape" report 0))))
  (princ (strcat "\n扫描文字宿主：" (itoa (OCS:assocd "hostsScanned" report 0))
                 "　修改字体段：" (itoa (OCS:assocd "fontRunsChanged" report 0))
                 "　属性实例：" (itoa (OCS:assocd "attribs" report 0))
                 "　表格内容项：" (itoa (OCS:assocd "tableContents" report 0))))
  (princ (strcat "\n扫描块定义：" (itoa (OCS:assocd "blocks" report 0))
                 "　外参块跳过：" (itoa (OCS:assocd "xrefBlocks" report 0))
                 "　匿名显示块：" (itoa (OCS:assocd "displayBlocks" report 0))))
  (princ (strcat "\n专业对象未覆盖：" (itoa (OCS:assocd "uncovered" report 0))
                 "　错误：" (itoa (OCS:assocd "errors" report 0))
                 "　恢复失败：" (itoa (OCS:assocd "recoverFailed" report 0))))
  (if (OCS:assocd "errorDetail" report nil)
    (progn
      (princ "\n错误明细：")
      (foreach d (OCS:assocd "errorDetail" report nil)
        (princ (strcat "\n  " (OCS:fmt d))))
    )
  )
  (if (OCS:assocd "uncoveredDetail" report nil)
    (progn
      (princ "\n未覆盖明细（句柄/位置）：")
      (foreach d (OCS:assocd "uncoveredDetail" report nil)
        (princ (strcat "\n  " (OCS:fmt d))))
    )
  )
  (princ (strcat "\n详细记录：*OCS:LastReport*"))
  (princ)
  report
)

(defun OCS:fmt (x / out)
  (cond
    ((stringp x) x)
    ((numberp x) (rtos x 2 6))
    ((null x) "nil")
    ((listp x)
     (setq out "")
     (foreach i x
       (if (= out "") (setq out (OCS:fmt i))
         (setq out (strcat out " | " (OCS:fmt i)))))
     (strcat "(" out ")"))
    (T (vl-symbol-name x))
  )
)

;;; =====================================================================
;;; 用户命令 c:YJST：方案第 8 节流程
;;; =====================================================================

(defun c:YJST ( / )
  (if *OCS:Running*
    (princ "\nYJST：上一次运行尚未结束（重入被拒绝）。")
    (progn
      (setq *OCS:Running* T
            *OCS:EscRequested* nil
            *OCS:TempState* nil
            *OCS:UndoMark* nil)
      (OCS:mainFlow)
      (setq *OCS:Running* nil)
    )
  )
  (princ)
)

(defun OCS:mainFlow ( / report pre plan r okUndo)
  (setq *OCS:EscRequested* nil)
  ;; ---- 1) 预检（业务写入之前的一切检查） ----
  (setq pre (vl-catch-all-apply 'OCS:Preflight nil))
  (cond
    ((vl-catch-all-error-p pre)
     ;; 预检本身异常 → 未写入任何数据
     (setq report (OCS:makeReport "预检失败"))
     (setq report (OCS:appendErrors report
                     (list (vl-catch-all-error-message pre))))
     (OCS:Report report)
    )
    ((not (OCS:getVal pre "ok" nil))
     (setq report (OCS:makeReport "预检失败"))
     (setq report (OCS:appendErrors report (OCS:problemsOf pre)))
     (OCS:Report report)
    )
    (T
     ;; ---- 2) 扫描并生成修改计划（只读阶段） ----
     (setq plan (vl-catch-all-apply 'OCS:BuildPlan nil))
     (if (vl-catch-all-error-p plan)
       (progn
         (setq report (OCS:makeReport "预检失败"))
         (setq report (OCS:appendErrors report
                         (list (strcat "扫描计划失败："
                                       (vl-catch-all-error-message plan)))))
         (OCS:Report report)
       )
       (progn
         (setq *OCS:Plan* (OCS:putPair plan "font" (OCS:getVal pre "font")))
         ;; ---- 3) 开始 Undo 分组 ----
         (setq okUndo (OCS:beginUndoGroup))
         (if (not okUndo)
           (progn
             (setq report (OCS:makeReport "撤销不可用，未写入任何数据"))
             (OCS:Report report)
           )
           (progn
             ;; 写入阶段：任何未捕获错误都进入收尾/回滚（含 Esc）
             (setq report (vl-catch-all-apply 'OCS:executeWrites nil))
             (if (vl-catch-all-error-p report)
               (progn
                 (setq report (OCS:makeReport "失败已回滚"))
                 (setq report (OCS:appendErrors report
                                 (list (vl-catch-all-error-message report))))
                 ;; Esc 或未预期错误：恢复临时状态并回滚本次分组
                 (OCS:restoreTempState)
                 (if (not (OCS:Rollback))
                   (setq report (OCS:reportSet report (list (cons "recoverFailed" 1))))
                 )
                 ;; appendErrors 会把 :status 覆盖？不会：它只改 :errors/:errorDetail
                 (setq report (OCS:reportSet report (list (cons "status" "失败已回滚"))))
               )
             )
             (OCS:Report report)
           )
         )
       )
     )
    )
  )
  (princ)
)

(defun OCS:beginUndoGroup ( / doc r)
  (setq doc (OCS:activeDoc))
  (if (not doc) nil
    (progn
      (setq r (vl-catch-all-apply 'vla-StartUndoMark (list doc)))
      (if (vl-catch-all-error-p r) nil
        (progn (setq *OCS:UndoMark* T) T)
      )
    )
  )
)
(princ "\nOK-PART11 lines 1872-2185")
(princ)
