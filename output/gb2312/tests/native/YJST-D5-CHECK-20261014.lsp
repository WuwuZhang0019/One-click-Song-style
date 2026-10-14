;;; 日期：2026-10-14
;;; 状态：旧自动探测入口已撤回，加载本文件不会执行对象诊断
;;; 用户反馈旧版加载后 CAD 闪退；不再保留 ActiveX 复探或加载即执行逻辑。
(defun c:YJSTD5CHECK ()
  (princ "\n旧 D5 自动探测已停用。新入口为 YJST-D5-DXF-20261014.lsp，加载后输入 YJSTD5DXF。")
  (princ)
)
(princ "\n旧 D5 自动探测已停用，本次加载未检查图纸对象。")
(princ)
