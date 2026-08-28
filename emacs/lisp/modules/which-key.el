;;; which-key.el --- Setup which-key -*- lexical-binding: t; -*-
;;
;;; Commentary:
;;
;;  Description
;;
;;; Code:


(use-package which-key
  :demand t
  :init
  (setq which-key-idle-delay 0.7
        which-key-idle-secondary-delay 0.7)
  :config
  (which-key-mode 1))

(provide 'modules/which-key)
;;; which-key.el ends here

