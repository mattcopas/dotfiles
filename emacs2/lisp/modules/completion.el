;;; completion.el --- Completion tools -*- lexical-binding: t; -*-
;;
;;; Commentary:
;;
;;  Description
;;
;;; Code:

;; Vertico (Minibuffer UI)
(use-package vertico
  :demand t
  :init
  (vertico-mode 1)
  :config
  (setq vertico-count 15           ; Show 15 candidate lines
        vertico-resize nil           ; Grow/shrink minibuffer dynamically
        vertico-cycle t))          ; Wrap around when reaching top/bottom

;; Orderless (Fuzzy / space-separated matching engine)
(use-package orderless
  :demand t
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles partial-completion)))))

;; Marginalia (Minibuffer Annotations: file permissions, sizes, docstrings)
(use-package marginalia
  :demand t
  :init
  (marginalia-mode 1))

;; Nerd Icons Completion (Adds icons to Marginalia & Vertico candidates)
(use-package nerd-icons-completion
  :demand t
  :after (marginalia)
  :config
  (nerd-icons-completion-mode 1)
  (add-hook 'marginalia-mode-hook #'nerd-icons-completion-marginalia-setup))

;; Recentf (Built-in Recent Files tracker - feeds into Consult)
(use-package recentf
  :ensure nil
  :demand t
  :init
  (defvar mc-cache-directory (expand-file-name ".local/cache" user-emacs-directory))

  (unless (file-exists-p mc-cache-directory)
    (make-directory mc-cache-directory t))
  :config
  (setq recentf-save-file (expand-file-name "recentf" mc-cache-directory)
        recentf-max-saved-items 200
        recentf-max-menu-items 15
        recentf-exclude '("^/tmp/"
                          "^/var/"
                          "\\.eln$"
                          "\\.elc$"
                          "elpaca/repos/"
                          "elpaca/builds/"))
  ;; 
  ;; Consult (Enhanced search and navigation commands)
  (use-package consult
    :demand t
    :config
    ;; Enable live preview for buffer switching & ripgrep
    (setq consult-preview-key 'any)
    
    ;; Map Consult commands into General.el leader keymaps
    (with-eval-after-load 'general
      (general-define-key
       :states '(normal visual emacs)
       :keymaps 'override
       :prefix "SPC"
       ;; Buffer navigation
       "b"  '(:ignore t :which-key "buffer")
       "bb" '(consult-buffer :which-key "switch buffer")
       "bB" '(consult-buffer-other-window :which-key "switch buffer other window")
       "bk" '(kill-current-buffer :which-key "kill buffer")
       
       ;; File searching
       "f"  '(:ignore t :which-key "file")
       "ff" '(find-file :which-key "find file")
       "fr" '(consult-recent-file :which-key "recent files")
       
       ;; Code & Project Search
       "s"  '(:ignore t :which-key "search")
       "ss" '(consult-line :which-key "search current buffer")
       "sp" '(consult-ripgrep :which-key "search project (ripgrep)")
       "si" '(consult-imenu :which-key "search symbols (imenu)")
       "so" '(consult-outline :which-key "search headings/outline")))) (recentf-mode 1))

(provide 'modules/completion)
;;; completion.el ends here
