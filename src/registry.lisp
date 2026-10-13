(defpackage #:sprolog/src/registry (:use #:cl #:sprolog/src/api))
(in-package #:sprolog)

(defvar *iso-builtins* (make-hash-table :test 'equal))
(defvar *iso-aliases* (make-hash-table :test 'equal))
(defvar *iso-context* nil)
(defvar *iso-halt-function* (lambda (status) (uiop:quit status)))
(defun iso-register (name arities)
  (dolist (arity arities) (setf (gethash (cons (string-upcase name) arity) *iso-builtins*) t)))
(defun iso-primitive-p (name arity)
  (and (symbolp name)
       (let ((key (cons (string-upcase (symbol-name name)) arity)))
         (or (gethash key *iso-builtins*) (gethash (cons (or (gethash key *iso-aliases*) (car key)) arity) *iso-builtins*)))))
(defvar *standard-predicates* (make-hash-table :test 'equal))
(defun standard-predicate (name arity)
  (and (symbolp name)
       (gethash (cons (iso-predicate-name name arity) arity) *standard-predicates*)))
(defun iso-builtin-p (name arity)
  "Protected public names: primitives, syntax, and derived library predicates."
  (or (iso-primitive-p name arity) (standard-predicate name arity)))
(defun builtin-predicate-inventory ()
  "Return all public predicate indicators, including the derived library."
  (sort (remove-duplicates
         (append (loop for key being the hash-keys of *iso-builtins*
                       unless (char= #\% (char (car key) 0)) collect (copy-tree key))
                 (loop for key being the hash-keys of *standard-predicates*
                       unless (char= #\% (char (car key) 0)) collect (copy-tree key)))
         :test #'equal)
        (lambda (a b) (or (string< (car a) (car b))
                         (and (string= (car a) (car b)) (< (cdr a) (cdr b)))))))
