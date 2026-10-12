;;; part5 - 主源码第 712-905 行（顶层 form 53-65，共 151 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART5
(defun OCS:findError (res / found)
  (setq found nil)
  (foreach item res
    (if (and (consp item) (equal (car item) "problem")
             (consp (cdr item)) (equal (cadr item) "error"))
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
      (if (and (not (vl-catch-all-error-p ro)) ro)
        (OCS:addProblem res "error" "当前图纸为只读，不能修改")
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
      (if (not (vlax-method-applicable-p doc 'GetBlocks))
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
(defun OCS:activeDoc* ()
  (vla-get-ActiveDocument (vlax-get-acad-object))
)

;;; =====================================================================
;;; 样式收集 OCS:CollectStyles
;;; 方案第 3 节：DXF 70 位 1 = 形文件记录，位 16 = 外参依赖；
;;; 不按名称含 "|" 判断；Standard 与注释性样式照常处理。
;;; =====================================================================

(defun OCS:CollectStyles ( / res ent lst e flg name)
  (setq res (list "normal" nil "shape" nil "xref" nil "vertical" nil "count" 0))
  (setq ent (tblnext "STYLE" T))
  (while ent
    (setq flg (OCS:assocd 70 ent 0)
          name (OCS:assocd 2 ent ""))
    (cond
      ((/= 0 (logand flg 1))
       ;; 形文件记录（LOAD 请求）→ 跳过并分类记录
       (setq res (OCS:lstAppend res "shape" name))
      )
      ((/= 0 (logand flg 16))
       ;; 外部参照依赖记录 → 跳过并分类记录
       (setq res (OCS:lstAppend res "xref" name))
      )
      (T
       (setq res (OCS:lstAppend res "normal"
                  (list "name" name
                        "flags" flg
                        "vertical" (/= 0 (logand flg 4))
                        "annotative" (OCS:isAnnotativeStyle ent)
                        "bigFontBefore" (OCS:assocd 4 ent "")
                        "fontFileBefore" (OCS:assocd 3 ent "")
                        "dxf" ent)))
      )
    )
    (setq ent (tblnext "STYLE" nil))
  )
  (setq res (OCS:putPair res "count" (length (OCS:getVal res "normal"))))
  res
)
(princ "\nOK-PART5 lines 712-905")
(princ)
