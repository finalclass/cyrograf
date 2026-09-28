;;; cyrograf-mode.el --- Major mode for Cyrograf contracts  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Cyrograf contributors
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; Editing support for Cyrograf contract files (".cyrograf").
;;
;; The mode provides syntax recognition, font-lock, `//' line comments and
;; basic brace indentation. Language intelligence (diagnostics, navigation and
;; formatting) comes from the external `cyrograf lsp' process, wired into
;; Eglot. Loading this file never starts a server: Eglot starts `cyrograf lsp'
;; only when Eglot is enabled in a Cyrograf buffer.
;;
;; Clone https://github.com/finalclass/cyrograf.git to
;; ~/.local/share/cyrograf, then add this to init.el:
;;
;;   (add-to-list 'load-path
;;                (expand-file-name "~/.local/share/cyrograf/editors/emacs"))
;;   (require 'cyrograf-mode)
;;
;; For Doom Emacs declare the GitHub package in `packages.el':
;;
;;   (package! cyrograf-mode
;;     :recipe (:host github
;;              :repo "finalclass/cyrograf"
;;              :files ("editors/emacs/cyrograf-mode.el")))
;;
;; Configure the mode in `config.el':
;;
;;   (use-package! cyrograf-mode
;;     :mode "\\.cyrograf\\'"
;;     :hook (cyrograf-mode . eglot-ensure))
;;
;; Run `doom sync' and restart Emacs after adding the package.
;;
;; The program path is customizable through `cyrograf-lsp-program'; it may
;; contain spaces because the command is passed as a list, never as a shell
;; string.

;;; Code:

(require 'prog-mode)
(require 'syntax)

(defgroup cyrograf nil
  "Editing support for Cyrograf contracts."
  :group 'languages
  :prefix "cyrograf-")

(defcustom cyrograf-lsp-program "cyrograf"
  "Path to the Cyrograf program used for `cyrograf lsp'.
The value may contain spaces; it is passed to the process directly and never
interpreted by a shell."
  :type 'string
  :group 'cyrograf)

