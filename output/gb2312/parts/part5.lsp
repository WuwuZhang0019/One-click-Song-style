;;; part5 - 主源码第 679-917 行（顶层 form 57-70，共 159 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART5
(defun OCS:fontFileSource ( pair )
  (if (OCS:consp pair) (cadr pair) pair)
)

;; 在临时样式上验证写入/读回
(defun OCS:verifyFontWrite (res / doc name ent o r f bf old1071)
  (setq doc (OCS:activeDoc))
  (if (not doc)
    (setq res (OCS:addProblem res "error" "无法获取活动文档（ActiveX 不可用）"))
    (progn
      (setq name (OCS:tempStyleName))
      (OCS:deleteStyleIfExists name)
      (setq r (vl-catch-all-apply 'vla-AddTextStyle
                (list doc name (OCS:styleBaseFont) "vlax-true")))
      (if (vl-catch-all-error-p r)
        (setq res (OCS:addProblem res "error"
                    (strcat "创建试验文字样式失败：" (vl-catch-all-error-message r))))
        (progn
          (setq ent (tblobjname "STYLE" name))
          (if (not ent)
            (setq res (OCS:addProblem res "error" "试验文字样式创建后未找到 STYLE 记录"))
            (progn
              (setq o (vlax-ename->vla-object ent))
              ;; FontFile 写入（先文件名）
              (setq f (OCS:getVal res "fontFile"))
              (setq bf (if (OCS:consp f) (cadr f) f))
              (setq r (vl-catch-all-apply 'vla-put-FontFile (list o bf)))
              (if (vl-catch-all-error-p r)
                (progn
                  ;; 名称失败 → 绝对路径
                  (setq r (vl-catch-all-apply 'vla-put-FontFile (list o (car f))))
                  (if (vl-catch-all-error-p r)
                    (setq res (OCS:addProblem res "error"
                      (strcat "FontFile 写入失败：" (vl-catch-all-error-message r))))
                    (progn
                      (setq res (OCS:putPair res "fontFileSource" (strcat (car f) " (绝对路径回退)")))
                    ))
                )
              )
              ;; SetFont（字体族名 + 字符集 + pitch/family）
              (if (not (OCS:hasError res))
                (progn
                  (setq r (vl-catch-all-apply 'vla-SetFont
                    (list o "SimSun" "vlax-false" "vlax-false"
                          (OCS:getVal res "charSet")
                          (OCS:getVal res "pitchFamily"))))
                  (if (vl-catch-all-error-p r)
                    (setq res (OCS:addProblem res "error"
                      (strcat "SetFont(SimSun) 失败：" (vl-catch-all-error-message r))))
                  )
                )
              )
              ;; 写入后立即读回验证：FontFile 与 LastFontFile
              (if (not (OCS:hasError res))
                (progn
                  (setq r (vl-catch-all-apply 'vla-get-FontFile (list o)))
                  (if (or (vl-catch-all-error-p r) (= r ""))
                    (setq res (OCS:addProblem res "error" "FontFile 读回为空，字体未被 CAD 解析"))
                    (setq res (OCS:putPair res "fontFileReadback" r))
                  )
                )
              )
              ;; 大字体清空验证（STYLE DXF 组码 4）
              (if (not (OCS:hasError res))
                (setq res (OCS:verifyBigFontClear res ent name))
              )
              ;; 记录写入顺序证据
              (setq res (OCS:putPair res "writeOrder" "FontFile → SetFont → 大字体清空(组码4) → 读回"))
              ;; 删除试验样式
              (OCS:deleteStyleIfExists name)
            )
          )
        )
      )
    )
  )
  res
)

(defun OCS:hasError (res / p)
  (setq p (assoc "problem" res))
  ;; 扫描列表中是否有 :error
  (OCS:findError res)
)
(defun OCS:findError (res / found)
  (setq found nil)
  (foreach item res
    (if (and (OCS:consp item) (equal (car item) "problem")
             (OCS:consp (cdr item)) (equal (cadr item) "error"))
      (setq found T)
    )
  )
  found
)

(defun OCS:tempStyleName ()
  "OCS_TMP_VERIFY_STYLE"
)

(defun OCS:styleBaseFont ()
  ;; 样式基字体使用普通 txt，若不可用退回 romans；与目标字体无关
  (if (findfile "txt.shx") "txt.shx" (if (findfile "romans.shx") "romans.shx" "simplex.shx"))
)

(defun OCS:deleteStyleIfExists (name / ent)
  (setq ent (tblobjname "STYLE" name))
  (if ent
    (vl-catch-all-apply 'entdel (list ent))
  )
)

;; 大字体清空验证：按方案“通过 tblobjname + entget 定位 STYLE，
;; 将 DXF 组码 4 设为空，再用 entmod 写回；顺序与读回由 S01 验证”
(defun OCS:verifyBigFontClear (res ent name / e r v4)
  ;; 先写入一个大字体，确保组码 4 存在
  (setq e (entget ent))
  (setq r (OCS:ensureBigFont4 e "hz.shx"))
  (setq e (entget ent))
  (setq r (OCS:substDxf4 "" e))
  (if (OCS:errp r)
    (setq res (OCS:addProblem res "error"
                (strcat "大字体清空（DXF 组码 4 + entmod）失败：" (OCS:errmsg r))))
    (progn
      (setq e (entget (tblobjname "STYLE" name)))
      (setq v4 (OCS:assocd 4 e "MISSING"))
      (if (or (= v4 "MISSING") (= v4 ""))
        ;; 组码 4 已清空：再读回 COM 属性确认
        (setq res (OCS:putPair res "bigFontEmpty" T))
        (setq res (OCS:addProblem res "error"
                    (strcat "大字体清空后组码 4 读回非空：" v4)))
      )
    )
  )
  res
)

(defun OCS:ensureBigFont4 (e val / o r)
  (setq o (vlax-ename->vla-object (cdr (assoc -1 e))))
  (setq r (vl-catch-all-apply 'vla-put-BigFontFile (list o val)))
  (if (vl-catch-all-error-p r)
    ;; 文档不允许空字符串，但允许非空；写入失败则用 entmod 补组码 4
    (vl-catch-all-apply 'entmod (list (OCS:substDxf4 val e)))
  )
  T
)

;; 替换组码 4（无则追加），返回新 entlist；entmod 错误以 (:error . msg) 表示
(defun OCS:substDxf4 (val e / out found r)
  (setq out nil found nil)
  (foreach pair e
    (if (= (car pair) 4)
      (progn
        (setq found T)
        (setq out (append out (list (cons 4 val))))
      )
      (setq out (append out (list pair)))
    )
  )
  (if (not found)
    (setq out (append out (list (cons 4 val))))
  )
  (setq r (vl-catch-all-apply 'entmod (list out)))
  (if (vl-catch-all-error-p r)
    (cons "error" (vl-catch-all-error-message r))
    (if (null r) (cons "error" "entmod 返回 nil") out)
  )
)

;;; =====================================================================
;;; 环境预检 OCS:Preflight
;;; =====================================================================

(defun OCS:Preflight ( / res acadObj undoctl)
  (setq res (list "ok" nil))
  ;; 1. AutoLISP/Visual LISP/ActiveX（只探测，不执行任何命令）
  (setq res (OCS:putPair res "acadver" (getvar "ACADVER")))
  (setq res (OCS:putPair res "product"  (getvar "PRODUCT")))
  (setq res (OCS:putPair res "lispys"   (getvar "LISPSYS")))
  (setq res (OCS:putPair res "platform" (getvar "PLATFORM")))
  (setq acadObj (vl-catch-all-apply 'vlax-get-acad-object nil))
  (if (vl-catch-all-error-p acadObj)
    (setq res (OCS:addProblem res "error" "Visual LISP/ActiveX 不可用"))
  )
  ;; 2. 撤销可用性（UNDOCTL 位 0 = UNDO 开启）
  (setq undoctl (getvar "UNDOCTL"))
  (setq res (OCS:putPair res "undoctl" undoctl))
  (if (= 0 (logand undoctl 1))
    (setq res (OCS:addProblem res "error" "图纸撤销（UNDO）不可用，不能保证一次 U 恢复"))
  )
  ;; 3. 文档可写（锁定/只读）
  (setq res (OCS:checkDocWritable res))
  ;; 4. 字体解析
  (setq res (OCS:putPair res "font" (OCS:ResolveSongFont)))
  (if (OCS:findError (OCS:getVal res "font"))
    (setq res (OCS:addProblem res "error" "宋体字体解析失败（详见 :font）"))
  )
  ;; 5. 关键接口存在性
  (setq res (OCS:checkInterfaces res))
  (setq res (OCS:putPair res "ok" (not (OCS:findError res))))
  res
)

(defun OCS:checkDocWritable (res / doc ro)
  (setq doc (OCS:activeDoc))
  (if (not doc)
    (OCS:addProblem res "error" "无法获取活动文档")
    (progn
      (setq ro (vl-catch-all-apply 'vla-get-ReadOnly (list doc)))
      ;; 只读降级为警告：部分克隆引擎（天正/浩辰内核）该属性存根恒返 TRUE，
      ;; 若图纸真只读，后续写入会被 vl-catch-all 拦截并走回滚，不会损坏图纸。
      (if (and (not (vl-catch-all-error-p ro)) ro)
        (OCS:addProblem res "warn" "文档报告为只读（引擎可能误报；写入失败将自动回滚）")
        res
      )
    )
  )
)

(defun OCS:checkInterfaces (res / doc)
  (setq doc (OCS:activeDoc))
  (if (not doc)
    (OCS:addProblem res "error" "ActiveX 文档不可用")
    (progn
      (if (not (OCS:methodOk doc 'vla-get-Blocks))
        (setq res (OCS:addProblem res "error" "Blocks 集合接口不可用")))
      res
    )
  )
)

(defun OCS:activeDoc ( / acad doc)
  (setq acad (vl-catch-all-apply 'vlax-get-acad-object nil))
  (if (vl-catch-all-error-p acad) nil
    (progn
      (setq doc (vl-catch-all-apply 'vla-get-ActiveDocument (list acad)))
      (if (vl-catch-all-error-p doc) nil doc)
    )
  )
)
(princ "\nOK-PART5 lines 679-917")
(princ)
