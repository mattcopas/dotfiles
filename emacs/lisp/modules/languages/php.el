;;; php.el --- PHP -*- lexical-binding: t; -*-

;;; Commentary:
;; 

;;; Code:

;; Core PHP major mode
(use-package php-mode
  :ensure t
  :mode "\\.php\\'"
  :hook ((php-mode . (lambda ()
                       (setq-local tab-width 4
                                   indent-tabs-mode nil))))
  :custom
  (php-mode-coding-style 'psr2))

;; Blade templates (Laravel's .blade.php)
;; Uses add-to-list rather than setq so this composes safely with any
;; web-mode config from your React/JSX setup elsewhere.
(use-package web-mode
  :ensure t
  :mode "\\.blade\\.php\\'"
  :config
  (add-to-list 'web-mode-engines-alist '("blade" . "\\.blade\\.")))

;; LSP via Intelephense or Phpactor — using eglot (built-in since Emacs 29)
(use-package eglot
  :ensure nil
  :hook ((php-mode . eglot-ensure))
  :config
  (add-to-list 'eglot-server-programs
               '(php-mode . ("intelephense" "--stdio"))))
;; Swap for Phpactor instead:
;; '(php-mode . ("phpactor" "language-server"))

;; Composer / project awareness (Laravel apps are Composer projects)
(use-package composer
  :ensure t)

;; Flycheck: phpcs / phpstan
(use-package flycheck
  :ensure t
  :hook (php-mode . flycheck-mode)
  :config
  (flycheck-add-next-checker 'php 'php-phpcs)
  (setq flycheck-phpcs-standard "PSR12"))

;; Formatting on save with php-cs-fixer
(use-package apheleia
  :ensure t
  :config
  (setf (alist-get 'php-cs-fixer apheleia-formatters)
        '("php-cs-fixer" "fix" "--using-cache=no" filepath))
  (setf (alist-get 'php-mode apheleia-mode-alist) 'php-cs-fixer)
  (apheleia-global-mode +1))

;; Inline documentation lookups
(use-package php-eldoc
  :ensure t
  :hook (php-mode . php-eldoc-enable))

;; PHPUnit test runner
(use-package phpunit
  :ensure t
  :hook (php-mode . (lambda ()
                      (local-set-key (kbd "C-c C-t C-c") #'phpunit-current-class)
                      (local-set-key (kbd "C-c C-t C-m") #'phpunit-current-test)
                      (local-set-key (kbd "C-c C-t C-p") #'phpunit-current-project))))

;; ---------------------------------------------------------------------------
;; Laravel project detection — works with either project.el or Projectile,
;; whichever this config actually has active. Detected at load time so
;; switching between them later doesn't require editing this file.
;;
;; NOTE: (featurep 'projectile) only reflects reality if Projectile's module
;; loads *before* this file in your init.el. If load order isn't guaranteed
;; (e.g. async Elpaca loading), consider replacing the featurep check below
;; with an explicit `me-project-backend` variable set once near the top of
;; your config instead.
;; ---------------------------------------------------------------------------

(defun me-laravel-project-root ()
  "Return the project root if it looks like a Laravel app, else nil."
  (locate-dominating-file default-directory "artisan"))

(if (featurep 'projectile)
    ;; --- Projectile branch ---
    (with-eval-after-load 'projectile
      (projectile-register-project-type 'laravel '("artisan" "composer.json")
                                        :project-file "artisan"
                                        :compile "composer install"
                                        :test "php artisan test"
                                        :run "php artisan serve"))

  ;; --- project.el branch (current default) ---
  (with-eval-after-load 'project
    (defun me-project-try-laravel (dir)
      (when-let ((root (locate-dominating-file dir "artisan")))
        (cons 'laravel root)))

    (cl-defmethod project-root ((project (head laravel)))
      (cdr project))

    (add-hook 'project-find-functions #'me-project-try-laravel)))

(defun me-laravel-setup ()
  "Set compile-command and keybindings when visiting a Laravel project file."
  (when-let ((root (me-laravel-project-root)))
    (setq-local default-directory root)
    (setq-local compile-command "php artisan test")
    (local-set-key (kbd "C-c C-t C-p")
                   (lambda () (interactive)
                     (let ((default-directory root))
                       (compile "php artisan test"))))
    (local-set-key (kbd "C-c C-r")
                   (lambda () (interactive)
                     (let ((default-directory root))
                       (async-shell-command "php artisan serve"))))))

(add-hook 'php-mode-hook #'me-laravel-setup)

(me/configure-mason-for-mode 'php-mode "intelephense")

(provide 'modules/languages/php)
;;; php.el ends here
