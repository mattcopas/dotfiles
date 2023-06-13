(defconst dotfiles-directory "~/git/dotfiles/")
(defconst dotfiles-emacs-directory (concat dotfiles-directory "emacs/"))
(org-babel-load-file (concat dotfiles-emacs-directory "configuration.org"))
