;; This tangles the org file and runs that.
;; Note that the org file must NOT be called config.org
;; otherwise the org file gets tanged into config.el which causes an
;; infinite loop
(defconst dotfiles-doom-directory "~/git/dotfiles/doom/")
(org-babel-load-file (concat dotfiles-doom-directory "configuration.org"))
