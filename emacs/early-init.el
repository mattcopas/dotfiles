;; Silence native compiler warnings during background package compilation
;; To view these, see the *Warnings* buffer
(setq native-comp-async-report-warnings-errors 'silent)

;; kill package.el as we're using elpaca
(setq package-enable-at-startup nil)

;; Disable UI clutter before window draws to prevent flash of unstyled content
;; Doing  these via default-frame-alist removes the stutter you get at the start
;; when using stuff like (menu-bar-mode -1)
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(scroll-bar-mode . nil) default-frame-alist)
(setq inhibit-startup-message t)
(setq visible-bell nil)
(add-to-list 'initial-frame-alist '(fullscreen . maximized))
