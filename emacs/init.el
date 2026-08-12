;; Add the lisp directory to user-emacs-directory, so we can require them in here
;; By doing this, we have to 'require' using the subdirectory (modules/evil)
;; This is preferable to just (require 'evil) because it can cause clashes (eg with which-key)
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

;; Load the package manager module - this must come before any other modules
(require 'modules/package-manager)

(require 'modules/globals)
(when (eq system-type 'darwin)
  (require 'modules/macos))
(require 'modules/evil)
(require 'modules/which-key)
(require 'modules/ui)
(require 'modules/completion)
(require 'modules/snippets)
(require 'modules/git)
(require 'modules/project)
(require 'modules/tidy-backup)
(require 'modules/org)
(require 'modules/editor)
(require 'modules/languages/java)
(require 'modules/ai)

;; Start emacs in server mode so that emacsclient can be used
;; eg for IntelliJ to jump over to magit
(server-start)
