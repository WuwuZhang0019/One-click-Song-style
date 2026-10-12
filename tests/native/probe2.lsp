;;; probe2.lsp - S01 native probe #2 (temporary development file)
;;; ASCII-only strings; writes results as UTF-8 via encoded print.
(defun c:OCS_PROBE2 ( / f )
  (setq f (open "C:\\Temp\\ocs\\probe2.out" "w"))
  (write-line "--- OCS PROBE 2 ---" f)
  (write-line (strcat "ACADVER=" (getvar "ACADVER")) f)
  (write-line (strcat "PRODUCT=" (getvar "PRODUCT")) f)
  (write-line (strcat "LISPSYS=" (itoa (getvar "LISPSYS"))) f)
  (write-line (strcat "UNDOCTL=" (itoa (getvar "UNDOCTL"))) f)
  (write-line (strcat "FONTALT=[" (getvar "FONTALT") "]") f)
  (write-line (strcat "FONTMAP=[" (getvar "FONTMAP") "]") f)
  (write-line (strcat "SECURELOAD=" (itoa (getvar "SECURELOAD"))) f)
  (write-line (strcat "CMDECHO=" (itoa (getvar "CMDECHO"))) f)
  (write-line (strcat "f findfile simsun.ttc=" (if (findfile "simsun.ttc") "YES" "NO")) f)
  (write-line (strcat "f findfile SIMSUN.TTC=" (if (findfile "SIMSUN.TTC") "YES" "NO")) f)
  (write-line (strcat "f findfile simsun.ttf=" (if (findfile "simsun.ttf") "YES" "NO")) f)
  (write-line (strcat "f findfile simhei.ttf=" (if (findfile "simhei.ttf") "YES" "NO")) f)
  (write-line (strcat "f findfile STSONG.TTF=" (if (findfile "STSONG.TTF") "YES" "NO")) f)
  (write-line (strcat "f WindowsFonts=" (if (findfile (strcat (getenv "WinDir") "\\Fonts\\simsun.ttc")) "YES" "NO")) f)
  (OCS_PROBE2_STYLE f)
  (write-line "--- PROBE 2 END ---" f)
  (close f)
  (princ)
)

