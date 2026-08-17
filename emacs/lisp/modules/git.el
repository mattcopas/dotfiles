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
  ;; TODO - make magit commits (eg from Recent commits) display on the right
  ;; DOOM does this, so might be able to copy from there
  (setq magit-display-buffer-function #'magit-display-buffer-fullframe-status-v1)

  (with-eval-after-load 'evil
    (evil-set-initial-state 'git-commit-mode 'insert)))

  ;; Start commit message buffers in Evil Insert Mode
  
;; Leader Keybindings for Git (Defined directly via General)
(with-eval-after-load 'general
    (general-define-key
    :states '(normal visual emacs)
    :keymaps 'override
    :prefix me-leader-key
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

;; Exile Magit's Transient Folder to cache directory
(setq transient-history-file (expand-file-name "transient/history.el" me-local-cache-directory)
      transient-values-file  (expand-file-name "transient/values.el" me-local-cache-directory)
      transient-levels-file  (expand-file-name "transient/levels.el" me-local-cache-directory))

(provide 'modules/git)
;;; git.el ends here
