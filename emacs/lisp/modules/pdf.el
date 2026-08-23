;;; pdf.el --- PDF Tools etc -*- lexical-binding: t; -*-

;;; Commentary:
;;

;;; Code:

(use-package pdf-tools
  ;; Shouldn't need to do mode stuff here - .pdf should activate by default
  :config
  (pdf-tools-install))

(provide 'modules/pdf)
;;; pdf.el ends here
