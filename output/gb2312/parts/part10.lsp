;;; part10 - 主源码第 1797-1975 行（顶层 form 127-140，共 159 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART10
(defun OCS:containsField (s)
  (and (OCS:strContains s "%<") (OCS:strContains s ">%"))
)

(defun OCS:fontTarget ()
  (OCS:getVal (OCS:getVal *OCS:Plan* "font") "font"
    (list (cons "family" "SimSun") (cons "charSet" 134)
          (cons "pitchFamily" 36) (cons "appendParams" T)))
)

;; 宿主快照（写后校验：非字体字段必须一致）
(defun OCS:hostSnapshot (e / kind)
  (list "height" (OCS:safeProp e 'Height)
        "width" (OCS:safeProp e 'Width)
        "rotation" (OCS:safeProp e 'Rotation)
        "layer" (OCS:safeProp e 'Layer)
        "color" (OCS:safeProp e 'Color)
        "styleName" (OCS:safeProp e 'StyleName)
        "tag" (OCS:safeProp e 'TagString)
        "value" (OCS:safeProp e 'TextString))
)

(defun OCS:verifyHost (e before expect / after ok)
  (setq after (OCS:hostSnapshot e) ok T)
  (foreach key (list "height" "width" "rotation" "layer" "color" "styleName" "tag")
    (if (not (equal (OCS:assocd key before nil) (OCS:assocd key after nil) 1e-9))
      (setq ok nil)
    )
  )
  (if (and (OCS:assocd "value" expect nil)
           (not (equal (OCS:assocd "value" expect nil) (OCS:assocd "value" after nil))))
    (setq ok nil)
  )
  (if ok (list "ok" T) (list "ok" nil "error" "写后校验：非字体数据发生变化"))
)

;;; =====================================================================
;;; 图层临时解锁（方案第 7 节）
;;; 仅临时解锁确有需要的本图图层，完成/异常时恢复；
;;; 关闭、冻结状态保持不动；外参图层保持原状。
;;; =====================================================================

(defun OCS:lockLayersNeeded ( / doc layers i lay name locked)
  (setq doc (OCS:activeDoc))
  (if (not doc) nil
    (progn
      (setq layers (vla-get-Layers doc) i 1)
      (while (<= i (vla-get-Count layers))
        (setq lay (OCS:safeItem layers i))
        (if lay
          (progn
            (setq name (OCS:safeProp lay 'Name)
                  locked (OCS:safeProp lay 'Lock))
            (if (and name (equal locked "vlax-true")
                     (not (OCS:isXrefLayer name)))
              (setq *OCS:TempState*
                    (append *OCS:TempState*
                            (list (list "layer" name "obj" lay))))
            )
          )
        )
        (setq i (1+ i))
      )
      *OCS:TempState*
    )
  )
)

(defun OCS:isXrefLayer (name)
  (OCS:strContains name "|")
)

(defun OCS:unlockTempLayers ( / item)
  (foreach item *OCS:TempState*
    (if (and (OCS:consp item) (equal (car item) "layer"))
      (vl-catch-all-apply 'vla-put-Lock (list (OCS:assocd "obj" item nil) "vlax-false"))
    )
  )
)

(defun OCS:restoreTempLayers ( / item)
  (foreach item *OCS:TempState*
    (if (and (OCS:consp item) (equal (car item) "layer"))
      (vl-catch-all-apply 'vla-put-Lock (list (OCS:assocd "obj" item nil) "vlax-true"))
    )
  )
)

;;; =====================================================================
;;; 报告构造辅助
;;; =====================================================================

(defun OCS:makeReport (status)
  (list "status" (if status status "进行中")
        "errors" 0
        "errorDetail" nil
        "uncovered" 0
        "uncoveredDetail" nil
        "recoverFailed" 0
        "stylesScanned" 0 "stylesModified" 0 "stylesXref" 0 "stylesShape" 0
        "hostsScanned" 0 "fontRunsChanged" 0 "attribs" 0 "tableContents" 0
        "blocks" 0 "xrefBlocks" 0 "displayBlocks" 0
        "dwg" (getvar "DWGPREFIX")
        "cadver" (getvar "ACADVER")
        "family" "SimSun")
)

(defun OCS:appendError (report where msg / errs detail)
  (setq errs  (1+ (OCS:assocd "errors" report 0))
        detail (append (OCS:assocd "errorDetail" report nil)
                       (list (list where msg))))
  (OCS:reportSet report
    (list (cons "errors" errs) (cons "errorDetail" detail))
  )
)

(defun OCS:appendErrors (report msgs / errs detail)
  (setq errs (+ (OCS:assocd "errors" report 0) (length msgs))
        detail (OCS:assocd "errorDetail" report nil))
  (foreach m msgs
    (setq detail (append detail (list (list "PREFLIGHT" m))))
  )
  (OCS:reportSet report
    (list (cons "errors" errs) (cons "errorDetail" detail))
  )
)

;; 用新值替换 plist 中已存在的键（不产生重复键）
(defun OCS:reportSet (report pairs / out updated)
  (setq out nil)
  (foreach pair pairs
    (setq updated nil out nil)
    (foreach item report
      (if (and (OCS:consp item) (equal (car item) (car pair)) (not updated))
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
    (if (and (OCS:consp item) (equal (car item) "problem")
             (OCS:consp (cdr item)) (equal (cadr item) "error"))
      (setq out (append out (list (caddr item))))
    )
  )
  ;; 字体解析中的问题
  (foreach item (OCS:getVal res "font" nil)
    (if (and (OCS:consp item) (equal (car item) "problem")
             (OCS:consp (cdr item)) (equal (cadr item) "error"))
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
(princ "\nOK-PART10 lines 1797-1975")
(princ)
