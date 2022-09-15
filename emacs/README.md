# Emacs from scratch

**Note for iTerm2 on MacOS**
Left Option needs to be remapped to Esc+, not Meta! This can be done via iTerm2 Preferences > Profiles > Keys
To use this emacs, copy into your ~/.emacs file (or ~/.emacs.d/init.el):

```
(setq user-emacs-directory "~/git/dotfiles/emacs")
(setq user-init-file "~/git/dotfiles/emacs/init.el")
(load user-init-file)
```
