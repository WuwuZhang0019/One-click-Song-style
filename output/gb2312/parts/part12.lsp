;;; part12 - 主源码第 2188-2426 行（顶层 form 144-151，共 151 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART12
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

(defun OCS:applyAllStyles ( / modified err)
  (setq modified 0 err nil)
  (foreach st (OCS:assocd :styles *OCS:Plan* nil)
    (if (not err)
      (progn
        (OCS:TestFault "style-write")
        (setq r (OCS:ApplyStyle (OCS:activeDoc) st))
        (if (OCS:assocd :ok r nil)
          (setq modified (1+ modified))
          (setq err (OCS:assocd :error r "未知错误"))
        )
      )
    )
  )
  (list :modified modified :error err)
)

(defun OCS:applyAllHosts ( / changes tableContents err data new r)
  (setq changes 0 tableContents 0 err nil)
  (foreach host (OCS:assocd :hosts *OCS:Plan* nil)
    (if (not err)
      (progn
        (setq data (OCS:ReadHost host))
        (if (OCS:assocd :error data nil)
          (setq err (strcat (OCS:assocd :handle host "?") ": " (OCS:assocd :error data "")))
          (if (not (OCS:assocd :skip data nil))
            (progn
              (setq new (OCS:NormalizeFontRuns (OCS:assocd :text data "") (OCS:fontTarget)))
              (if (OCS:assocd :issues new nil)
                (setq err (strcat (OCS:assocd :handle host "?") ": 内容解析问题 "
                                   (OCS:fmt (OCS:assocd :issues new nil))))
              )
              (if (and (not err) (> (OCS:assocd :changes new 0) 0))
                (progn
                  (OCS:TestFault "content-write")
                  (setq data (OCS:putPair data :text (OCS:assocd :text new "")))
                  (setq r (OCS:WriteHost host data))
                  (if (OCS:assocd :ok r nil)
                    (progn
                      (setq changes (+ changes (OCS:assocd :changes new 0)))
                      (if (eq (OCS:assocd :kind host) :table)
                        (setq tableContents (+ tableContents (OCS:assocd :contents r 0)))
                      )
                    )
                    (setq err (strcat (OCS:assocd :handle host "?") ": " (OCS:assocd :error r "")))
                  )
                )
              )
            )
          )
        )
      )
    )
  )
  (list :changes changes :tableContents tableContents :error err)
)

;;; ----------------------------------------------------------------------
;;; 故障注入（仅测试入口，正常运行不受影响）
;;; ----------------------------------------------------------------------
(defun OCS:TestFault (point)
  (if (and *OCS:FaultPoint* (= *OCS:FaultPoint* point))
    (progn
      (setq *OCS:FaultPoint* nil)
      (error (strcat "OCS 故障注入：" point))
    )
  )
)

;;; ----------------------------------------------------------------------
;;; 自检入口（纯函数部分，不依赖 CAD 环境）：OCS:SelfTest
;;; ----------------------------------------------------------------------
(defun OCS:SelfTest ( / cases pass fail)
  (setq cases (OCS:selfTestCases) pass 0 fail 0)
  (foreach c cases
    (progn
      (setq in  (car c) want (cadr c) wantN (caddr c))
      (setq r (OCS:NormalizeFontRuns in (list (cons :family "SimSun")
                                               (cons :charSet 134)
                                               (cons :pitchFamily 36)
                                               (cons :appendParams T))))
      (setq out (OCS:assocd :text r ""))
      (setq n  (OCS:assocd :changes r 0))
      (if (and (= out want) (= n wantN))
        (setq pass (1+ pass))
        (progn
          (setq fail (1+ fail))
          (princ (strcat "\nFAIL in=[" in "] got=[" out "] want=[" want "]"))
        )
      )
    )
  )
  (princ (strcat "\nOCS:SelfTest 通过 " (itoa pass) " / 失败 " (itoa fail)))
  ;; 注意：结尾不能写 (setq fail)：目标引擎读入器不接受单参数 setq（实测语法错误），
  ;; 裸符号作为最后表达式返回值，语义相同。
  fail
)

