;;; part8 - 主源码第 1232-1463 行（顶层 form 92-104，共 151 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART8
(defun OCS:BuildPlan ( / plan styles hosts)
  (setq styles (OCS:CollectStyles))
  (setq hosts   (OCS:CollectHosts))
  (setq plan (list
    :styles    (OCS:getVal styles :normal nil)
    :shape     (OCS:getVal styles :shape nil)
    :xrefStyle (OCS:getVal styles :xref nil)
    :hosts     (OCS:getVal hosts :hosts nil)
    :seen      (OCS:getVal hosts :seen nil)
    :stats     hosts
    :targets   nil      ; (kind obj handle ctx ...) 内容修改目标
    :issues    nil
  ))
  plan
)

;;; =====================================================================
;;; 应用样式修改 OCS:ApplyStyle
;;; =====================================================================

(defun OCS:ApplyStyle (doc st / name ent o r before after)
  (setq name (OCS:assocd :name st ""))
  (setq ent (tblobjname "STYLE" name))
  (if (not ent)
    (list :ok nil :name name :error "STYLE 记录未找到")
    (progn
      (setq o (vlax-ename->vla-object ent))
      (setq before (OCS:styleSnapshot ent))
      ;; 1) FontFile
      (setq r (OCS:safeMethod o 'FontFile nil))  ; 读
      (setq r (vl-catch-all-apply 'vla-put-FontFile
                (list o (OCS:styleTargetFontFile doc))))
      (if (vl-catch-all-error-p r)
        (list :ok nil :name name :error (strcat "FontFile 写入失败：" (vl-catch-all-error-message r)))
        (progn
          ;; 2) SetFont
          (setq r (vl-catch-all-apply 'vla-SetFont
                    (list o "SimSun" :vlax-false :vlax-false 134 36)))
          (if (vl-catch-all-error-p r)
            (list :ok nil :name name :error (strcat "SetFont 失败：" (vl-catch-all-error-message r)))
            (progn
              ;; 3) 大字体清空（组码 4）
              (setq r (OCS:clearBigFont ent name))
              (if (OCS:errp r)
                (list :ok nil :name name :error (strcat "大字体清空失败：" (OCS:errmsg r)))
                (progn
                  ;; 4) 读回验证
                  (setq after (OCS:styleSnapshot (tblobjname "STYLE" name)))
                  (if (not (OCS:styleReadbackOk before after))
                    (list :ok nil :name name :error "样式读回校验失败（非字体参数被改变）"
                          :before before :after after)
                    (list :ok T :name name :before before :after after)
                  )
                )
              )
            )
          )
        )
      )
    )
  )
)

(defun OCS:styleTargetFontFile (doc / f)
  (setq f (OCS:getVal (OCS:getVal *OCS:Plan* :font) :fontFile))
  (if (consp f) (cadr f) f)
)

;; 样式非字体参数快照（40/41/50/70/71 + 未知组码计数）
(defun OCS:styleSnapshot (ent / e out)
  (if (not ent) nil
    (progn
      (setq e (entget ent))
      (list
        :h     (OCS:assocd 5 e "")
        :name  (OCS:assocd 2 e "")
        :40    (OCS:assocd 40 e nil)
        :41    (OCS:assocd 41 e nil)
        :50    (OCS:assocd 50 e nil)
        :70    (OCS:assocd 70 e nil)
        :71    (OCS:assocd 71 e nil)
        :1071  (OCS:assocd 1071 e nil)
        :xdata (length (OCS:xdataKeys e))
      )
    )
  )
)

(defun OCS:xdataKeys (e / keys)
  (setq keys nil)
  (foreach pair e
    (if (and (consp pair) (numberp (car pair)) (>= (car pair) 1000))
      (setq keys (cons (car pair) keys))
    )
  )
  keys
)

(defun OCS:styleReadbackOk (before after / ok)
  (setq ok T)
  (foreach key (list :name :40 :41 :50 :70 :71 :1071 :xdata)
    (if (not (equal (OCS:assocd key before nil) (OCS:assocd key after nil) 1e-9))
      (setq ok nil)
    )
  )
  ok
)

