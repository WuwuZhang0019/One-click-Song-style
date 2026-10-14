;;; 独立手动 DXF 诊断：只查句柄 D5，不使用 ActiveX，不调用 YJST/OCS。
;;; 日期：2026-10-14
;;; 状态：源码验证通过，原生 CAD 稳定性待验证
;;; 编码：源码 UTF-8；CAD 使用 output/gb2312/tests/native/ 下的同名交付文件。
;;; APPLOAD 只注册命令。手动输入 YJSTD5DXF 才执行 handent 与 entget。
(setq *YJSTD5DXF:Marker* "YJST-D5-20261014-v3-DXF")
(setq *YJSTD5DXF:LogPath* nil *YJSTD5DXF:Encoding* nil *YJSTD5DXF:Lines* nil *YJSTD5DXF:LogError* nil)
(setq *YJSTD5DXF:LastCallStatus* nil)

(defun YJSTD5DXF:writeLine (line / stream written closed)
  (setq stream (vl-catch-all-apply 'open
    (if (= *YJSTD5DXF:Encoding* "UTF-8")
      (list *YJSTD5DXF:LogPath* "a" "utf8") (list *YJSTD5DXF:LogPath* "a"))))
  (if (and stream (not (vl-catch-all-error-p stream)))
    (progn
      (setq written (vl-catch-all-apply 'write-line (list line stream)))
      (setq closed (vl-catch-all-apply 'close (list stream)))
      (cond
        ((vl-catch-all-error-p written) (vl-catch-all-error-message written))
        ((vl-catch-all-error-p closed) (vl-catch-all-error-message closed))
        (T nil)))
    (if (vl-catch-all-error-p stream) (vl-catch-all-error-message stream) "无法打开日志"))
)

(defun YJSTD5DXF:emit (event data / line problem)
  (setq line (vl-prin1-to-string (list event data)))
  (setq *YJSTD5DXF:Lines* (cons line *YJSTD5DXF:Lines*))
  (if (and *YJSTD5DXF:LogPath* (not *YJSTD5DXF:LogError*))
    (progn
      (setq problem (vl-catch-all-apply 'YJSTD5DXF:writeLine (list line)))
      (if (vl-catch-all-error-p problem) (setq problem (vl-catch-all-error-message problem)))
      (if problem (setq *YJSTD5DXF:LogError* problem))))
  nil
)

(defun YJSTD5DXF:call (label fn args / result)
  (YJSTD5DXF:emit "CALL_BEGIN" (list "probe" label "function" (vl-symbol-name fn)))
  ;; 日志失败时停止访问目标对象，避免没有磁盘检查点仍继续探测。
  (if (or (not *YJSTD5DXF:LogPath*) *YJSTD5DXF:LogError*)
    (progn
      (setq *YJSTD5DXF:LastCallStatus* "skipped")
      (YJSTD5DXF:emit "CALL_SKIPPED" (list "probe" label "reason" "日志检查点无法落盘"))
      nil)
    (progn
      (setq result (vl-catch-all-apply fn args))
      (if (vl-catch-all-error-p result)
        (progn
          (setq *YJSTD5DXF:LastCallStatus* "error")
          (YJSTD5DXF:emit "CALL_ERROR" (list "probe" label "error" (vl-catch-all-error-message result)))
          nil)
        (progn
          (setq *YJSTD5DXF:LastCallStatus* (if (null result) "nil" "ok"))
          ;; 日期：2026-10-14。原生 AutoLISP 的 (type nil) 返回 nil，不能传给 vl-symbol-name。
          (YJSTD5DXF:emit "CALL_END" (list "probe" label "status" *YJSTD5DXF:LastCallStatus*
            "valueType" (if (null result) "NIL" (vl-symbol-name (type result)))))
          result))))
)

(defun YJSTD5DXF:summary (data / fields pair value)
  (foreach pair data
    (if (member (car pair) (list 0 2 5 8 66 67 70 100 102 330 340 350 360 410))
      (progn
        (setq value (cdr pair))
        (setq fields (cons (list (car pair)
          (if (equal (type value) 'ENAME) "<ENAME>" (vl-prin1-to-string value))) fields)))))
  (reverse fields)
)

(defun YJSTD5DXF:run ( / ent data)
  (YJSTD5DXF:emit "RUN_BEGIN" (list "marker" *YJSTD5DXF:Marker* "date" "2026-10-14"
    "handle" "D5" "readOnly" T "encoding" *YJSTD5DXF:Encoding*
    "dwg" (strcat (getvar "DWGPREFIX") (getvar "DWGNAME"))))
  (setq ent (YJSTD5DXF:call "entity.byHandle" 'handent (list "D5")))
  (if ent
    (progn
      (setq data (YJSTD5DXF:call "entity.DXF" 'entget (list ent)))
      (YJSTD5DXF:emit "DXF" (list "status" (if data "ok" "nil") "pairCount" (length data)
        "entgetStatus" *YJSTD5DXF:LastCallStatus* "fields" (YJSTD5DXF:summary data))))
    (YJSTD5DXF:emit "DXF" (list "status" "unavailable")))
  (YJSTD5DXF:emit "RUN_END" (list "marker" *YJSTD5DXF:Marker* "readOnly" T
    "status" (cond (*YJSTD5DXF:LogError* "日志写入失败") (data "DXF已读取") (ent "DXF不可读") (T "句柄未找到"))
    "lastCallStatus" *YJSTD5DXF:LastCallStatus*))
)

(defun c:YJSTD5DXF ( / dirs dir stamp path suffix opened closed result line)
  (setq *YJSTD5DXF:LogPath* nil *YJSTD5DXF:Encoding* nil *YJSTD5DXF:Lines* nil *YJSTD5DXF:LogError* nil)
  (setq *YJSTD5DXF:LastCallStatus* nil)
  (setq stamp (rtos (getvar "CDATE") 2 8)
        dirs (list (getvar "TEMPPREFIX") (getenv "TEMP") (getvar "DWGPREFIX")))
  (foreach dir dirs
    (if (and (not *YJSTD5DXF:LogPath*) dir (/= dir ""))
      (progn
        (if (not (member (substr dir (strlen dir) 1) (list "/" "\\"))) (setq dir (strcat dir "/")))
        (setq path (strcat dir "YJST-D5-DXF-" stamp ".log") suffix 0)
        (while (findfile path)
          (setq suffix (1+ suffix) path (strcat dir "YJST-D5-DXF-" stamp "-" (itoa suffix) ".log")))
        (setq opened (vl-catch-all-apply 'open (list path "w" "utf8")) *YJSTD5DXF:Encoding* "UTF-8")
        (if (vl-catch-all-error-p opened)
          (setq opened (vl-catch-all-apply 'open (list path "w")) *YJSTD5DXF:Encoding* "CAD-legacy"))
        (if (and opened (not (vl-catch-all-error-p opened)))
          (progn
            (setq closed (vl-catch-all-apply 'close (list opened)))
            (if (not (vl-catch-all-error-p closed)) (setq *YJSTD5DXF:LogPath* path)))))))
  (if *YJSTD5DXF:LogPath*
    (progn
      (princ (strcat "\n手动 DXF 诊断：" *YJSTD5DXF:Marker* "\n诊断日志：" *YJSTD5DXF:LogPath*))
      (setq result (vl-catch-all-apply 'YJSTD5DXF:run nil))
      (if (vl-catch-all-error-p result)
        (progn
          (YJSTD5DXF:emit "DIAGNOSTIC_ERROR" (vl-catch-all-error-message result))
          (YJSTD5DXF:emit "RUN_END" (list "status" "诊断中断"))))
      (if *YJSTD5DXF:LogError*
        (progn
          (princ "\n日志写入失败，已停止进一步探测；以下为内存记录：")
          (foreach line (reverse *YJSTD5DXF:Lines*) (princ (strcat "\n" line)))))
      (princ "\nDXF 诊断结束。"))
    (princ "\n无法创建诊断日志，未读取 D5。"))
  (princ)
)

;; 加载阶段仅定义命令和显示标识，不调用任何图纸、文件或对象读取接口。
(princ (strcat "\n手动 DXF 诊断已加载：" *YJSTD5DXF:Marker* "。输入 YJSTD5DXF 才开始检查。"))
(princ)