(defun OCS:selfTestCases ( / long1 acc n)
  ;; 与 tests/font-format-cases.json 一一对应：
  ;; C01-plain-inherit, C02-font-arial-bold-italic, C03-height-nested-fonts,
  ;; C04-paragraph-codes, C05-stack-diameter-tolerance, C06-field-code-protected,
  ;; C07-escaped-backslash-brace, C08-long-mixed-text, C09-already-simsun,
  ;; C10-incomplete-code-error, C11-nested-two-fonts, C12-underline-color-preserved,
  ;; C13-second-run-zero, C14-chinese-font-name-in-body, C15-nested-field-inside-format
  (setq long1 "")
  (setq n 0)
  (while (< n 60)
    (setq long1 (strcat long1 "英文 ABC 与中文 宋体测试"))
    (setq n (1+ n))
  )
  (list
    ;; C01
    (list "本页统一使用黑体，字高 3.5。" "本页统一使用黑体，字高 3.5。" 0)
    ;; C02
    (list "{\\fArial|b1|i0;标题正文}" "{\\fSimSun|b1|i0|c134|pf22;标题正文}" 1)
    ;; C03
    (list "{\\H0.7x;\\fSimHei|b0|i1;说明段落}" "{\\H0.7x;\\fSimSun|b0|i1|c134|pf22;说明段落}" 1)
    ;; C04
    (list "\\pl1;第一段\\P第二段\\fTimes New Roman;第三段"
          "\\pl1;第一段\\P第二段\\fSimSun|c134|pf22;第三段" 1)
    ;; C05
    (list "%%c12 \\fISOCPEUR;\\S1/2; 完"
          "%%c12 \\fSimSun|c134|pf22;\\S1/2; 完" 1)
    ;; C06 字段保护（示例字段内容，\f 位于 %<...>% 内）
    (list "值 %<\\f\\H0.5x;\\C1;\\f% \\pr \"0.00\";.Measured|%fml \\f+1; %>结束"
          "值 %<\\f\\H0.5x;\\C1;\\f% \\pr \"0.00\";.Measured|%fml \\f+1; %>结束" 0)
    ;; C07 转义
    (list "路径 C:\\temp\\{图} 与 \\fArial 不变"
          "路径 C:\\temp\\{图} 与 \\fArial 不变" 0)
    ;; C08 长文本（应无修改，完整往返）
    (list long1 long1 0)
    ;; C09 已是宋体
    (list "{\\fSimSun|b0|i0|c134|pf22;已统一}" "{\\fSimSun|b0|i0|c134|pf22;已统一}" 0)
    ;; C10 不完整指令 → 不修改原文（错误由 :issues 报告）
    (list "前面{\\fArial" "前面{\\fArial" 0)
    ;; C11 嵌套两个字体
    (list "{\\fArial|b1|i0;标题}\\P{\\H0.7x;\\fSimHei|b0|i1;说明}"
          "{\\fSimSun|b1|i0|c134|pf22;标题}\\P{\\H0.7x;\\fSimSun|b0|i1|c134|pf22;说明}" 2)
    ;; C12 颜色与字距保持
    (list "\\C3;\\fCourier New;固定\\fSimSun;字宽\\Q5;尾"
          "\\C3;\\fSimSun|c134|pf22;固定\\fSimSun|c134|pf22;字宽\\Q5;尾" 2)
    ;; C13 幂等
    (list "{\\fSimSun|b1|i0|c134|pf22;幂等}" "{\\fSimSun|b1|i0|c134|pf22;幂等}" 0)
    ;; C14 正文中的字体名不改
    (list "本页统一使用黑体与 Arial 字体名说明"
          "本页统一使用黑体与 Arial 字体名说明" 0)
    ;; C15 字段嵌套在格式作用域内
    (list "{\\fArial|b1;i;前 %<\\\\AcVar \\f\\\\H;>后}"
          "{\\fSimSun|b1|c134|pf22;i;前 %<\\\\AcVar \\f\\\\H;>后}" 1)
  )
)

;;; =====================================================================
;;; 加载提示（防御式：版本号取不到时不触发 strcat 类型错误）
;;; =====================================================================
(if (and (boundp '*OCS:Version*) *OCS:Version*)
  (princ (strcat "\n一键统一宋体（YJST）v" *OCS:Version*
                 " 已加载。输入 YJST 执行。"))
  (princ "\n一键统一宋体（YJST）已加载。输入 YJST 执行。")
)
(princ)
(princ "\nOK-PART12 lines 2188-2426")
(princ)
