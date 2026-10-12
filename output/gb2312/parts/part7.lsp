;;; part7 - 主源码第 1090-1226 行（顶层 form 79-91，共 151 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART7
(defun OCS:knownClass (typ)
  (OCS:strContains typ "Text")
)

;; 类型 → 分类（DXF/ObjectName 映射）
(defun OCS:mapClass (typ / t)
  (setq t (OCS:lower typ))
  (cond
    ((or (= t "acad_text")   (= t "acdbtext"))          "text")
    ((or (= t "acad_mtext")  (= t "acdbmtext"))         "mtext")
    ((or (= t "acad_attribute") (= t "acdbattribute"))  "attrib")
    ((or (= t "acad_attributereference") (= t "acdbattributereference")) "attrib")
    ((or (= t "acad_attributedefinition") (= t "acdbattributedefinition")) "attdef")
    ((OCS:strContains t "dimension")                    "dim")
    ((OCS:strContains t "mleader")                      "mleader")
    ((OCS:strContains t "leader")                       "leader")
    ((OCS:strContains t "table")                        "table")
    ((OCS:strContains t "tolerance")                    "tolerance")
    ((or (= t "acad_blockreference") (= t "acdbblockreference")) "blockref")
    ((OCS:strContains t "wblock")                       "blockref")
    (T "other")
  )
)

;;; ---------------------------------------------------------------------
;;; 各宿主“读”：收集进计划（只读阶段）
;;; ---------------------------------------------------------------------

(defun OCS:collectTextHost (res doc e ctx handle typ / s r)
  (setq res (OCS:putPair res "entities" (1+ (OCS:getVal res "entities" 0))))
  (setq res (OCS:lstAppend res "hosts"
              (list "kind" (if (= (OCS:lower typ) "acdbmtext") "mtext" "text")
                    "obj" e "handle" handle "ctx" ctx "type" typ)))
  res
)

(defun OCS:collectAttrib (res doc e ctx handle typ / isAttdef)
  (setq res (OCS:putPair res "attribs" (1+ (OCS:getVal res "attribs" 0))))
  (setq res (OCS:lstAppend res "hosts"
              (list "kind" (if (OCS:strContains (OCS:lower typ) "definition") "attdef" "attrib")
                    "obj" e "handle" handle "ctx" ctx "type" typ)))
  res
)

(defun OCS:collectDim (res doc e ctx handle typ)
  (OCS:lstAppend res "hosts"
    (list "kind" "dim" "obj" e "handle" handle "ctx" ctx "type" typ))
)

(defun OCS:collectMLeader (res doc e ctx handle typ)
  (OCS:lstAppend res "hosts"
    (list "kind" "mleader" "obj" e "handle" handle "ctx" ctx "type" typ))
)

(defun OCS:collectLeader (res doc e ctx handle typ)
  (OCS:lstAppend res "hosts"
    (list "kind" "leader" "obj" e "handle" handle "ctx" ctx "type" typ))
)

(defun OCS:collectTable (res doc e ctx handle typ)
  (OCS:lstAppend res "hosts"
    (list "kind" "table" "obj" e "handle" handle "ctx" ctx "type" typ))
)

(defun OCS:collectTolerance (res doc e ctx handle typ)
  (OCS:lstAppend res "hosts"
    (list "kind" "tolerance" "obj" e "handle" handle "ctx" ctx "type" typ))
)

;; 块引用：额外处理属性实例（GetAttributes / GetConstantAttributes）
(defun OCS:collectBlockRef (res doc e ctx handle typ / attrs consts)
  (setq res (OCS:putPair res "entities" (1+ (OCS:getVal res "entities" 0))))
  (setq res (OCS:lstAppend res "hosts"
              (list "kind" "blockref" "obj" e "handle" handle "ctx" ctx "type" typ)))
  ;; 属性实例
  (setq attrs (vl-catch-all-apply 'vla-GetAttributes (list e)))
  (if (and (not (vl-catch-all-error-p attrs)) attrs)
    (foreach a (OCS:variantToList attrs)
      (setq res (OCS:collectAttrib res doc a ctx (OCS:safeProp a 'Handle)
                                    (OCS:safeProp a 'ObjectName)))
    )
  )
  (setq consts (vl-catch-all-apply 'vla-GetConstantAttributes (list e)))
  (if (and (not (vl-catch-all-error-p consts)) consts)
    (foreach a (OCS:variantToList consts)
      (setq res (OCS:collectAttrib res doc a ctx (OCS:safeProp a 'Handle)
                                    (OCS:safeProp a 'ObjectName)))
    )
  )
  res
)

;;; =====================================================================
;;; 安全 COM 访问
;;; =====================================================================

(defun OCS:safeProp (obj prop / r)
  (if (null obj) nil
    (progn
      (setq r (vl-catch-all-apply (read (strcat "vla-get-" (vl-symbol-name prop))) (list obj)))
      (if (vl-catch-all-error-p r) nil r)
    )
  )
)

(defun OCS:safeMethod (obj meth args / r)
  (if (null obj) (cons "error" "nil object")
    (progn
      (setq r (vl-catch-all-apply (read (strcat "vla-" (vl-symbol-name meth))) (cons obj args)))
      (if (vl-catch-all-error-p r)
        (cons "error" (vl-catch-all-error-message r))
        r
      )
    )
  )
)

;; Variant/SafeArray 解包（64 位 ObjectID 不转 32 位整数）
(defun OCS:variantToList (v / r)
  (cond
    ((null v) nil)
    ((listp v) v)
    (T
     (setq r (vl-catch-all-apply 'vlax-safearray->list (list v)))
     (if (vl-catch-all-error-p r)
       ;; 标量 Variant
       (progn
         (setq r2 (vl-catch-all-apply 'vlax-variant-value (list v)))
         (if (vl-catch-all-error-p r2) nil
           (if (listp r2) r2 (list r2))
         )
       )
       r
     )
    )
  )
)
(princ "\nOK-PART7 lines 1090-1226")
(princ)
