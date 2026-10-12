;;; part12 - 主源码第 2448-2549 行（顶层 form 155-159，共 159 个）
;;; 由 tools/build_diag.py 生成；本部件可独立 LOAD，加载成功打印 OK-PART12
(defun OCS:TestFault (point)
  (if (and *OCS:FaultPoint* (= *OCS:FaultPoint* point))
    (progn
      (setq *OCS:FaultPoint* nil)
      (OCS:fail (strcat "OCS 故障注入：" point))
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
      (setq r (OCS:NormalizeFontRuns in (list (cons "family" "SimSun")
                                               (cons "charSet" 134)
                                               (cons "pitchFamily" 36)
                                               (cons "appendParams" T))))
      (setq out (OCS:assocd "text" r ""))
      (setq n  (OCS:assocd "changes" r 0))
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
(princ "\nOK-PART12 lines 2448-2549")
(princ)
