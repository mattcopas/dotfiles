;;; ui.el --- General UI stuff -*- lexical-binding: t; -*-
;;
;;; Commentary:
;;
;;  Description
;;
;;; Code:

;; Nerd Icons
(use-package nerd-icons
  :demand t)
;; Icons for dired (lazy-loaded when opening a folder)
(use-package nerd-icons-dired
  :hook (dired-mode . nerd-icons-dired-mode))

;; Doom Themes
(use-package doom-themes
  :demand t
  :config
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t)
  (load-theme 'doom-one t)
  (doom-themes-visual-bell-config)
  (doom-themes-org-config))

;; Doom Modeline
(use-package doom-modeline
  :demand t
  :init
  (doom-modeline-mode 1)
  :config
  (setq doom-modeline-height 25
        doom-modeline-bar-width 4
        doom-modeline-icon t
        doom-modeline-major-mode-icon t
        doom-modeline-minor-modes nil))


;; Rainbow delimeters
(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

;; Helpful
(use-package helpful
  :commands (helpful-callable helpful-variable helpful-key helpful-macro helpful-command helpful-mode)
  :demand t
  :config
  ;; Integrate Helpful into General.el leader keys
  (with-eval-after-load 'general
    (general-define-key
     :states '(normal visual emacs)
     :keymaps 'override
     :prefix me-leader-key
     "h"  '(:ignore t :which-key "help")
     "hf" '(helpful-callable :which-key "describe function")
     "hv" '(helpful-variable :which-key "describe variable")
     "hk" '(helpful-key :which-key "describe key")
     "hx" '(helpful-command :which-key "describe command")
     ; Helpful doesn't have a helpful-mode - so use describe-mod
     "hm" '(describe-mode :which-key "describe mode"))))

(add-to-list 'display-buffer-alist
             '("\\*\\(Help\\|helpful.*\\)\\*"
               (display-buffer-reuse-mode-window display-buffer-at-bottom)
               (window-height . 0.35)
               (body-function . select-window)))

;; Fonts
(defun my/setup-fonts ()
  "Configure fonts across operating systems without Doom macros."
  (cond
   ;; Windows Setup (Cascadia Code @ 48pt)
   ;; For when you're unfortunate enough to be using...shudder...windows
   ((eq system-type 'windows-nt)
    (let ((font-to-use "Cascadia Code"))
      (set-face-attribute 'default nil :font font-to-use :height 480)
      (set-face-attribute 'fixed-pitch nil :font font-to-use :height 1.0)
      (set-face-attribute 'variable-pitch nil :font font-to-use :height 1.0)))

   ;; Non-Windows Setup (Default OS font @ 18pt)
   ;; For when life is good
   (t
    (set-face-attribute 'default nil :height 150)
    (set-face-attribute 'fixed-pitch nil :height 1.0)
    (set-face-attribute 'variable-pitch nil :height 1.0))))

;; Apply fonts on startup (handles GUI frame & daemon startup)
(if (daemonp)
    (add-hook 'server-after-make-frame-hook
              (lambda (frame)
                (with-selected-frame frame (my/setup-fonts))))
  (my/setup-fonts))

;; Relative line numbers
(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode 1)
;; Disable line numbers in specific modes where they don't make sense
(dolist (mode '(term-mode-hook
                shell-mode-hook
                eshell-mode-hook
                dired-mode-hook
                help-mode-hook
                magit-status-mode-hook))
  (add-hook mode (lambda () (display-line-numbers-mode 0))))

;; 2. Dark Title Bar on macOS
(when (eq system-type 'darwin)
  (add-to-list 'default-frame-alist '(ns-appearance . dark))
  (add-to-list 'default-frame-alist '(ns-transparent-titlebar . t)))

(use-package hl-line
  :ensure nil
  :demand t
  :config
  (setq hl-line-sticky-flag t)
  
  ;; Optional: Customize background color to make it clearly visible
  ;; (adjust hex code to match your theme preference)
  ;(custom-set-faces
  ; '(hl-line ((t (:background "#2d3139" :extend t)))))

  (global-hl-line-mode 1))

(provide 'modules/ui)
;;; icons.el ends here
