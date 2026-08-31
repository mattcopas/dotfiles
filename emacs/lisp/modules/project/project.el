;;; project.el --- Project.el config -*- lexical-binding: t; -*-

;;; Commentary:
;; 

;;; Code:
(defvar me-project-directories '(
				("~/git" . t)
				("~/playground" . t)
				"~/.config"
				"~/.mt5/drive_c/Program Files/MetaTrader 5/MQL5/Experts/Advisors")
  "Project directories. These are discovered by project,el when me-discover-projects is invoked.
Elements can either be a conse cell (DIRECTORY . RECURSIVEP) or a string. RECURSIVEP determines if recursion should be used or not. For strings, recursion is not used.")

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
     ;; This needs a backtick so we can evaluate me-project-directories when the lambda is constructed. We can't just call the variable, as doing this
     ;; with async start means we're in a new emacs process, so the variable won't be available
     ;; The async call is also the reason we have to (require 'project) in the lambda.
     `(lambda ()
       (require 'project)
       (dolist (entry ',me-project-directories)
	 (if (consp entry)
	     (project-remember-projects-under (car entry) (cdr entry))
	   (project-remember-projects-under entry)))
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
