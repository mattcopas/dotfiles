;;; snippets.el --- Description: snippets config -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:
(use-package yasnippet
  :demand t
  :config
  (yas-global-mode 1))

(use-package autoinsert
  :ensure nil
  :init
  ;; Don't ask for confirmation before inserting template
  (setq auto-insert-query nil)
  (auto-insert-mode 1)
  :config
  ;; Define Elisp auto-insert skeleton
  (define-auto-insert
    '("\\.el\\'" . "Emacs Lisp Header")
    '((file-name-nondirectory (buffer-file-name))
      ";;; " (file-name-nondirectory (buffer-file-name))
      " --- " (read-string "Description: ") " -*- lexical-binding: t; -*-\n\n"
      ";;; Commentary:\n;; " _ "\n\n"
      ";;; Code:\n\n"
      "(provide '" (file-name-base (buffer-file-name)) ")\n"
      ";;; " (file-name-nondirectory (buffer-file-name)) " ends here\n")))

(provide 'modules/snippets)

;;; snippets.el ends here
