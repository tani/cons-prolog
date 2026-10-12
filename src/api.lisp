;; ASDF infers load order from this dependency package. Implementation symbols
;; stay in SPROLOG so the public API and internal symbol identities are stable.
(defpackage #:sprolog/src/api (:use #:cl #:sprolog/src/slg))
(in-package #:sprolog)

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
  (defun host-goal-form (goal &optional bindings)
    (let* ((testp (string= (symbol-name (car goal)) "LISPP"))
           (output (and (not testp) (= (length goal) 3) (second goal)))
           (expression (if output (third goal) (second goal)))
           (expression (if bindings
                           `(symbol-macrolet
                                ,(mapcar (lambda (entry)
                                           `(,(car entry) (lexical-binding-value ,(cdr entry)))) bindings)
                              ,expression)
                           expression))
           (variables (variables-in expression)))
      (unless (if testp (= (length goal) 2) (member (length goal) '(2 3)))
        (error "Invalid Lisp bridge goal: ~S" goal))
      `(make-host-goal :function (lambda ,variables
                                  ,@(when variables `((declare (ignorable ,@variables))))
                                  ,expression)
                       :arguments ',variables :output ',output :testp ,testp)))
  (defun source-control-p (goal names)
    (and (consp goal) (symbolp (car goal))
         (member (symbol-name (car goal)) names :test #'string=)))
  (defun source-sequence (goals)
    (let ((work (copy-list goals)) (result nil))
      (loop while work do
        (let* ((goal (pop work)))
          (if (and (source-control-p goal '("AND" ","))
                   (finite-list-p goal) (= (length goal) 3))
              (progn (push (third goal) work) (push (second goal) work))
              (push goal result))))
      (nreverse result)))
  (defun goal-form (goal &optional bindings)
    (cond
      ((scoped-goals-p goal)
       `(make-scoped-goals :goals ,(goals-form (scoped-goals-goals goal) bindings)))
      ((disjunction-goal-p goal)
       `(make-disjunction-goal :branches
          (list ,@(mapcar (lambda (branch) (goals-form branch bindings))
                         (disjunction-goal-branches goal)))))
      ((and (consp goal) (symbolp (car goal))
            (member (symbol-name (car goal)) '("LISP" "LISPP") :test #'string=))
       (host-goal-form goal bindings))
      ((or (source-control-p goal '("LET"))
           (and (source-control-p goal '("AND" ","))
                (finite-list-p goal) (= (length goal) 3)))
       `(make-sequence-goals :goals ,(goals-form (list goal) bindings)))
      ((source-control-p goal '("OR" ";" "->" "ONCE" "/+" "\\+"))
       `(list ',(car goal) ,@(mapcar (lambda (child) (goal-form child bindings)) (cdr goal))))
      (t `',goal)))
  (defun goals-form (goals &optional bindings)
    (let ((result nil))
      (dolist (goal (source-sequence (expand-query-goals goals)))
        (if (source-control-p goal '("LET"))
            (progn
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
                                        (and (finite-list-p spec)
                                             (not (eq (car spec) 'special)))) (cdr declaration)))
                    (error "LET accepts a DECLARE form without SPECIAL declarations")))
                ;; Reuse the existing hidden-variable marker used by DCG expansion.
                (setf (get slot 'dcg-internal) t)
                (push `(progn
                         ;; Symbol properties do not survive a FASL round trip.
                         (setf (get ',slot 'dcg-internal) t)
                         ,(host-goal-form
                           `(lisp ,slot
                              (let ((,name ,(third goal)))
                                ,@(when declaration (list declaration))
                                (make-lexical-binding :getter (lambda () ,name)
                                  :setter (lambda (,value) (setf ,name ,value))))) bindings)) result)
                (setf bindings (acons name slot (remove name bindings :key #'car :test #'eq)))))
            (push (goal-form goal bindings) result)))
      `(list ,@(nreverse result)))))

(defmacro --> (head &body body)
  (multiple-value-bind (expanded-head expanded-body) (dcg-expand head body)
    `(add-clause ',expanded-head ,(goals-form expanded-body) nil)))
(defmacro ---> (head &body body)
  (multiple-value-bind (expanded-head expanded-body) (dcg-expand head body)
    `(add-clause ',expanded-head ,(goals-form expanded-body) t)))

(defmacro <- (head &body body)
  `(add-clause ',head ,(goals-form body) nil))
(defmacro <-- (head &body body)
  `(add-clause ',head ,(goals-form body) t))
(defun display-query-answer (solution truth delays stream)
  (let ((*print-circle* t) (*print-pretty* t) (*print-readably* nil))
    (fresh-line stream)
    (dolist (binding solution)
      (format stream "~S = ~S~%" (car binding) (cdr binding)))
    (if (eq truth :undefined)
        (format stream "undefined; delayed negation: ~S~%" delays)
        (unless solution (format stream "true.~%")))))

(defun query-more-p (stream)
  (loop
    (format stream "More? [; = next, Enter = stop] ")
    (finish-output stream)
    (let ((line (read-line stream nil nil)))
      (unless line (return nil))
      (let ((command (string-trim '(#\Space #\Tab #\Return) line)))
        (cond ((string= command ";") (return t))
              ((member command '("" "." "q") :test #'string-equal) (return nil))
              (t (format stream "Type ; for the next answer, or Enter to stop.~%")))))))

(defun interactive-query (goals)
  "Display one answer at a time through *QUERY-IO*, without lookahead."
  (let ((vm (make-query goals)))
    (unwind-protect
         (loop
           (multiple-value-bind (solution foundp truth delays) (next-solution vm)
             (unless foundp
               (fresh-line *query-io*)
               (format *query-io* "false.~%")
               (finish-output *query-io*)
               (return))
             (display-query-answer solution truth delays *query-io*)
             (unless (query-more-p *query-io*) (return))))
      (close-query vm)))
  (values))

(defmacro ?- (&body goals)
  "Interactively display answers; ; requests another, Enter or EOF stops."
  `(interactive-query ,(goals-form goals)))
(defmacro prolog (&body goals)
  "Enumerate goals with lexical Lisp callbacks; RETURN-FROM PROLOG exits safely."
  (let ((vm (gensym "VM")) (solution (gensym "SOLUTION")) (found (gensym "FOUND")))
    `(block prolog
       (let ((,vm (make-query ,(goals-form goals))))
         (unwind-protect
              (loop (multiple-value-bind (,solution ,found) (next-solution ,vm)
                      (declare (ignore ,solution)) (unless ,found (return nil))))
           (close-query ,vm))))))
