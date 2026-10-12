;;; part9 - 主源码第 1465-1718 行（顶层 form 105-117，共 151 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART9
(defun OCS:leaderAnnotation (e / r)
  (setq r (OCS:safeProp e 'Annotation))
  r
)

(defun OCS:readTable (host e / rows cols)
  (setq rows (OCS:safeProp e 'Rows)
        cols  (OCS:safeProp e 'Columns))
  (list :kind :table :obj e
        :rows rows :cols cols
        :styleName (OCS:safeProp e 'StyleName)
        :suppressed (OCS:safeProp e 'RegenerateTableSuppressed)))

(defun OCS:readTolerance (host e)
  (list :kind :tolerance :obj e
        :text (OCS:safeProp e 'Text)
        :styleName (OCS:safeProp e 'StyleName))
)

;;; 写回宿主
(defun OCS:WriteHost (host data / kind e)
  (setq kind (OCS:assocd :kind data (OCS:assocd :kind host))
        e (OCS:assocd :obj data (OCS:assocd :obj host nil)))
  (cond
    ((or (eq kind :text) (eq kind :mtext))
     (OCS:writeTextLike e data))
    ((or (eq kind :attrib) (eq kind :attdef))
     (OCS:writeAttr e data))
    ((eq kind :dim)
     (OCS:writeDim e data))
    ((eq kind :mleader)
     (OCS:writeMLeader e data))
    ((eq kind :leader)
     (OCS:writeLeader e data))
    ((eq kind :table)
     (OCS:writeTable e data))
    ((eq kind :tolerance)
     (OCS:writeTolerance e data))
    (T (list :ok nil :error "未知宿主类型"))
  )
)

(defun OCS:writeTextLike (e data / txt r before)
  (setq txt (OCS:assocd :text data nil))
  (if (null txt)
    (list :ok nil :error "无内容")
    (progn
      (setq before (OCS:hostSnapshot e))
      (setq r (vl-catch-all-apply 'vla-put-TextString (list e txt)))
      (if (vl-catch-all-error-p r)
        (list :ok nil :error (vl-catch-all-error-message r))
        (OCS:verifyHost e before (list :text txt))
      )
    )
  )
)

(defun OCS:writeAttr (e data / txt r before mt w)
  (setq txt (OCS:assocd :text data nil))
  (if (null txt)
    (list :ok nil :error "无内容")
    (progn
      (setq before (OCS:hostSnapshot e))
      (setq mt (OCS:safeProp e 'MTextAttribute))
      (if (equal mt :vlax-true)
        (progn
          (setq r (vl-catch-all-apply 'vla-put-MTextAttributeContent (list e txt)))
          (if (vl-catch-all-error-p r)
            (setq r (cons :error (vl-catch-all-error-message r)))
            (progn
              ;; 多行属性：按可用接口更新显示
              (setq r2 (vl-catch-all-apply 'vla-UpdateMTextAttribute (list e)))
              (if (vl-catch-all-error-p r2)
                (setq r (cons :error (strcat "UpdateMTextAttribute 失败：" (vl-catch-all-error-message r2))))
              )
            )
          )
        )
        (progn
          (setq r (vl-catch-all-apply 'vla-put-TextString (list e txt)))
          (if (vl-catch-all-error-p r)
            (setq r (cons :error (vl-catch-all-error-message r)))
          )
        )
      )
      (if (OCS:errp r)
        (list :ok nil :error (OCS:errmsg r))
        (OCS:verifyHost e before (list :text txt))
      )
    )
  )
)

(defun OCS:writeDim (e data / txt r before)
  (setq txt (OCS:assocd :text data nil))
  (if (null txt)
    (list :ok nil :error "无内容")
    (progn
      (setq before (OCS:hostSnapshot e))
      (setq r (vl-catch-all-apply 'vla-put-TextOverride (list e txt)))
      (if (vl-catch-all-error-p r)
        (list :ok nil :error (vl-catch-all-error-message r))
        (OCS:verifyHost e before (list :text txt))
      )
    )
  )
)

(defun OCS:writeMLeader (e data / txt r before)
  (setq txt (OCS:assocd :text data nil))
  (if (null txt)
    ;; 块内容：块内文字由块定义转换覆盖，无需改写
    (list :ok T :skip T)
    (progn
      (setq before (OCS:hostSnapshot e))
      (setq r (vl-catch-all-apply 'vla-put-TextString (list e txt)))
      (if (vl-catch-all-error-p r)
        (list :ok nil :error (vl-catch-all-error-message r))
        (OCS:verifyHost e before (list :text txt))
      )
    )
  )
)

(defun OCS:writeLeader (e data / ann r txt)
  ;; 关联注释对象单独处理（可能为 TEXT/MTEXT/块）
  (setq ann (OCS:assocd :annotation data nil))
  (if (null ann)
    (list :ok T :skip T)
    (progn
      (setq txt (OCS:assocd :text data nil))
      (if (null txt)
        (list :ok T :skip T)
        (progn
          (setq before (OCS:hostSnapshot ann))
          (setq r (vl-catch-all-apply 'vla-put-TextString (list ann txt)))
          (if (vl-catch-all-error-p r)
            (list :ok nil :error (vl-catch-all-error-message r))
            (OCS:verifyHost ann before (list :text txt))
          )
        )
      )
    )
  )
)

(defun OCS:writeTolerance (e data / txt r before)
  (setq txt (OCS:assocd :text data nil))
  (if (null txt)
    (list :ok T :skip T)
    (progn
      (setq before (OCS:hostSnapshot e))
      (setq r (vl-catch-all-apply 'vla-put-Text (list e txt)))
      (if (vl-catch-all-error-p r)
        (list :ok nil :error (vl-catch-all-error-message r))
        (OCS:verifyHost e before (list :text txt))
      )
    )
  )
)

;; 表格：保留数据语义（方案第 6、8 节）
;; - 临时抑制再生，结束时恢复
;; - 枚举行列与内容项（不假定只有 0 项）
;; - 字段/公式/数据链接不以显示值回写；仅普通文本参与字体指令替换
(defun OCS:writeTable (e data / rows cols r prev cnt)
  (setq rows (OCS:assocd :rows data nil)
        cols  (OCS:assocd :cols data nil))
  (if (or (null rows) (null cols))
    (list :ok nil :error "无法读取表格行列数")
    (progn
      ;; 记录原抑制状态并抑制
      (setq prev (OCS:safeProp e 'RegenerateTableSuppressed))
      (setq r (vl-catch-all-apply 'vla-put-RegenerateTableSuppressed (list e :vlax-true)))
      (if (vl-catch-all-error-p r)
        (setq r (cons :error (strcat "抑制表格再生失败：" (vl-catch-all-error-message r))))
        (progn
          (setq r (OCS:tableProcess e rows cols data))
          ;; 恢复原状态（必须）
          (setq r2 (vl-catch-all-apply 'vla-put-RegenerateTableSuppressed
                     (list e (if (equal prev :vlax-true) :vlax-true :vlax-false))))
          (if (vl-catch-all-error-p r2)
            (setq r (cons :error (strcat "恢复表格再生状态失败：" (vl-catch-all-error-message r2)))))
          (if (OCS:errp r)
            (list :ok nil :error (OCS:errmsg r))
            (list :ok T :contents (OCS:assocd :contents r 0))
          )
        )
      )
    )
  )
)

(defun OCS:tableProcess (e rows cols data / r row col content txt new n go errList)
  (setq n 0 row 0 errList nil)
  (while (< row rows)
    (setq col 0)
    (while (< col cols)
      ;; 枚举该单元格内容项：0..N-1。
      ;; 终点只由“确认越界”（OUT_OF_CONTENT / DISP_E_OVERFLOW）判定；
      ;; 一次普通读取失败、空字符串都不作为遍历终点，必须记录。
      (setq content 0)
      (setq go T)
      (while (and go (<= content 64))
        (setq r (OCS:tableGetText e row col content))
        (cond
          ((OCS:errp r)
           (if (= (OCS:assocd :code (OCS:errmsgList r) "") "OUT_OF_CONTENT")
             (setq go nil)                 ; 确认越界 → 该单元格枚举结束
             (progn                        ; 其他读取失败：记录并继续
               (setq errList (append errList
                             (list (list row col content (OCS:errmsg r)))))
               (setq content (1+ content))
             )
           )
          )
          ((null (car r))
           ;; 读到空串：不作为终点，继续下一内容项
           (setq content (1+ content))
          )
          (T
           (setq txt (car r))
           (if (> (strlen txt) 0)
             (progn
               (setq new (OCS:NormalizeFontRuns txt (OCS:fontTarget)))
               (if (and (> (OCS:assocd :changes new 0) 0)
                        (not (OCS:containsField txt)))
                 (progn
                   (setq r2 (OCS:tableSetText e row col content (OCS:assocd :text new txt)))
                   (if (OCS:errp r2)
                     (setq errList (append errList
                                 (list (list row col content (OCS:errmsg r2)))))
                     (setq n (1+ n))
                   )
                 )
               )
             )
           )
           (setq content (1+ content))
          )
        )
      )
      (setq col (1+ col))
    )
    (setq row (1+ row))
  )
  (list :contents n :errors errList)
)

;; tableGetText 返回 (cons :error (list :code .. :msg ..))
(defun OCS:errmsgList (r / lst)
  (setq lst (OCS:errmsg r))
  (if (listp lst) lst (list :msg lst))
)
(princ "\nOK-PART9 lines 1465-1718")
(princ)
