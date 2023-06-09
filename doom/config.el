;; This tangles the org file and runs that.
;; Note that the org file must NOT be called config.org
;; otherwise the org file gets tanged into config.el which causes an
;; infinite loop
(org-babel-load-file "~/git/dotfiles/doom/configuration.org")
