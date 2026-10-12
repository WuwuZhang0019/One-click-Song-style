;;; sub12/f05 - 主源码第 2337-2361 行（part12 第 5 个顶层 form）
;;; 由 tools/build_diag.py 生成；加载成功打印 OK-F05
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
(princ "\nOK-F05 lines 2337-2361")
(princ)
