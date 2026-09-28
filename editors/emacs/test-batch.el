;;; test-batch.el --- Batch checks for cyrograf-mode  -*- lexical-binding: t; -*-

;; Runs under `emacs --batch'. It verifies mode activation, font-lock faces,
;; `//' comment handling, brace indentation and the Eglot registration,
;; without ever starting the language server.

;;; Code:

(require 'seq)

(defvar cyrograf-test--failures 0)
(defvar cyrograf-test--blocked 0)

(defun cyrograf-test-check (label condition)
  (if condition
      (princ (format "PASS: %s\n" label))
    (setq cyrograf-test--failures (1+ cyrograf-test--failures))
    (princ (format "FAIL: %s\n" label))))

(defun cyrograf-test-blocked (label reason)
  (setq cyrograf-test--blocked (1+ cyrograf-test--blocked))
  (princ (format "BLOCKED: %s (%s)\n" label reason)))

(defun cyrograf-test-face-p (position face)
  "Return non-nil when FACE applies at POSITION.
POSITION may carry a single face symbol or a list of faces."
  (let ((value (get-text-property position 'face)))
    (cond
     ((null value) nil)
     ((listp value) (memq face value))
     (t (eq face value)))))

(let* ((here (file-name-directory (or load-file-name buffer-file-name)))
       (editors (expand-file-name ".." here))
       (root (expand-file-name "../.." here)))
  (add-to-list 'load-path (directory-file-name (expand-file-name "emacs" editors)))
  (require 'cyrograf-mode)

  ;; The example shipped with the editors.
  (let ((fixture (expand-file-name "example/Orders.cyrograf" editors)))
    (with-temp-buffer
      (insert-file-contents fixture)
      (cyrograf-mode)
      (font-lock-mode 1)
      (font-lock-ensure)
      (cyrograf-test-check "mode selected for .cyrograf"
                           (eq major-mode 'cyrograf-mode))

      (goto-char (point-min))
      (search-forward "struct")
      (cyrograf-test-check "struct keyword face"
                           (eq (get-text-property (match-beginning 0) 'face)
                               'font-lock-keyword-face))
      (search-forward "ReserveRequest")
      (cyrograf-test-check "message name face"
                           (eq (get-text-property (match-beginning 0) 'face)
                               'font-lock-type-face))
      (search-forward "owner_id")
      (cyrograf-test-check "field name face"
                           (eq (get-text-property (match-beginning 0) 'face)
                               'font-lock-variable-name-face))
      (search-forward "string")
      (cyrograf-test-check "primitive face"
                           (eq (get-text-property (match-beginning 0) 'face)
                               'font-lock-type-face))
      (goto-char (point-min))
      (search-forward "//")
      (cyrograf-test-check "// starts a comment"
                           (nth 4 (syntax-ppss (match-end 0))))
      (search-forward "Example")
      (cyrograf-test-check "comment face"
                           (eq (get-text-property (match-beginning 0) 'face)
                               'font-lock-comment-face))
      (goto-char (point-min))
      (search-forward "rpc")
      (cyrograf-test-check "rpc keyword face"
                           (eq (get-text-property (match-beginning 0) 'face)
                               'font-lock-keyword-face))
      (search-forward "reserve")
      (cyrograf-test-check "method name face"
                           (eq (get-text-property (match-beginning 0) 'face)
                               'font-lock-function-name-face))))

  ;; Indentation of a snippet without leading whitespace.
  (with-temp-buffer
    (insert "struct A {\nfield: String\n// keep\n}\n")
    (cyrograf-mode)
    (indent-region (point-min) (point-max))
    (cyrograf-test-check "brace indentation"
                         (equal (buffer-string)
                                "struct A {\n  field: String\n  // keep\n}\n")))

  ;; Eglot registration is available when Eglot is bundled or provided on a path.
  (let* ((eglot-path (getenv "CYROGRAF_EMACS_EGLOT_PATH"))
         (external (and eglot-path (file-directory-p eglot-path))))
    (when external
      (add-to-list 'load-path eglot-path)
      (let ((xc (car (file-expand-wildcards
                      (expand-file-name "xc/external-completion-*"
                                        (file-name-directory eglot-path))))))
        (when xc (add-to-list 'load-path xc))))
    (cond
     ((require 'eglot nil t)
      (cyrograf-test-check "eglot server program registered"
                           (eq (cdr (assq 'cyrograf-mode eglot-server-programs))
                               'cyrograf-eglot-contact))
      (cyrograf-test-check "eglot contact is a list"
                           (equal (cyrograf-eglot-contact) '("cyrograf" "lsp")))
      (let ((cyrograf-lsp-program "/opt/cyrograf bin/cyrograf"))
        (cyrograf-test-check "program path with spaces is one list item"
                             (equal (cyrograf-eglot-contact)
                                    '("/opt/cyrograf bin/cyrograf" "lsp"))))
      (cyrograf-test-check "loading does not start a server"
                           (not (seq-find
                                 (lambda (process)
                                   (string-match-p "cyrograf"
                                                   (or (process-name process) "")))
                                 (process-list)))))
     (t
      (cyrograf-test-blocked "eglot registration"
                             "eglot is not bundled with this Emacs and not found in CYROGRAF_EMACS_EGLOT_PATH"))))

  ;; Markdown fenced `cyrograf' blocks use the same font-lock rules as the
  ;; standalone files. markdown-mode is an optional dependency of this check.
  (let* ((md-path (getenv "CYROGRAF_EMACS_MARKDOWN_PATH"))
         (md-file (and md-path (expand-file-name "markdown-mode.el" md-path))))
    (cond
     ((not (and md-file (file-exists-p md-file)))
      (cyrograf-test-blocked
       "markdown block fontification"
       "markdown-mode is not available in CYROGRAF_EMACS_MARKDOWN_PATH"))
     (t
      (add-to-list 'load-path md-path)
      (require 'markdown-mode)
      (cyrograf-test-check "markdown language mapping registered"
                           (eq (cdr (assoc "cyrograf" markdown-code-lang-modes))
                               'cyrograf-mode))
      (dolist (mode '(markdown-mode gfm-mode))
        (with-temp-buffer
          (insert "# Title\n\n"
                  "```cyrograf\n"
                  "// <b>&</b> comment\n"
                  "struct A {\n  x: String\n}\n"
                  "```\n\n"
                  "prose after the block\n")
          (funcall mode)
          (setq-local markdown-fontify-code-blocks-natively t)
          (font-lock-mode 1)
          (font-lock-ensure)
          (goto-char (point-min))
          (search-forward "struct")
          (cyrograf-test-check (format "%s block struct face" mode)
                               (cyrograf-test-face-p (match-beginning 0)
                                                     'font-lock-keyword-face))
          (search-forward "string")
          (cyrograf-test-check (format "%s block primitive face" mode)
                               (cyrograf-test-face-p (match-beginning 0)
                                                     'font-lock-type-face))
          (goto-char (point-min))
          (search-forward "comment")
          (cyrograf-test-check (format "%s block comment face" mode)
                               (cyrograf-test-face-p (match-beginning 0)
                                                     'font-lock-comment-face))
          (search-forward "prose after")
          (cyrograf-test-check (format "%s prose after the block is not cyrograf" mode)
                               (not (cyrograf-test-face-p (match-beginning 0)
                                                          'font-lock-keyword-face)))))))))

  (princ (format "emacs checks: %d failure(s), %d blocked\n"
                 cyrograf-test--failures cyrograf-test--blocked))
  (kill-emacs (if (and (zerop cyrograf-test--failures)
                       (zerop cyrograf-test--blocked))
                  0
                1)))

;;; test-batch.el ends here