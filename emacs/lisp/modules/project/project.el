;;; project.el --- Project.el config -*- lexical-binding: t; -*-

;;; Commentary:
;; 

;;; Code:
(use-package project
  :ensure nil
  :config
  ;; Instead of the dispatch menu, just go straight to find file when switching project
  (setq project-switch-commands #'project-find-file)
  ;; Tell project.el where your code lives for quick switching
  (defun me-discover-projects ()
    (interactive)
    (message "Discovering projects...")
    (async-start
     (lambda ()
       (require 'project)
       (project-remember-projects-under "~/git" t)
       (project-remember-projects-under "~/playground" t)
       (project-remember-projects-under "~/.config")
       ;; Call this last, so that the secondl lambda receives all the projects discovered in this asnyc process
       (project-known-project-roots))

     (lambda (result)
       (require 'project)
       (when (listp result)
	 (dolist (project-directory result)
	   (message "Discovered project %s" project-directory)
	   (project-remember-project (cons 'transient project-directory))))
       (message "Finished discovering projects")))))

(with-eval-after-load 'general
  (general-define-key
   :states '(normal visual emacs)
   :keymaps 'override
   :prefix me-leader-key
   "p"  '(:ignore t :which-key "project")
   "pp" '(project-switch-project :which-key "switch project")
   me-leader-key '(project-find-file :which-key "find file in project")
   "sp" '(consult-ripgrep :which-key "search in project")
   "pb" '(project-switch-to-buffer :which-key "switch project buffer")
   "pk" '(project-kill-buffers :which-key "kill project buffers")
   "pr" '(project-recentf :which-key "recent project files")
   "pD" '(project-dired :which-key "open project root in dired")))

(provide 'modules/project/project)
;;; project.el ends here
