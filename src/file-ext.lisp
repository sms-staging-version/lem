(in-package :lem)

(defvar *file-type-relationals* '())
(defvar *program-name-relationals* '())

(defun get-file-mode (pathname)
  (alexandria:assoc-value *file-type-relationals*
                          (pathname-type pathname)
                          :test #'string=))

(defun associcate-file-type (type-list mode)
  (dolist (type type-list)
    (pushnew (cons type mode)
             *file-type-relationals*
             :test #'equal)))

(defmacro define-file-type ((&rest type-list) mode)
  `(associcate-file-type ',type-list ',mode))

(defun get-program-mode (program-name)
  (alexandria:assoc-value *program-name-relationals*
                          program-name
                          :test #'string=))

(defun associcate-program-name-with-mode (program-names mode)
  (dolist (name program-names)
    (pushnew (cons name mode)
             *program-name-relationals*
             :test #'equal)))

(defmacro define-program-name-with-mode ((&rest program-names) mode)
  `(associcate-program-name-with-mode ',program-names ',mode))

;;;
(defun parse-shebang (line)
  (let* ((args (split-sequence:split-sequence #\space line :remove-empty-subseqs t))
         (program (alexandria:lastcar
                   (split-sequence:split-sequence #\/ (alexandria:lastcar args)))))
    (cond ((string= program "env")
           (second args))
          (t
           program))))

(defun program-name-to-mode (program)
  (get-program-mode program))

(defun parse-file-mode (buffer)
  (with-point ((point (buffer-point buffer)))
    (buffer-start point)
    (let ((header-line (line-string point)))
      (when (alexandria:starts-with-subseq "#!" header-line)
        (program-name-to-mode (parse-shebang header-line))))))

(defun detect-file-mode (buffer)
  (or (get-file-mode (buffer-filename buffer))
      (parse-file-mode buffer)))

(defun process-file (buffer)
  (alexandria:when-let (mode (detect-file-mode buffer))
    (change-buffer-mode buffer mode)
    (values)))

;;;
(defun detect-external-format-from-file (pathname)
  (values (inq:dependent-name (inq:detect-encoding (pathname pathname) :jp))
          (or (inq:detect-end-of-line (pathname pathname)) :lf)))

(setf *external-format-function* 'detect-external-format-from-file)
