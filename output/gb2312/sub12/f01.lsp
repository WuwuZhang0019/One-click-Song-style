;;; sub12/f01 - 主源码第 2188-2263 行（part12 第 1 个顶层 form）
;;; 由 tools/build_diag.py 生成；加载成功打印 OK-F01
(defun OCS:executeWrites ( / report stylesRes hostsRes verifyRes wrote)
  (setq report (OCS:makeReport nil))
  ;; 临时解锁
  (OCS:lockLayersNeeded)
  (OCS:unlockTempLayers)
  ;; 样式写入
  (setq stylesRes (OCS:applyAllStyles))
  (if (OCS:assocd :error stylesRes nil)
    (setq report (OCS:appendError report "STYLE" (OCS:assocd :error stylesRes ""))))
  ;; 内容写入
  (setq hostsRes (OCS:applyAllHosts))
  ;; 其余统计（report 中已预置同名键，必须替换而非追加）
  (setq report (OCS:reportSet report
                 (list
                   (cons :stylesScanned (length (OCS:assocd :styles *OCS:Plan* nil)))
                   (cons :stylesModified (OCS:assocd :modified stylesRes 0))
                   (cons :stylesXref (length (OCS:assocd :xrefStyle *OCS:Plan* nil)))
                   (cons :stylesShape (length (OCS:assocd :shape *OCS:Plan* nil)))
                   (cons :hostsScanned (length (OCS:assocd :hosts *OCS:Plan* nil)))
                   (cons :fontRunsChanged (OCS:assocd :changes hostsRes 0))
                   (cons :attribs (OCS:assocd :attribs (OCS:assocd :stats *OCS:Plan*) 0))
                   (cons :blocks (OCS:assocd :blocks (OCS:assocd :stats *OCS:Plan*) 0))
                   (cons :xrefBlocks (OCS:assocd :xrefBlocks (OCS:assocd :stats *OCS:Plan*) 0))
                   (cons :displayBlocks (OCS:assocd :displayBlocks (OCS:assocd :stats *OCS:Plan*) 0))
                   (cons :tableContents (OCS:assocd :tableContents hostsRes 0))
                   (cons :uncovered (OCS:assocd :unknown (OCS:assocd :stats *OCS:Plan*) 0))
                   (cons :uncoveredDetail (OCS:assocd :skipped (OCS:assocd :stats *OCS:Plan*) nil))
                 )))
  (if (OCS:assocd :error hostsRes nil)
    (setq report (OCS:appendError report "HOST" (OCS:assocd :error hostsRes ""))))
  ;; 临时状态恢复
  (OCS:restoreTempState)
  ;; 中途错误（写入失败/解析问题）→ 回滚本次业务写入
  (if (OCS:assocd :errors report 0)
    (progn
      (setq report (OCS:reportSet report (list (cons :status "失败已回滚"))))
      (if (not (OCS:Rollback))
        (setq report (OCS:reportSet report (list (cons :recoverFailed 1))))
      )
    )
    (progn
      ;; 再生 + 读回
      (OCS:TestFault "regen-check")
      (setq verifyRes (OCS:VerifyDrawing))
      (if (not (OCS:assocd :ok verifyRes T))
        (progn
          (setq report (OCS:appendError report "VERIFY" (OCS:assocd :error verifyRes "")))
          ;; 读回不符 → 回滚本次修改
          (setq report (OCS:reportSet report (list (cons :status "失败已回滚"))))
          (if (not (OCS:Rollback))
            (setq report (OCS:reportSet report (list (cons :recoverFailed 1))))
          )
        )
        (progn
          (OCS:endUndoGroup)
          ;; 状态判定（方案第 12 节）
          (setq report (OCS:reportSet report
            (list (cons :status
              (cond
                ((> (OCS:assocd :errors report 0) 0) "失败已回滚")
                ((> (OCS:assocd :uncovered report 0) 0) "部分完成")
                ((and (= 0 (OCS:assocd :stylesModified report 0))
                      (= 0 (OCS:assocd :fontRunsChanged report 0)))
                 "无需修改")
                (T "已完成")
              )))))
        )
      )
    )
  )
  (setq report (OCS:reportSet report
                 (list (cons :dwg (getvar "DWGPREFIX"))
                       (cons :cadver (getvar "ACADVER"))
                       (cons :family "SimSun"))))
  report
)
(princ "\nOK-F01 lines 2188-2263")
(princ)
