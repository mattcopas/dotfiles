;;; editor.el --- Editor config -*- lexical-binding: t; -*-


;;; Commentary:
;;

;;; Code:

(use-package smartparens
  ;; Most programming modes inherit from prog-mode, so this covers basically everything
  :hook (prog-mode text-mode markdown-mode)
  :config
  ;; load default config
  (require 'smartparens-config)
  ;; Explicitly enable smartparens in the scratch buffer
  ;; We have to do this outside the hook above because the scratch buffer is created BEFORE init.el runs
  (with-current-buffer "*scratch*"
    (smartparens-mode 1)))

(use-package highlight-quoted
  :hook (emacs-lisp-mode . highlight-quoted-mode))

(provide 'modules/editor)
;;; editor.el ends here
