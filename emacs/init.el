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
;; Use project OR projectile - keybinds will clash otherwise!
(require 'modules/project/project)
(require 'modules/tidy-backup)
(require 'modules/org)
(require 'modules/editor)
;; Put this BEFORE any languages - then those languages can use mason to auto install lsp servers
(require 'modules/mason)
(require 'modules/languages/java)
(require 'modules/languages/yaml)
(require 'modules/languages/markdown)
(require 'modules/ai)
(require 'modules/server)
(require 'modules/pdf)
