(setq inhibit-startup-message t)
(tool-bar-mode -1) ; only applies in gui emacs
(menu-bar-mode -1)
(setq visible-bell nil)

;; ;;;;;;;;;;;;;;;;;;
;; Setup use package
;; ;;;;;;;;;;;;;;;;;;
(require 'package)

(setq package-archives '(("melpa" . "https://melpa.org/packages/")
                         ("melpa-stable" . "https://stable.melpa.org/packages/")
                         ("org" . "https://orgmode.org/elpa/")
                         ("elpa" . "https://elpa.gnu.org/packages/")))
(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))

(unless (package-installed-p 'use-package)
        (package-install 'use-package))

(require 'use-package)
(setq use-package-always-ensure t) ; Set :ensure t for all use-package calls


;; All the icons (required for doom themes)
(use-package all-the-icons
  :ensure t)
;; doom-themes
(use-package doom-themes
  :ensure t
  :config
  ;; Global settings (defaults)
  (setq 
    doom-themes-enable-bold t    ; if nil, bold is universally disabled
    doom-themes-enable-italic t) ; if nil, italics is universally disabled
  (load-theme 'doom-one t)
  ;; Enable flashing mode-line on errors
  (doom-themes-visual-bell-config)
  ;; Enable custom neotree theme (all-the-icons must be installed!)
  (doom-themes-neotree-config)
  ;; or for treemacs users
  (setq doom-themes-treemacs-theme "doom-atom") ; use "doom-colors" for less minimal icon theme
  (doom-themes-treemacs-config)
  ;; Corrects (and improves) org-mode's native fontification.
  (doom-themes-org-config))

;; Modeline from doom
(use-package doom-modeline
  :init (doom-modeline-mode 1))

;; Recent files
(require 'recentf)
(recentf-mode t)
(setq recentf-max-menu-items 25)
(setq recentf-max-saved-items 25)

;;;;;;;;;;;;;
;; Evil Mode
;;;;;;;;;;;;;
(use-package evil
  :init
  (setq evil-want-integration t) ;; This is optional since it's already set to t by default.
  (setq evil-want-keybinding nil)
  :config (evil-mode t))

(evil-set-leader 'normal (kbd "SPC"))
(evil-define-key 'normal 'global (kbd "<leader>ff") #'find-file)

;; evil everywhere
(use-package evil-collection
  :after evil
  :ensure t
  :config
  (evil-collection-init))

;;;;;;;;;;
;; magit
;;;;;;;;;;
(use-package magit
  :ensure t)

;;;;;;;;;;;;;;;;
;; projectile
;;;;;;;;;;;;;;;;
(use-package projectile 
  :ensure t
  :init (projectile-mode +1)
  :config 
  (define-key projectile-mode-map (kbd "C-c p") 'projectile-command-map)
)  

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Minibuffer completion
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Vertico (what doom uses)
(use-package vertico
  :custom
  (vertico-resize nil)
  (vertico-cycle t)
  :bind (:map vertico-map
         ("C-w" . backward-kill-word))
  :init
  (vertico-mode))

;;;;;;;;;;;;;;;;;;;
;; Editor settings
;;;;;;;;;;;;;;;;;;;

;; Automatically add ending brackets and braces
(electric-pair-mode 1)

;; Make sure tab-width is 4 and not 8
(setq-default tab-width 4)

