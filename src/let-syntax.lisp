(defpackage #:sprolog/src/let-syntax (:use #:cl #:sprolog/src/slg))
(in-package #:sprolog)

(defstruct lexical-binding getter setter)
(defun lexical-binding-value (binding) (funcall (lexical-binding-getter binding)))
(defun (setf lexical-binding-value) (value binding)
  (funcall (lexical-binding-setter binding) value))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun globally-special-p (symbol)
    #+sbcl (eq (sb-int:info :variable :kind symbol) :special)
    #-sbcl
    ;; ANSI CL exposes no declaration introspection. A compiled LET binds a
    ;; globally special symbol dynamically; SYMBOL-VALUE observes that binding.
    (let ((marker (gensym "SPECIAL-PROBE-")))
      (funcall (compile nil
                        `(lambda ()
                           (let ((,symbol ',marker))
                             (declare (ignorable ,symbol))
                             (and (boundp ',symbol)
                                  (eq (symbol-value ',symbol) ',marker))))))))
  (defun let-goal-form (goal bindings)
    (unless (and (finite-list-p goal) (member (length goal) '(3 4))
                 (symbolp (second goal)) (second goal)
                 (not (or (keywordp (second goal)) (constantp (second goal))
                          (variable-symbol-p (second goal))
                          (globally-special-p (second goal)))))
      (error "LET requires a nonspecial Lisp variable and an initializer"))
    (let* ((name (second goal)) (declaration (fourth goal))
           (slot (gensym "?LET-")) (value (gensym "VALUE-")))
      (when declaration
        (unless (and (finite-list-p declaration) (eq (car declaration) 'declare)
                     (every (lambda (spec)
                              (and (finite-list-p spec) (not (eq (car spec) 'special))))
                            (cdr declaration)))
          (error "LET accepts a DECLARE form without SPECIAL declarations")))
      (setf (get slot 'dcg-internal) t)
      (values
       `(progn
          (setf (get ',slot 'dcg-internal) t)
          ,(host-goal-form
            `(lisp ,slot
               (let ((,name ,(third goal)))
                 ,@(when declaration (list declaration))
                 (make-lexical-binding :getter (lambda () ,name)
                   :setter (lambda (,value) (setf ,name ,value))))) bindings))
       (acons name slot (remove name bindings :key #'car :test #'eq)))))
)
