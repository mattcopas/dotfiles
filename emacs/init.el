(require 'package)
 

;; Add package archives
(add-to-list 'package-archives '("org" . "http://orgmode.org/elpa/"))
(add-to-list 'package-archives '("melpa" . "http://melpa.org/packages/"))
(add-to-list 'package-archives '("melpa-stable" . "http://stable.melpa.org/packages/"))
 
(setq package-enable-at-startup nil)
(package-initialize)


;; Setup use-package
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(eval-when-compile
  (require 'use-package))

;; Theme + UI stuff
(setq inhibit-startup-message t)
(scroll-bar-mode -1)
(tool-bar-mode -1)
(menu-bar-mode -1)
(tooltip-mode -1)
(set-fringe-mode 10)
(load-theme 'tango-dark)

;; Fonts
(defun font-exists-p (font) "check if font exists" (if (null (x-list-fonts font)) nil t))
(if (font-exists-p "MesloLGL NF") 
  (add-to-list 'default-frame-alist '(font . "MesloLGL NF" ))
  (set-face-attribute 'default t :font "MesloLGL NF" ))

;;;;;;;;;;;;
;; Packages
;;;;;;;;;;;;

;; evil mode
(use-package evil
  :ensure t)
;; Start evil-mode - do this asap so that if anything else breaks we still get evil bindings
(require 'evil)
(evil-mode t)
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   (quote
	(lsp-java helm-lsp lsp-ui dap-mode flycheck markdown-mode use-package evil-visual-mark-mode))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

;; magit
(use-package magit
  :ensure t)

;; projectile
(use-package projectile 
  :ensure t
  :init (projectile-mode +1)
  :config 
  (define-key projectile-mode-map (kbd "C-c p") 'projectile-command-map)
)  

;; helm
(use-package helm
  :ensure t
  :init 
  (helm-mode 1)
  (progn (setq helm-buffers-fuzzy-matching t))
  :bind
  (("C-c h" . helm-command-prefix))
  (("M-x" . helm-M-x))
  (("C-x C-f" . helm-find-files))
  (("C-x b" . helm-buffers-list))
  (("C-c b" . helm-bookmarks))
  (("C-c f" . helm-recentf))   ;; Add new key to recentf
  (("C-c g" . helm-grep-do-git-grep))  ;; Search using grep in a git project; Helm (command completion)
  )

;; Company (code auto completion)
(use-package company
  :ensure t)

;; yansnippet (snippets/templating)
(use-package yasnippet :config (yas-global-mode))
(use-package yasnippet-snippets :ensure t)

;; FlyCheck (code checking)
(use-package flycheck :ensure t :init (global-flycheck-mode))

;; lsp-mode
(use-package lsp-mode
:ensure t
:hook (
   ;; (lsp-mode . lsp-enable-which-key-integration)
   (java-mode . #'lsp-deferred)
)
:init (setq 
    lsp-keymap-prefix "C-c l"              ; this is for which-key integration documentation, need to use lsp-mode-map
    lsp-enable-file-watchers nil
    read-process-output-max (* 1024 1024)  ; 1 mb
    lsp-completion-provider :capf
    lsp-idle-delay 0.500
)
:config 
    (setq lsp-intelephense-multi-root nil) ; don't scan unnecessary projects
    (with-eval-after-load 'lsp-intelephense
    (setf (lsp--client-multi-root (gethash 'iph lsp-clients)) nil))
	(define-key lsp-mode-map (kbd "C-c l") lsp-command-map)
)

;; Debug Adapter Protocol (DAP)
(use-package dap-mode
  :ensure t
  :after (lsp-mode)
  :functions dap-hydra/nil
  :config
  (require 'dap-java)
  :bind (:map lsp-mode-map
         ("<f5>" . dap-debug)
         ("M-<f5>" . dap-hydra))
  :hook ((dap-mode . dap-ui-mode)
    (dap-session-created . (lambda (&_rest) (dap-hydra)))
    (dap-terminated . (lambda (&_rest) (dap-hydra/nil)))))

;; Treemacs (provides UI elements for LSP UI)
(use-package lsp-treemacs
  :after (lsp-mode treemacs)
  :ensure t
  :commands lsp-treemacs-errors-list
  :bind (:map lsp-mode-map
         ("M-9" . lsp-treemacs-errors-list)))

(use-package treemacs
  :ensure t
  :commands (treemacs)
  :after (lsp-mode))

;; LSP UI
(use-package lsp-ui
  :ensure t
  :after (lsp-mode)
  :bind (:map lsp-ui-mode-map
         ([remap xref-find-definitions] . lsp-ui-peek-find-definitions)
         ([remap xref-find-references] . lsp-ui-peek-find-references))
  :init (setq lsp-ui-doc-delay 1.5
      lsp-ui-doc-position 'bottom
	  lsp-ui-doc-max-width 100
))

;; Helm LSP
(use-package helm-lsp
  :ensure t
  :after (lsp-mode)
  :commands (helm-lsp-workspace-symbol)
  :init (define-key lsp-mode-map [remap xref-find-apropos] #'helm-lsp-workspace-symbol))

;; LSP Java
(use-package lsp-java 
  :ensure t
  :config (add-hook 'java-mode-hook 'lsp))

;;;;;;;;;;;;;;;;;;;
;; Editor settings
;;;;;;;;;;;;;;;;;;;

;; Automatically add ending brackets and braces
(electric-pair-mode 1)

;; Make sure tab-width is 4 and not 8
(setq-default tab-width 4)

;;;;;;;;;;;;;;;;;;;
;; LSP settings
;;;;;;;;;;;;;;;;;;;

;; Start LSP server
(require 'lsp-mode)