(defun OCS_PROBE2_STYLE ( f / doc ent old big r typeFace bold italic charSet pitch )
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  ;; remove leftover test style if any
  (vl-catch-all-apply 'command (list "-DELETE" "ALL" "" ))
  (setq ent (tblobjname "STYLE" "OCSPROBE"))
  (if ent (entdel ent))
  (vl-catch-all-apply '(lambda () (vla-AddTextStyle doc "OCSPROBE" "txt" T)) nil)
  (setq ent (tblobjname "STYLE" "OCSPROBE"))
  (if (not ent)
    (write-line "F: AddTextStyle failed" f)
    (progn
      (write-line (strcat "I: STYLE 70=" (itoa (cdr (assoc 70 (entget ent))))) f)
      (OCS_PROBE2_STYLE_RW f ent)
    )
  )
  (princ)
)

(defun OCS_PROBE2_STYLE_RW ( f ent / o r typeFace bold italic charSet pitch dxf4 old70 old40 old41 old50 )
  (setq o (vlax-ename->vla-object ent))
  (setq r (vl-catch-all-apply 'vla-get-FontFile (list o)))
  (write-line (if (vl-catch-all-error-p r) (strcat "F: get FontFile ERR " (vl-catch-all-error-message r)) (strcat "I: FontFile-before=[" r "]")) f)
  (setq r (vl-catch-all-apply 'vla-get-BigFontFile (list o)))
  (write-line (if (vl-catch-all-error-p r) (strcat "F: get BigFontFile ERR " (vl-catch-all-error-message r)) (strcat "I: BigFontFile-before=[" r "]")) f)

  ;; 1) set a bigfont first
  (setq r (vl-catch-all-apply 'vla-put-BigFontFile (list o "hz.shx")))
  (write-line (if (vl-catch-all-error-p r) (strcat "F: put BigFontFile ERR " (vl-catch-all-error-message r)) "I: put BigFontFile hz.shx OK") f)
  (setq r (vl-catch-all-apply 'vla-get-BigFontFile (list o)))
  (write-line (if (vl-catch-all-error-p r) "F: get bigfont after put ERR" (strcat "I: BigFontFile-with=[" r "]")) f)

  ;; 2) try vla-put-BigFontFile with empty string
  (setq r (vl-catch-all-apply 'vla-put-BigFontFile (list o "")))
  (write-line (if (vl-catch-all-error-p r) (strcat "I: put BigFontFile empty ERR: " (vl-catch-all-error-message r)) "I: put BigFontFile empty OK") f)
  (setq r (vl-catch-all-apply 'vla-get-BigFontFile (list o)))
  (write-line (if (vl-catch-all-error-p r) "F: get bigfont after empty ERR" (strcat "I: BigFontFile-after-empty=[" r "]")) f)

  ;; 3) DXF 4 clear path
  (setq ent (tblobjname "STYLE" "OCSPROBE"))
  (setq r (OCS_PROBE2_DXF4CLEAR ent))
  (write-line r f)
  (setq ent (tblobjname "STYLE" "OCSPROBE"))
  (setq o (vlax-ename->vla-object ent))
  (setq r (vl-catch-all-apply 'vla-get-BigFontFile (list o)))
  (write-line (if (vl-catch-all-error-p r) "F: get bigfont after dxf4 ERR" (strcat "I: BigFontFile-after-dxf4=[" r "]")) f)
  (setq ent (tblobjname "STYLE" "OCSPROBE"))
  (write-line (strcat "I: DXF4-readback=[" (cdr (assoc 4 (entget ent))) "]") f)

  ;; 4) snapshot non-font params
  (setq old40 (cdr (assoc 40 (entget ent)))
        old41 (cdr (assoc 41 (entget ent)))
        old50 (cdr (assoc 50 (entget ent)))
        old70 (cdr (assoc 70 (entget ent))))
  (write-line (strcat "I: before 40=" (rtos old40 2 6) " 41=" (rtos old41 2 6) " 50=" (rtos old50 2 6) " 70=" (itoa old70)) f)

  ;; 5) GetFont
  (setq r (vl-catch-all-apply 'vla-GetFont (list o 'typeFace 'bold 'italic 'charSet 'pitch)))
  (if (vl-catch-all-error-p r)
    (write-line (strcat "F: GetFont ERR " (vl-catch-all-error-message r)) f)
    (progn
      (write-line (strcat "I: GetFont typeFace=[" typeFace "] bold=" (itoa (if (equal bold T) 1 0)) " italic=" (itoa (if (equal italic T) 1 0)) " charSet=" (itoa charSet) " pitch=" (itoa pitch)) f)
    )
  )

  ;; 6) FontFile write then SetFont
  (setq r (vl-catch-all-apply 'vla-put-FontFile (list o "simsun.ttc")))
  (write-line (if (vl-catch-all-error-p r) (strcat "F: put FontFile simsun.ttc ERR " (vl-catch-all-error-message r)) "I: put FontFile simsun.ttc OK") f)
  (setq r (vl-catch-all-apply 'vla-SetFont (list o "SimSun" :vlax-false :vlax-false 1 34)))
  (write-line (if (vl-catch-all-error-p r) (strcat "F: SetFont SimSun ERR " (vl-catch-all-error-message r)) "I: SetFont SimSun OK") f)
  (setq r (vl-catch-all-apply 'vla-get-FontFile (list o)))
  (write-line (if (vl-catch-all-error-p r) "F: get FontFile after ERR" (strcat "I: FontFile-after=[" r "]")) f)
  (setq r (vl-catch-all-apply 'vla-get-LastFontFile (list o)))
  (write-line (if (vl-catch-all-error-p r) "F: get LastFontFile ERR" (strcat "I: LastFontFile=[" r "]")) f)
  (setq r (vl-catch-all-apply 'vla-get-TextFontFile (list o)))
  (write-line (if (vl-catch-all-error-p r) "F: get TextFontFile ERR" (strcat "I: TextFontFile=[" r "]")) f)

  ;; readback dxf
  (setq ent (tblobjname "STYLE" "OCSPROBE"))
  (write-line (strcat "I: dxf3=[" (cdr (assoc 3 (entget ent))) "] dxf4=[" (cdr (assoc 4 (entget ent))) "] dxf40=" (rtos (cdr (assoc 40 (entget ent))) 2 6) " dxf41=" (rtos (cdr (assoc 41 (entget ent))) 2 6) " dxf50=" (rtos (cdr (assoc 50 (entget ent))) 2 6) " dxf70=" (itoa (cdr (assoc 70 (entget ent)))))) f)
  (write-line (strcat "I: charset=" (itoa (OCS_PROBE2_CHARSET "simsun.ttc"))) f)
  (princ)
)

(defun OCS_PROBE2_DXF4CLEAR ( ent / e r )
  (setq e (entget ent))
  (if (not (assoc 4 e))
    "I: dxf4 clear skipped, group 4 absent"
    (progn
      (setq r (vl-catch-all-apply 'entmod (list (OCS_PROBE2_SUBST4 "" e))))
      (if (vl-catch-all-error-p r)
        (strcat "F: entmod clear4 ERR " (vl-catch-all-error-message r))
        "I: entmod clear4 OK")
    )
  )
)

(defun OCS_PROBE2_SUBST4 ( val e / out found )
  (foreach pair e
    (if (= (car pair) 4)
      (setq found T out (append (if out (list (cons 4 val)) (list (cons 4 val))) out))
      (setq out (append out (list pair)))
    )
  )
  (if found out e)
)

(defun OCS_PROBE2_CHARSET ( file / c sz h b i n )
  ;; heuristic: return 134 if Chinese content detected, else 1
  (setq c 1)
  (if (findfile file)
    (progn
      (setq h (open (findfile file) "r"))
      (if h
        (progn
          (setq sz (file-size (findfile file)))
          (setq b (read-char h) n 0)
          (while (and b (< n 600000))
            (if (or (and (>= b 176) (<= b 247)) (and (>= b 48) (<= b 57) nil)) (setq c 134))
            (setq b (read-char h) n (1+ n))
          )
          (close h)
        )
      )
    )
  )
  c
)

(princ)