(defcustom cyrograf-lsp-args '("lsp")
  "Arguments passed to `cyrograf-lsp-program' to start the language server."
  :type '(repeat string)
  :group 'cyrograf)

(defcustom cyrograf-indent-offset 2
  "Number of spaces used for one level of indentation."
  :type 'integer
  :group 'cyrograf)

(defvar cyrograf-mode-syntax-table
  (let ((table (make-syntax-table prog-mode-syntax-table)))
    (modify-syntax-entry ?/ "." table)
    (modify-syntax-entry ?\n ">" table)
    (modify-syntax-entry ?_ "_" table)
    (modify-syntax-entry ?. "." table)
    (modify-syntax-entry ?{ "(}" table)
    (modify-syntax-entry ?} "){" table)
    (modify-syntax-entry ?\( "()" table)
    (modify-syntax-entry ?\) ")(" table)
    (modify-syntax-entry ?\[ "(]" table)
    (modify-syntax-entry ?\] ")[" table)
    table)
  "Syntax table for `cyrograf-mode'.")

(defconst cyrograf--primitive-re
  (regexp-opt '("String" "Int" "Float" "Bool" "Void" "Date" "Record" "List"))
  "Regexp matching Cyrograf primitive type names.")

(defconst cyrograf-font-lock-keywords
  (list
   ;; Declarations: the contextual keywords immediately before a name.
   (list (concat "\\_<\\(struct\\|variant\\)\\_>\\s-+\\([A-Z][A-Za-z0-9_]*\\)")
         '(1 font-lock-keyword-face)
         '(2 font-lock-type-face))
   (list (concat "\\_<\\(rpc\\)\\_>\\s-+\\([a-z][A-Za-z0-9_]*\\)")
         '(1 font-lock-keyword-face)
         '(2 font-lock-function-name-face))
   ;; Primitive names in a type position.
   (list (concat "[:[(<]\\s-*\\(" cyrograf--primitive-re "\\)\\_>")
         '(1 font-lock-type-face))
   ;; Named message and module types.
   (list "\\_<\\([A-Z][A-Za-z0-9_]*\\)\\_>"
         '(1 font-lock-type-face))
   ;; Struct fields and method names.
   (list "^\\s-*\\([a-z][A-Za-z0-9_]*\\)\\s-*[?]?\\s-*:"
         '(1 font-lock-variable-name-face))
   (list "\\_<\\(rpc\\)\\_>\\s-+\\([a-z][A-Za-z0-9_]*\\)"
         '(1 font-lock-keyword-face)
         '(2 font-lock-function-name-face)))
  "Font-lock rules for `cyrograf-mode'.")

(defun cyrograf-syntax-propertize (start end)
  "Mark `//' line comments between START and END."
  (goto-char start)
  (while (re-search-forward "\\(//\\)" end t)
    (put-text-property (match-beginning 1) (match-end 1)
                       'syntax-table (string-to-syntax "<")))
  nil)

(defun cyrograf--line-depth (line-end)
  "Return the brace depth just before LINE-END, ignoring `//' comments."
  (let ((depth 0))
    (save-excursion
      (goto-char (point-min))
      (while (< (point) line-end)
        (let ((ch (char-after)))
          (cond
           ((and (eq ch ?/) (eq (char-after (1+ (point))) ?/))
            (end-of-line))
           ((eq ch ?{) (setq depth (1+ depth)) (forward-char))
           ((eq ch ?}) (setq depth (max 0 (1- depth))) (forward-char))
           (t (forward-char))))))
    depth))

(defun cyrograf-indent-line ()
  "Indent the current line according to the surrounding braces."
  (interactive)
  (let* ((bol (save-excursion (beginning-of-line) (point)))
         (first-line (= bol (point-min)))
         (prev-end (save-excursion
                     (goto-char bol)
                     (forward-line -1)
                     (line-end-position)))
         (depth (if (or first-line (<= prev-end (point-min)))
                    0
                  (cyrograf--line-depth prev-end))))
    (save-excursion
      (goto-char bol)
      (when (looking-at "\\s-*}")
        (setq depth (max 0 (1- depth)))))
    (indent-line-to (* depth cyrograf-indent-offset))))

;;;###autoload
(define-derived-mode cyrograf-mode prog-mode "Cyrograf"
  "Major mode for editing Cyrograf contract files."
  :syntax-table cyrograf-mode-syntax-table
  (setq-local comment-start "//")
  (setq-local comment-end "")
  (setq-local comment-start-skip "//+\\s-*")
  (setq-local parse-sexp-ignore-comments t)
  (setq-local font-lock-defaults '(cyrograf-font-lock-keywords nil nil nil nil))
  (setq-local syntax-propertize-function #'cyrograf-syntax-propertize)
  (setq-local indent-line-function #'cyrograf-indent-line)
  (setq-local indent-tabs-mode nil)
  (setq-local tab-width cyrograf-indent-offset))

(defun cyrograf-eglot-contact (&rest _)
  "Return the Eglot command line for `cyrograf lsp'.
The program and its arguments are returned as a list so a path containing
spaces is not split by a shell."
  (append (list cyrograf-lsp-program) cyrograf-lsp-args))

;;;###autoload
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(cyrograf-mode . cyrograf-eglot-contact)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.cyrograf\\'" . cyrograf-mode))

(defun cyrograf-register-markdown-language ()
  "Register `cyrograf-mode' for `cyrograf' fenced blocks.
Adds the mapping used by `markdown-fontify-code-blocks-natively' in
`markdown-mode' and `gfm-mode'.  The mapping is added only once."
  (add-to-list 'markdown-code-lang-modes '("cyrograf" . cyrograf-mode)))

(with-eval-after-load 'markdown-mode
  (cyrograf-register-markdown-language))

(provide 'cyrograf-mode)
;;; cyrograf-mode.el ends here