;; 大字体清空 + 读回
(defun OCS:clearBigFont (ent name / e r e2 v)
  (setq e (entget ent))
  (if (not (assoc 4 e))
    T  ; 本就没有大字体
    (progn
      (setq r (OCS:substDxf4 "" e))
      (if (OCS:errp r) r
        (progn
          (setq e2 (entget (tblobjname "STYLE" name)))
          (setq v (OCS:assocd 4 e2 "MISSING"))
          (if (or (= v "MISSING") (= v ""))
            (progn
              ;; COM 读回
              (setq r (vl-catch-all-apply 'vla-get-BigFontFile
                        (list (vlax-ename->vla-object (tblobjname "STYLE" name)))))
              (if (vl-catch-all-error-p r)
                (cons :error "大字体 COM 读回失败")
                (if (= r "") T (cons :error (strcat "大字体读回非空：" r)))
              )
            )
            (cons :error (strcat "大字体读回非空：" v))
          )
        )
      )
    )
  )
)

;;; =====================================================================
;;; 宿主读写 OCS:ReadHost / OCS:WriteHost
;;; =====================================================================

;; 读取宿主内容与必须保留的数据 → plist
(defun OCS:ReadHost (host / kind e)
  (setq kind (OCS:assocd :kind host nil)
        e (OCS:assocd :obj host nil))
  (cond
    ((or (eq kind :text) (eq kind :mtext))
     (OCS:readTextLike host e))
    ((or (eq kind :attrib) (eq kind :attdef))
     (OCS:readAttr host e))
    ((eq kind :dim)
     (OCS:readDim host e))
    ((eq kind :mleader)
     (OCS:readMLeader host e))
    ((eq kind :leader)
     (OCS:readLeader host e))
    ((eq kind :table)
     (OCS:readTable host e))
    ((eq kind :tolerance)
     (OCS:readTolerance host e))
    ((eq kind :blockref)
     (list :kind kind :obj e :skip T))
    (T (list :kind kind :obj e :skip T))
  )
)

;; TEXT/MTEXT：完整原始内容
(defun OCS:readTextLike (host e / kind r txt)
  (setq kind (OCS:assocd :kind host))
  (setq r (vl-catch-all-apply 'vla-get-TextString (list e)))
  (if (vl-catch-all-error-p r)
    (list :kind kind :obj e :error (vl-catch-all-error-message r))
    (progn
      (setq txt r)
      ;; MTEXT 的完整原始格式：TextString 在 MTEXT 上返回原始格式串；
      ;; 长文本不分段读取（XDATA 组码 1 只是前 250 字符，不能作为来源）
      (list :kind kind :obj e :text txt
            :styleName (OCS:safeProp e 'StyleName)
            :height (OCS:safeProp e 'Height)
            :width (OCS:safeProp e 'Width)
            :rotation (OCS:safeProp e 'Rotation)
            :layer (OCS:safeProp e 'Layer)
            :color (OCS:safeProp e 'Color))
    )
  )
)

(defun OCS:readAttr (host e / kind mt)
  (setq kind (OCS:assocd :kind host))
  (setq mt (OCS:safeProp e 'MTextAttribute))
  (if (equal mt :vlax-true)
    (list :kind kind :obj e :multiline T
          :text (OCS:safeProp e 'MTextAttributeContent)
          :boundaryWidth (OCS:safeProp e 'MTextBoundaryWidth)
          :tag (OCS:safeProp e 'TagString)
          :value (OCS:safeProp e 'TextString)
          :styleName (OCS:safeProp e 'StyleName)
          :constant (OCS:safeProp e 'Constant))
    (list :kind kind :obj e :multiline nil
          :text (OCS:safeProp e 'TextString)
          :tag (OCS:safeProp e 'TagString)
          :styleName (OCS:safeProp e 'StyleName)
          :constant (OCS:safeProp e 'Constant))
  )
)

(defun OCS:readDim (host e / r)
  (list :kind :dim :obj e
        :textOverride (OCS:safeProp e 'TextOverride)
        :textString (OCS:safeProp e 'TextString)
        :styleName (OCS:safeProp e 'TextStyle)
        :measurement (OCS:safeProp e 'TextOverride)
        :rotation (OCS:safeProp e 'TextRotation)
        :height (OCS:safeProp e 'TextHeight))
)

(defun OCS:readMLeader (host e / r content)
  (setq r (OCS:safeProp e 'TextString))
  (if (not r)
    ;; 多重引线可能使用块内容：读取其块引用与属性
    (progn
      (setq content (OCS:safeProp e 'BlockRecordId))
      (list :kind :mleader :obj e :text nil :blockId content))
    (list :kind :mleader :obj e :text r :styleName (OCS:safeProp e 'TextStyle))
  )
)

(defun OCS:readLeader (host e / ann)
  ;; 普通引线的关联注释对象
  (setq ann (OCS:leaderAnnotation e))
  (list :kind :leader :obj e :annotation ann)
)
(princ "\nOK-PART8 lines 1232-1463")
(princ)
