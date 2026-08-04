;;; git.el --- Magit etc -*- lexical-binding: t; -*-

;;; Commentary:
;; 

;;; Code:

;; Force modern Transient (magit dependency) to be installed before Magit loads
(use-package transient
  :demand t
  :ensure t)

;;; Core Magit Interface
(use-package magit
  :commands (magit-status magit-get-current-branch)
  :config
  (setq magit-display-buffer-function #'magit-display-buffer-same-window-except-diff-v1)
  (with-eval-after-load 'evil
    (evil-set-initial-state 'git-commit-mode 'insert)))

  ;; Start commit message buffers in Evil Insert Mode
  
;; Leader Keybindings for Git (Defined directly via General)
(with-eval-after-load 'general
    (general-define-key
    :states '(normal visual emacs)
    :keymaps 'override
    :prefix "SPC"
    "g"  '(:ignore t :which-key "git")
    "gg" '(magit-status :which-key "magit status")
    "gb" '(magit-blame :which-key "magit blame")
    "gC" '(magit-clone :which-key "magit clone")
    "gl" '(magit-log-current :which-key "magit log")))

;; Git Margins / Fringe Indicators (Shows modified lines in gutter)
(use-package diff-hl
  :hook
  ((prog-mode . diff-hl-mode)
   (org-mode  . diff-hl-mode)
   (magit-post-refresh . diff-hl-magit-post-refresh)))

(provide 'modules/git)
;;; git.el ends here
