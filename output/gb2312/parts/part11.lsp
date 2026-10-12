;;; part11 - 主源码第 1978-2443 行（顶层 form 141-154，共 159 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART11
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
    (if (and (OCS:consp item) (equal (car item) "layer"))
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
    ((OCS:stringp x) x)
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

;;; 诊断命令 c:OCS_TEST：逐项跑预检步骤，精确定位哪一步挂了
(defun c:OCS_TEST ( / res acadObj undoctl doc ro font probs okv)
  (princ "\n==== OCS 预检分步诊断 ====")
  ;; 复刻 OCS:Preflight 每一步，逐步打印
  (setq res (list "ok" nil))
  (princ (strcat "\n[1] ACADVER = " (getvar "ACADVER")))
  (princ (strcat "\n[2] PRODUCT  = " (getvar "PRODUCT")))
  (princ (strcat "\n[3] LISPSYS  = " (vl-prin1-to-string (getvar "LISPSYS"))))
  (princ (strcat "\n[4] PLATFORM = " (getvar "PLATFORM")))
  (setq acadObj (vl-catch-all-apply 'vlax-get-acad-object nil))
  (if (vl-catch-all-error-p acadObj)
    (princ "\n[5] vlax-get-acad-object = ERROR: Visual LISP/ActiveX 不可用")
    (princ "\n[5] vlax-get-acad-object = OK")
  )
  (setq undoctl (getvar "UNDOCTL"))
  (princ (strcat "\n[6] UNDOCTL = " (itoa undoctl)))
  (if (= 0 (logand undoctl 1))
    (princ "\n[7] UNDO 检查 = 失败（撤销不可用）")
    (princ "\n[7] UNDO 检查 = OK")
  )
  (setq doc (vl-catch-all-apply 'vla-get-ActiveDocument (list acadObj)))
  (if (vl-catch-all-error-p doc)
    (princ "\n[8] ActiveDocument = ERROR")
    (progn
      (princ "\n[8] ActiveDocument = OK")
      (setq ro (vl-catch-all-apply 'vla-get-ReadOnly (list doc)))
      (if (vl-catch-all-error-p ro)
        (princ "\n[9] ReadOnly = ERROR（接口可能不存在）")
        (princ (strcat "\n[9] ReadOnly = " (if ro "TRUE(只读)" "FALSE(可写)")))
      )
    )
  )
  ;; 字体解析
  (setq font (vl-catch-all-apply 'OCS:ResolveSongFont nil))
  (if (vl-catch-all-error-p font)
    (princ (strcat "\n[10] ResolveSongFont = ERROR: " (vl-catch-all-error-message font)))
    (princ (strcat "\n[10] ResolveSongFont = " (vl-prin1-to-string font)))
  )
  ;; Blocks 接口
  (if (vl-catch-all-error-p doc)
    (princ "\n[11] GetBlocks = 跳过（无文档）")
    (progn
      (setq okv (vl-catch-all-apply 'vlax-method-applicable-p (list doc "GetBlocks")))
      (if (vl-catch-all-error-p okv)
        (princ "\n[11a] vlax-method-applicable-p(字符串) = ERROR")
        (princ (strcat "\n[11a] applicable-p \"GetBlocks\" = " (if okv "T" "NIL")))
      )
      (setq okv (vl-catch-all-apply 'vlax-method-applicable-p (list doc 'GetBlocks)))
      (if (vl-catch-all-error-p okv)
        (princ "\n[11b] vlax-method-applicable-p(符号) = ERROR")
        (princ (strcat "\n[11b] applicable-p 'GetBlocks = " (if okv "T" "NIL")))
      )
      (setq okv (vl-catch-all-apply 'vla-get-Blocks (list doc)))
      (if (vl-catch-all-error-p okv)
        (princ (strcat "\n[11c] vla-get-Blocks = ERROR: " (vl-catch-all-error-message okv)))
        (progn
          (princ "\n[11c] vla-get-Blocks = OK")
          (setq okv (vl-catch-all-apply 'vla-get-Count (list okv)))
          (if (vl-catch-all-error-p okv)
            (princ "\n[11d] vla-get-Count = ERROR")
            (princ (strcat "\n[11d] Blocks Count = " (itoa okv)))
          )
        )
      )
    )
  )
  (princ "\n==== 诊断结束；把以上输出发给开发 ====")
  (princ)
)

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

;; 执行写入与检查（含回滚路径）
(defun OCS:executeWrites ( / report stylesRes hostsRes verifyRes wrote)
  (setq report (OCS:makeReport nil))
  ;; 临时解锁
  (OCS:lockLayersNeeded)
  (OCS:unlockTempLayers)
  ;; 样式写入
  (setq stylesRes (OCS:applyAllStyles))
  (if (OCS:assocd "error" stylesRes nil)
    (setq report (OCS:appendError report "STYLE" (OCS:assocd "error" stylesRes ""))))
  ;; 内容写入
  (setq hostsRes (OCS:applyAllHosts))
  ;; 其余统计（report 中已预置同名键，必须替换而非追加）
  (setq report (OCS:reportSet report
                 (list
                   (cons "stylesScanned" (length (OCS:assocd "styles" *OCS:Plan* nil)))
                   (cons "stylesModified" (OCS:assocd "modified" stylesRes 0))
                   (cons "stylesXref" (length (OCS:assocd "xrefStyle" *OCS:Plan* nil)))
                   (cons "stylesShape" (length (OCS:assocd "shape" *OCS:Plan* nil)))
                   (cons "hostsScanned" (length (OCS:assocd "hosts" *OCS:Plan* nil)))
                   (cons "fontRunsChanged" (OCS:assocd "changes" hostsRes 0))
                   (cons "attribs" (OCS:assocd "attribs" (OCS:assocd "stats" *OCS:Plan*) 0))
                   (cons "blocks" (OCS:assocd "blocks" (OCS:assocd "stats" *OCS:Plan*) 0))
                   (cons "xrefBlocks" (OCS:assocd "xrefBlocks" (OCS:assocd "stats" *OCS:Plan*) 0))
                   (cons "displayBlocks" (OCS:assocd "displayBlocks" (OCS:assocd "stats" *OCS:Plan*) 0))
                   (cons "tableContents" (OCS:assocd "tableContents" hostsRes 0))
                   (cons "uncovered" (OCS:assocd "unknown" (OCS:assocd "stats" *OCS:Plan*) 0))
                   (cons "uncoveredDetail" (OCS:assocd "skipped" (OCS:assocd "stats" *OCS:Plan*) nil))
                 )))
  (if (OCS:assocd "error" hostsRes nil)
    (setq report (OCS:appendError report "HOST" (OCS:assocd "error" hostsRes ""))))
  ;; 临时状态恢复
  (OCS:restoreTempState)
  ;; 中途错误（写入失败/解析问题）→ 回滚本次业务写入
  (if (OCS:assocd "errors" report 0)
    (progn
      (setq report (OCS:reportSet report (list (cons "status" "失败已回滚"))))
      (if (not (OCS:Rollback))
        (setq report (OCS:reportSet report (list (cons "recoverFailed" 1))))
      )
    )
    (progn
      ;; 再生 + 读回
      (OCS:TestFault "regen-check")
      (setq verifyRes (OCS:VerifyDrawing))
      (if (not (OCS:assocd "ok" verifyRes T))
        (progn
          (setq report (OCS:appendError report "VERIFY" (OCS:assocd "error" verifyRes "")))
          ;; 读回不符 → 回滚本次修改
          (setq report (OCS:reportSet report (list (cons "status" "失败已回滚"))))
          (if (not (OCS:Rollback))
            (setq report (OCS:reportSet report (list (cons "recoverFailed" 1))))
          )
        )
        (progn
          (OCS:endUndoGroup)
          ;; 状态判定（方案第 12 节）
          (setq report (OCS:reportSet report
            (list (cons "status"
              (cond
                ((> (OCS:assocd "errors" report 0) 0) "失败已回滚")
                ((> (OCS:assocd "uncovered" report 0) 0) "部分完成")
                ((and (= 0 (OCS:assocd "stylesModified" report 0))
                      (= 0 (OCS:assocd "fontRunsChanged" report 0)))
                 "无需修改")
                (T "已完成")
              )))))
        )
      )
    )
  )
  (setq report (OCS:reportSet report
                 (list (cons "dwg" (getvar "DWGPREFIX"))
                       (cons "cadver" (getvar "ACADVER"))
                       (cons "family" "SimSun"))))
  report
)

(defun OCS:applyAllStyles ( / modified err)
  (setq modified 0 err nil)
  (foreach st (OCS:assocd "styles" *OCS:Plan* nil)
    (if (not err)
      (progn
        (OCS:TestFault "style-write")
        (setq r (OCS:ApplyStyle (OCS:activeDoc) st))
        (if (OCS:assocd "ok" r nil)
          (setq modified (1+ modified))
          (setq err (OCS:assocd "error" r "未知错误"))
        )
      )
    )
  )
  (list "modified" modified "error" err)
)

(defun OCS:applyAllHosts ( / changes tableContents err data new r)
  (setq changes 0 tableContents 0 err nil)
  (foreach host (OCS:assocd "hosts" *OCS:Plan* nil)
    (if (not err)
      (progn
        (setq data (OCS:ReadHost host))
        (if (OCS:assocd "error" data nil)
          (setq err (strcat (OCS:assocd "handle" host "?") ": " (OCS:assocd "error" data "")))
          (if (not (OCS:assocd "skip" data nil))
            (progn
              (setq new (OCS:NormalizeFontRuns (OCS:assocd "text" data "") (OCS:fontTarget)))
              (if (OCS:assocd "issues" new nil)
                (setq err (strcat (OCS:assocd "handle" host "?") ": 内容解析问题 "
                                   (OCS:fmt (OCS:assocd "issues" new nil))))
              )
              (if (and (not err) (> (OCS:assocd "changes" new 0) 0))
                (progn
                  (OCS:TestFault "content-write")
                  (setq data (OCS:putPair data "text" (OCS:assocd "text" new "")))
                  (setq r (OCS:WriteHost host data))
                  (if (OCS:assocd "ok" r nil)
                    (progn
                      (setq changes (+ changes (OCS:assocd "changes" new 0)))
                      (if (equal (OCS:assocd "kind" host) "table")
                        (setq tableContents (+ tableContents (OCS:assocd "contents" r 0)))
                      )
                    )
                    (setq err (strcat (OCS:assocd "handle" host "?") ": " (OCS:assocd "error" r "")))
                  )
                )
              )
            )
          )
        )
      )
    )
  )
  (list "changes" changes "tableContents" tableContents "error" err)
)
(princ "\nOK-PART11 lines 1978-2443")
(princ)
