;;; part10 - 主源码第 1720-1869 行（顶层 form 118-130，共 151 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART10
(defun OCS:tableGetText (e row col content / r msg)
  (setq r (vl-catch-all-apply 'vla-GetTextString (list e row col content)))
  (cond
    ((vl-catch-all-error-p r)
     (setq msg (vl-catch-all-error-message r))
     (cons :error
           (list :code (if (or (OCS:strContains msg "8002000B")
                               (OCS:strContains msg "0x8002000B")
                               (OCS:strContains msg "超出")
                               (OCS:strContains msg "index"))
                           "OUT_OF_CONTENT" "READ_FAIL")
                 :msg msg)))
    (T (list r))
  )
)

(defun OCS:tableSetText (e row col content txt / r)
  (setq r (vl-catch-all-apply 'vla-SetTextString (list e row col content txt)))
  (if (vl-catch-all-error-p r)
    (cons :error (vl-catch-all-error-message r))
    T
  )
)

(defun OCS:containsField (s)
  (and (OCS:strContains s "%<") (OCS:strContains s ">%"))
)

(defun OCS:fontTarget ()
  (OCS:getVal (OCS:getVal *OCS:Plan* :font) :font
    (list (cons :family "SimSun") (cons :charSet 134)
          (cons :pitchFamily 36) (cons :appendParams T)))
)

;; 宿主快照（写后校验：非字体字段必须一致）
(defun OCS:hostSnapshot (e / kind)
  (list :height (OCS:safeProp e 'Height)
        :width (OCS:safeProp e 'Width)
        :rotation (OCS:safeProp e 'Rotation)
        :layer (OCS:safeProp e 'Layer)
        :color (OCS:safeProp e 'Color)
        :styleName (OCS:safeProp e 'StyleName)
        :tag (OCS:safeProp e 'TagString)
        :value (OCS:safeProp e 'TextString))
)

(defun OCS:verifyHost (e before expect / after ok)
  (setq after (OCS:hostSnapshot e) ok T)
  (foreach key (list :height :width :rotation :layer :color :styleName :tag)
    (if (not (equal (OCS:assocd key before nil) (OCS:assocd key after nil) 1e-9))
      (setq ok nil)
    )
  )
  (if (and (OCS:assocd :value expect nil)
           (not (equal (OCS:assocd :value expect nil) (OCS:assocd :value after nil))))
    (setq ok nil)
  )
  (if ok (list :ok T) (list :ok nil :error "写后校验：非字体数据发生变化"))
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
            (if (and name (equal locked :vlax-true)
                     (not (OCS:isXrefLayer name)))
              (setq *OCS:TempState*
                    (append *OCS:TempState*
                            (list (list :layer name :obj lay))))
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
    (if (and (consp item) (eq (car item) :layer))
      (vl-catch-all-apply 'vla-put-Lock (list (OCS:assocd :obj item nil) :vlax-false))
    )
  )
)

(defun OCS:restoreTempLayers ( / item)
  (foreach item *OCS:TempState*
    (if (and (consp item) (eq (car item) :layer))
      (vl-catch-all-apply 'vla-put-Lock (list (OCS:assocd :obj item nil) :vlax-true))
    )
  )
)

;;; =====================================================================
;;; 报告构造辅助
;;; =====================================================================

(defun OCS:makeReport (status)
  (list :status (if status status "进行中")
        :errors 0
        :errorDetail nil
        :uncovered 0
        :uncoveredDetail nil
        :recoverFailed 0
        :stylesScanned 0 :stylesModified 0 :stylesXref 0 :stylesShape 0
        :hostsScanned 0 :fontRunsChanged 0 :attribs 0 :tableContents 0
        :blocks 0 :xrefBlocks 0 :displayBlocks 0
        :dwg (getvar "DWGPREFIX")
        :cadver (getvar "ACADVER")
        :family "SimSun")
)

(defun OCS:appendError (report where msg / errs detail)
  (setq errs  (1+ (OCS:assocd :errors report 0))
        detail (append (OCS:assocd :errorDetail report nil)
                       (list (list where msg))))
  (OCS:reportSet report
    (list (cons :errors errs) (cons :errorDetail detail))
  )
)

(defun OCS:appendErrors (report msgs / errs detail)
  (setq errs (+ (OCS:assocd :errors report 0) (length msgs))
        detail (OCS:assocd :errorDetail report nil))
  (foreach m msgs
    (setq detail (append detail (list (list "PREFLIGHT" m))))
  )
  (OCS:reportSet report
    (list (cons :errors errs) (cons :errorDetail detail))
  )
)
(princ "\nOK-PART10 lines 1720-1869")
(princ)
