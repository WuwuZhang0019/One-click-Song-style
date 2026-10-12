;;; probe p11 (11/13) - 引擎特性测试：* 包裹的全局符号（*OCS:Version* 风格）
;;; 由 tools/build_diag.py 生成；加载成功应看到 PROBE-11-OK 标记
;;; probe p11 - starred global symbols
(setq *OCS:ProbeVar* "v0.1")
(if (and (boundp '*OCS:ProbeVar*) *OCS:ProbeVar*)
  (princ "\nPROBE-11-OK starred-symbols")
  (princ "\nPROBE-11-FAIL")
)
