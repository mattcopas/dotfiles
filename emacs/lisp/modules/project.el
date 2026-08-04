;;; project.el --- Projectile config -*- lexical-binding: t; -*-

;;; Commentary:
;; 

;;; Code:

;; Projectile Core Configuration
(use-package projectile
  :demand t
  :init
  (projectile-mode +1)
  :config
  ;; Cache projects for speed and set clean cache path
  (setq projectile-enable-caching t
        projectile-sort-order 'recently-active
        projectile-cache-file (expand-file-name "projectile.cache" me-local-cache-directory)
        projectile-known-projects-file (expand-file-name "projectile-bookmarks.eld" me-local-cache-directory))

  ;; Ignore common build/dependency folders to keep search fast
 (setq projectile-globally-ignored-directories
        (append projectile-globally-ignored-directories
                '(".git" "node_modules" "target" "elpaca" ".cache" "build" "dist"))))
  ;; Allow Projectile to search up to 3 or 4 levels deep into folders
  (setq projectile-project-search-path '("~/git" "~/playground" "~/code" "~/projects" "~/.config"))
  
  ;; Set max directory depth during auto-discovery (Default is 1)
  (setq projectile-auto-discover-max-depth 4)

  ;; Put projectile's cache in.... the cache folder
  (setq projectile-cache-file (expand-file-name "projectile.cache" me-local-cache-directory)
       projectile-known-projects-file (expand-file-name ".projectile-bookmarks.eld" me-local-cache-directory))

(setq projectile-frecency-file 
      (expand-file-name "projectile-frecency.eld" me-local-cache-directory))

;; General Leader Keybindings for Projectile
(with-eval-after-load 'general
  (general-define-key
   :states '(normal visual emacs)
   :keymaps 'override
   :prefix me-leader-key
   "p"  '(:ignore t :which-key "project")
   "pp" '(projectile-switch-project :which-key "switch project")
   me-leader-key '(projectile-find-file :which-key "find file in project")
   "sp" '(consult-ripgrep :which-key "search in project")
   "pb" '(projectile-switch-to-buffer :which-key "switch project buffer")
   "pk" '(projectile-kill-buffers :which-key "kill project buffers")
   "pr" '(projectile-recentf :which-key "recent project files")
   "pD" '(projectile-dired :which-key "open project root in dired")))

(provide 'modules/project)
;;; project.el ends here
