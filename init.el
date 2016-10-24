(require 'package)
(setq package-archives
 (append package-archives
         '(("melpa" . "http://melpa.org/packages/")
           ("melpa-stable" . "http://melpa-stable.milkbox.net/packages/"))))
(package-initialize)

(dolist (package '(paredit clojure-mode inf-clojure markdown-mode))
  (unless (package-installed-p package)
    (package-install package)))

;; manage emacs save files in a separate directory to avoid clutter
(setq
  backup-by-copying t
  delete-old-versions t
  kept-new-versions 6
  kept-old-versions 2
  version-control t)
(setq backup-directory-alist
      `((".*" . "/tmp/")))
(setq auto-save-file-name-transforms
      `((".*" "/tmp/" t)))

;; ensure environment variables inside Emacs look the same as in the user's shell
;; (only a problem on Macs)
(when (memq window-system '(mac ns))
  (exec-path-from-shell-initialize))

;; convenient for adding timestamps to files
(defun insert-time ()
  (interactive)
  (insert (format-time-string "%a %b %d %H:%M:%S %Z %Y")))

;; Paredit overshadows the C-j bindings in lisp interaction mode, so use S-return instead
(define-key lisp-interaction-mode-map [S-return] 'eval-print-last-sexp)

;; clojurescript-mode files
(add-to-list 'auto-mode-alist '("\\.cljs$" . clojurescript-mode))
(add-to-list 'auto-mode-alist '("\\.hl$" . clojurescript-mode))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; clojure-mode
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun setup-clojure-mode ()
  ;; Buffer local variables are not visible in mode hooks
  (add-hook 'hack-local-variables-hook
            (lambda ()
              (when use-inf-clojure
                (inf-clojure-minor-mode 1)
                (eldoc-mode 1)))
            nil
            t)
  (paredit-mode 1)
  (setq show-trailing-whitespace t)
  (flyspell-mode 0)
  (when (and (not use-inf-clojure)
             (fboundp 'clojure-enable-nrepl))
    (clojure-enable-nrepl))
  (define-key clojure-mode-map (kbd "C-c e") 'shell-eval-last-expression)
  (define-key clojure-mode-map (kbd "C-c x") 'shell-eval-defun)
  (define-key clojure-mode-map (kbd "C-c C-e") 'lisp-eval-last-sexp)
  (define-key clojure-mode-map (kbd "C-x C-e") 'lisp-eval-last-sexp)
  ;; Fix the keys that paredit screws up
  (define-key paredit-mode-map (kbd "<C-left>") nil)
  (define-key paredit-mode-map (kbd "<C-right>") nil)
  ;; And define some new bindings since the OS eats some of the useful ones
  (define-key paredit-mode-map (kbd "<C-S-left>") 'paredit-backward-slurp-sexp)
  (define-key paredit-mode-map (kbd "<C-S-right>") 'paredit-forward-slurp-sexp)
  (define-key paredit-mode-map (kbd "<M-S-left>") 'paredit-backward-barf-sexp)
  (define-key paredit-mode-map (kbd "<M-S-right>") 'paredit-forward-barf-sexp)
  ;; Not all terminals can transmit the standard key sequencences for
  ;; paredit-forward-slurp-sexp, which is super-useful
  (define-key paredit-mode-map (kbd "C-c )") 'paredit-forward-slurp-sexp)
  (define-key paredit-mode-map (kbd "M-)") 'paredit-forward-slurp-sexp)
  (when use-inf-clojure
    (define-key clojure-mode-map (kbd "M-.") 'dumb-jump-go)
    (define-key clojure-mode-map (kbd "M-,") 'dumb-jump-back)))

(add-hook 'clojure-mode-hook #'setup-clojure-mode)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; inf-clojure
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(add-hook 'inf-clojure-mode-hook
          (lambda ()
            (paredit-mode 1)
            (eldoc-mode 1)))

(require 'inf-clojure)

(defvar use-inf-clojure nil
  "If true, indicate that clojure-mode should also set up to use inf-clojure-minor-mode")

(defun inf-clojure-jack-in (dir cmd name)
  "Starts a new inf-clojure process and renames the resulting
  buffer to whatever inf-clojure-buffer is set to. To get the
  defaults to fill in correctly, use a .dir-locals.el that looks
  like this:
((clojure-mode
  (inf-clojure-buffer . \"requestinator-repl\")
  (use-inf-clojure-program . \"lein repl\")
  (use-inf-clojure . t)))
"
  (interactive (let* ((dir (read-directory-name "Project directory: "
                                                        default-directory
                                                        nil
                                                        t))
                              (_   (switch-to-buffer-other-window "*inf-clojure*"))
                              (_   (cd dir))
                              (_   (hack-dir-local-variables-non-file-buffer))
                              (dir-vars (cdr
                                         (assoc 'clojure-mode
                                                (assoc-default dir
                                                               dir-locals-class-alist
                                                               #'(lambda (i k)
                                                                   (file-equal-p k (symbol-name i)))))))
                              (cmd (read-string "Run Clojure: "
                                                (assoc-default 'use-inf-clojure-program
                                                               dir-vars)))
                              (name (read-buffer "REPL buffer name: "
                                                 (assoc-default 'inf-clojure-buffer
                                                                dir-vars))))
                 (list dir cmd name)))
  (inf-clojure cmd)
  (rename-buffer name)
  ;; Re-enable inf-clojure-minor-mode in all open clojure-mode buffers
  ;; for this project, since eldoc and completion don't work if you
  ;; start the REPL later.
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (and (derived-mode-p 'clojure-mode)
                 (file-equal-p dir (inf-clojure-project-root)))
        (inf-clojure-minor-mode 1)))))

;; Make it so that I can set inf-clojure-buffer in a .dir-locals.el file
(put 'inf-clojure-buffer 'safe-local-variable #'stringp)
(put 'use-inf-clojure-program 'safe-local-variable #'stringp)
(put 'use-inf-clojure 'safe-local-variable #'booleanp)

;; Redefine C-c C-c since I always wind up killing the process
(defun comint-prevent-idiocy ()
  (interactive)
  (ding)
  (message "Command disabled because Craig is stupid. Use M-x comint-interrupt-subjob if you really meant it."))
(define-key inf-clojure-mode-map (kbd "C-c C-c") 'comint-prevent-idiocy)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Support paredit for better paren
;;; editing in Lisp mode
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(autoload 'paredit-mode "paredit"
  "Minor mode for pseudo-structurally editing Lisp code."
  t)
(add-hook 'lisp-mode-hook '(lambda () (paredit-mode +1)))
(add-hook 'emacs-lisp-mode-hook '(lambda () (paredit-mode +1)))

(show-paren-mode t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; ui stuff
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; set font to something readable
(set-face-attribute 'default nil :height 140)

;; initial size of EMACS
(setq initial-frame-alist '((top . 0) (left . 0) (width . 87) (height . 53)))

;; prevent EMACS from displaying it's cute splash screen
(setq inhibit-splash-screen t)

;; I prefer y/n to yes/no queries
(defalias 'yes-or-no-p 'y-or-n-p)

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(custom-enabled-themes (quote (tango-dark)))
 '(initial-buffer-choice "~/.emacs.d/init.el")
 '(show-paren-mode t))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
