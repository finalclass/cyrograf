;;; test-eglot.el --- Real Eglot smoke test for cyrograf-mode  -*- lexical-binding: t; -*-

;; Runs a real `cyrograf lsp' session through Eglot in batch mode. It opens
;; `Orders.cyrograf' from a temporary project, introduces an unsaved unknown
;; type, waits for the `UnresolvedReference' diagnostic, repairs it, follows
;; the definition into `Common.cyrograf' and formats a messy buffer, comparing
;; the result with the CLI formatter.

;;; Code:

(require 'seq)
(require 'xref)

(defvar cyrograf-eglot--failures 0)
(defvar cyrograf-eglot--blocked 0)

(defun cyrograf-eglot-check (label condition)
  (if condition
      (princ (format "PASS: %s\n" label))
    (setq cyrograf-eglot--failures (1+ cyrograf-eglot--failures))
    (princ (format "FAIL: %s\n" label))))

(defun cyrograf-eglot-blocked (label reason)
  (setq cyrograf-eglot--blocked (1+ cyrograf-eglot--blocked))
  (princ (format "BLOCKED: %s (%s)\n" label reason)))

(defun cyrograf-eglot-wait (predicate timeout)
  "Wait until PREDICATE is non-nil or TIMEOUT seconds pass."
  (let ((deadline (+ (float-time) timeout)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.1)
      (sit-for 0.05))
    (funcall predicate)))

(defun cyrograf-eglot-sync ()
  "Send the current unsaved buffer state to the server without saving."
  (when (and (boundp 'eglot--managed-mode) eglot--managed-mode
             (fboundp 'eglot--signal-textDocument/didChange))
    (eglot--signal-textDocument/didChange)))

(defun cyrograf-eglot-diagnostics (buffer)
  "Return the diagnostics known for BUFFER as plists with :code and :message."
  (with-current-buffer buffer
    (let ((result '()))
      (dolist (diagnostic (append (and (boundp 'flymake-mode) flymake-mode
                                       (flymake-diagnostics))
                                  eglot--diagnostics))
        (let* ((data (ignore-errors (eglot--diag-data diagnostic)))
               (spec (cdr (assq 'eglot-lsp-diag data)))
               (code (plist-get spec :code))
               (message (flymake-diagnostic-text diagnostic)))
          (push (list :code (and code (format "%s" code)) :message message)
                result)))
      (nreverse result))))

(defun cyrograf-eglot-codes (buffer)
  (delq nil (mapcar (lambda (d) (plist-get d :code))
                    (cyrograf-eglot-diagnostics buffer))))

(let* ((here (file-name-directory (or load-file-name buffer-file-name)))
       (editors (expand-file-name ".." here))
       (bin (getenv "CYROGRAF_BIN"))
       (project (getenv "CYROGRAF_EMACS_PROJECT")))
  (add-to-list 'load-path (directory-file-name (expand-file-name "emacs" editors)))

  (let ((elpa (getenv "CYROGRAF_EMACS_ELPA")))
    (when (and elpa (file-directory-p elpa) (< emacs-major-version 29))
      (dolist (pattern '("xc/external-completion-*" "project-*" "eglot-*"))
        (dolist (dir (file-expand-wildcards (expand-file-name pattern elpa)))
          (when (file-directory-p dir)
            (add-to-list 'load-path dir))))))
  (let* ((eglot-path (getenv "CYROGRAF_EMACS_EGLOT_PATH"))
         (external (and eglot-path (file-directory-p eglot-path))))
    (when external
      (add-to-list 'load-path eglot-path)
      (let ((xc (car (file-expand-wildcards
                      (expand-file-name "xc/external-completion-*"
                                        (file-name-directory eglot-path))))))
        (when xc (add-to-list 'load-path xc)))))

  (cond
   ((not (and bin (file-exists-p bin)))
    (cyrograf-eglot-blocked "eglot smoke" "CYROGRAF_BIN is not set to an existing file"))
   ((not (and project (file-directory-p project)))
    (cyrograf-eglot-blocked "eglot smoke" "CYROGRAF_EMACS_PROJECT is not a directory"))
   ((not (require 'eglot nil t))
    (cyrograf-eglot-blocked "eglot smoke" "eglot is not available"))
   (t
    (require 'cyrograf-mode)
    (setq cyrograf-lsp-program bin)
    (setq flymake-no-changes-timeout nil)
    (let ((orders (expand-file-name "Orders.cyrograf" project))
          (default-directory (file-name-as-directory project)))
      (with-current-buffer (find-file-noselect orders)
        (cyrograf-mode)
        (apply #'eglot--connect (eglot--guess-contact))
        (cyrograf-eglot-check "eglot connects"
                              (cyrograf-eglot-wait (lambda () (eglot-current-server)) 30))
        (cyrograf-eglot-wait (lambda () (null (cyrograf-eglot-diagnostics (current-buffer)))) 30)
        (cyrograf-eglot-check "clean document has no diagnostics"
                              (null (cyrograf-eglot-diagnostics (current-buffer))))
        (goto-char (point-min))
        (when (search-forward "item: Common.Thing" nil t)
          (replace-match "item: Common.Missing"))
        (cyrograf-eglot-sync)
        (cyrograf-eglot-check
         "unsaved error diagnosed"
         (cyrograf-eglot-wait
          (lambda () (member "UnresolvedReference" (cyrograf-eglot-codes (current-buffer))))
          30))
        (goto-char (point-min))
        (when (search-forward "item: Common.Missing" nil t)
          (replace-match "item: Common.Thing"))
        (cyrograf-eglot-sync)
        (cyrograf-eglot-check
         "diagnostics cleared after repair"
         (cyrograf-eglot-wait
          (lambda () (null (cyrograf-eglot-diagnostics (current-buffer)))) 30))
        (goto-char (point-min))
        (when (search-forward "Common.Thing" nil t)
          (goto-char (match-beginning 0))
          (condition-case err
              (xref-find-definitions "Common.Thing")
            (error (princ (format "xref error: %s\n" err)))))
        (cyrograf-eglot-check
         "definition opens the other module"
         (cyrograf-eglot-wait
          (lambda () (string-match-p "Common\\.cyrograf\\'" (buffer-file-name (current-buffer))))
          30))
        (eglot-shutdown (eglot-current-server) nil 10)))

    ;; Formatting through Eglot must equal the CLI formatter.
    (let* ((messy-dir (make-temp-file "cyrograf-eglot-" t))
           (messy (expand-file-name "A.cyrograf" messy-dir))
           (content "struct   A{x:String;y?:Int}\n")
           (cli (with-temp-buffer
                  (insert content)
                  (let ((status (call-process-region
                                 (point-min) (point-max) bin t t nil
                                 "format" "--stdin" "--filename" "A.cyrograf")))
                    (unless (zerop status)
                      (cyrograf-eglot-blocked "eglot format" (format "CLI exit %s" status)))
                    (buffer-string)))))
      (write-region content nil messy nil 'silent)
      (with-current-buffer (find-file-noselect messy)
        (cyrograf-mode)
        (let ((default-directory (file-name-as-directory messy-dir)))
          (apply #'eglot--connect (eglot--guess-contact))
          (cyrograf-eglot-check "eglot connects in the format project"
                                (cyrograf-eglot-wait (lambda () (eglot-current-server)) 30))
          (eglot-format-buffer)
          (cyrograf-eglot-check
           "eglot formatting matches the CLI"
           (equal (buffer-string) cli))
          (eglot-shutdown (eglot-current-server) nil 10)))
      (delete-directory messy-dir t))))

  (princ (format "emacs eglot checks: %d failure(s), %d blocked\n"
                 cyrograf-eglot--failures cyrograf-eglot--blocked))
  (kill-emacs (if (or (> cyrograf-eglot--failures 0)
                      (> cyrograf-eglot--blocked 0))
                  1 0)))

;;; test-eglot.el ends here