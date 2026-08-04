;;; which-key.el --- Setup which-key -*- lexical-binding: t; -*-
;;
;;; Commentary:
;;
;;  Description
;;
;;; Code:


(use-package which-key
  :init
  (setq which-key-idle-delay 0.3
        which-key-idle-secondary-delay 0.05)
  :config
  (which-key-mode 1))

(provide 'modules/which-key)
;;; which-key.el ends here

