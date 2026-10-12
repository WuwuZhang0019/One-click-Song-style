;;; part6 - 主源码第 907-1088 行（顶层 form 66-78，共 151 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART6
(defun OCS:lstAppend (res key val)
  (OCS:putPair res key (append (OCS:getVal res key nil) (list val)))
)

;; 注释性判断：组码 1071 不含注释位；注释性在组码 70 无位，
;; 通过扩展数据/对象模型的 Annotative 属性判断；此处用
;; entget 的 1071 之外，另查 (assoc 1071 ...) 不可靠 → 用对象接口。
(defun OCS:isAnnotativeStyle (ent / o r)
  (setq o (vlax-ename->vla-object ent))
  (setq r (vl-catch-all-apply 'vla-get-Annotative (list o)))
  (if (vl-catch-all-error-p r) nil
    (equal r :vlax-true)
  )
)

;;; =====================================================================
;;; 图块与宿主收集 OCS:CollectHosts
;;; 方案第 4 节：以 Blocks 集合为主入口；按句柄去重；
;;; 遇外参块停止进入；动态块同时扫描原始定义与匿名表示；
;;; 标注/表格等生成的匿名显示块按来源分类处理。
;;; =====================================================================

(defun OCS:CollectHosts ( / res doc blocks i blk)
  (setq res (list :blocks 0 :xrefBlocks 0 :displayBlocks 0
                  :entities 0 :attribs 0 :unknown 0
                  :blockList nil :skipped nil))
  (setq doc (OCS:activeDoc))
  (if (not doc)
    (OCS:addProblem res :error "无法获取活动文档")
    (progn
      (setq blocks (vla-get-Blocks doc))
      (setq i 1)
      (while (<= i (vla-get-Count blocks))
        (setq blk (OCS:safeItem blocks i))
        (if blk
          (setq res (OCS:collectBlock res doc blk))
        )
        (setq i (1+ i))
      )
      res
    )
  )
)

(defun OCS:safeItem (coll i / r)
  (setq r (vl-catch-all-apply 'vla-Item (list coll (1- i))))
  (if (vl-catch-all-error-p r) nil r)
)

(defun OCS:collectBlock (res doc blk / name isXref ownerH handle btype)
  (setq name (OCS:safeProp blk 'Name)
        handle (OCS:safeProp blk 'Handle))
  (if (not name)
    res
    (progn
      (setq isXref (OCS:safeProp blk 'IsXRef))
      ;; 匿名块分类：动态块表示(*D...)、标注/表格显示缓存(*U...)、其他
      (setq btype (OCS:classifyBlockName name))
      (cond
        ;; 外部参照块：停止进入，不跨外部数据库
        ((equal isXref :vlax-true)
         (setq res (OCS:putPair res :xrefBlocks (1+ (OCS:getVal res :xrefBlocks 0))))
         (setq res (OCS:lstAppend res :skipped (list "XREF_BLOCK" handle name)))
        )
        ((eq btype :display-cache)
         ;; 标注/表格等的显示缓存：交由其源宿主处理，不直接改写
         (setq res (OCS:putPair res :displayBlocks (1+ (OCS:getVal res :displayBlocks 0))))
         (setq res (OCS:lstAppend res :skipped (list "DISPLAY_CACHE" handle name)))
        )
        (T
         (setq res (OCS:putPair res :blocks (1+ (OCS:getVal res :blocks 0))))
         (setq res (OCS:lstAppend res :blockList (list :name name :handle handle :obj blk)))
         ;; 扫描块内实体
         (setq res (OCS:scanBlockContents res doc blk name handle))
        )
      )
      res
    )
  )
)

;; 匿名块来源分类（方案第 4 节第 6 条）
(defun OCS:classifyBlockName (name / n)
  (setq n (OCS:lower name))
  (cond
    ;; 动态块的匿名表示：*D12 这类
    ((and (>= (strlen n) 2) (= (substr n 1 2) "*d")) :dynamic-repr)
    ;; 标注/表格等显示缓存：*U12、*X12 这类（U=匿名块，X=…）
    ((and (>= (strlen n) 2) (= (substr n 1 2) "*u")) :display-cache)
    (T :named)
  )
)

(defun OCS:scanBlockContents (res doc blk bname bhandle / ents i e)
  (setq ents (vla-get-BlockEntities blk))
  (setq i 1)
  (while (<= i (vla-get-Count ents))
    (setq e (OCS:safeItem ents i))
    (if e (setq res (OCS:visitEntity res doc e (list :block bname bhandle))))
    (setq i (1+ i))
  )
  res
)

;; 实体访问（去重按句柄）
(defun OCS:visitEntity (res doc e ctx / typ handle seen)
  (setq typ (OCS:safeProp e 'ObjectName))
  (if (not typ)
    (progn
      (setq res (OCS:putPair res :unknown (1+ (OCS:getVal res :unknown 0))))
      (setq res (OCS:lstAppend res :skipped (list "UNKNOWN_OBJECT" "?" (OCS:ctxStr ctx))))
    )
    (progn
      (setq handle (OCS:safeProp e 'Handle))
      (setq seen (OCS:seenP res handle))
      (if (not seen)
        (progn
          (setq res (OCS:markSeen res handle))
          (setq res (OCS:handleEntity res doc e typ ctx handle))
        )
      )
      res
    )
  )
)

(defun OCS:ctxStr (ctx)
  (if (null ctx) "-"
    (if (= (car ctx) :block)
      (strcat "块:" (cadr ctx))
      (strcat "空间:" (cadr ctx))
    )
  )
)

;; 记录处理
(defun OCS:seenP (res h)
  (and h (vl-position h (OCS:getVal res :seen nil)))
)
(defun OCS:markSeen (res h)
  (if h
    (OCS:putPair res :seen (append (OCS:getVal res :seen nil) (list h)))
    res
  )
)

;; 按对象类型分发
(defun OCS:handleEntity (res doc e typ ctx handle / cls)
  (setq cls (OCS:mapClass typ))
  (cond
    ((eq cls :text)     (OCS:collectTextHost res doc e ctx handle typ))
    ((eq cls :mtext)    (OCS:collectTextHost res doc e ctx handle typ))
    ((eq cls :attrib)   (OCS:collectAttrib res doc e ctx handle typ))
    ((eq cls :attdef)   (OCS:collectAttrib res doc e ctx handle typ))
    ((eq cls :dim)      (OCS:collectDim res doc e ctx handle typ))
    ((eq cls :mleader)  (OCS:collectMLeader res doc e ctx handle typ))
    ((eq cls :leader)   (OCS:collectLeader res doc e ctx handle typ))
    ((eq cls :table)    (OCS:collectTable res doc e ctx handle typ))
    ((eq cls :tolerance)(OCS:collectTolerance res doc e ctx handle typ))
    ((eq cls :blockref) (OCS:collectBlockRef res doc e ctx handle typ))
    ((eq cls :attribute-dest) res) ; 由 blockref 处理
    (T
     ;; 专业/代理对象：记录为未覆盖
     (if (OCS:isUnknownClass typ)
       (progn
         (setq res (OCS:putPair res :unknown (1+ (OCS:getVal res :unknown 0))))
         (setq res (OCS:lstAppend res :skipped
                      (list "PROXY_OR_PRO" handle (strcat typ "@" (OCS:ctxStr ctx)))))
       )
     )
     res
    )
  )
)

(defun OCS:isUnknownClass (typ)
  (or (OCS:strContains typ "Proxy")
      (OCS:strContains typ "ACAD_PROXY")
      (and (OCS:strContains typ "AcDb")
           (not (OCS:knownClass typ)))
  )
)
(princ "\nOK-PART6 lines 907-1088")
(princ)
