;;; mql.el --- MQL Config -*- lexical-binding: t; -*-

;;; Commentary:
;; 

;;; Code:

(add-to-list 'auto-mode-alist '("\\.mq5\\'" . c++-mode))
(add-to-list 'auto-mode-alist '("\\.mqh\\'" . c++-mode))

(defun my-mql5-setup ()
  (when (and buffer-file-name
             (string-match-p "\\.\\(mq5\\|mqh\\)\\'" buffer-file-name))
    (setq-local c-basic-offset 3)
    (setq-local indent-tabs-mode nil)))

(add-hook 'c++-mode-hook #'my-mql5-setup)

(defun mql5-compile ()
  (interactive)
  (save-buffer)
  (compile
   (format
    "wine \"%s\" /compile:\"%s\""
    (expand-file-name "~/.mt5/drive_c/Program Files/MetaTrader 5/MetaEditor64.exe")
    (buffer-file-name))))

(provide 'modules/languages/mql)
;;; mql.el ends here
