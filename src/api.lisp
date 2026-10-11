(in-package #:sprolog)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun host-goal-form (goal)
    (let* ((testp (string= (symbol-name (car goal)) "LISPP"))
           (output (and (not testp) (= (length goal) 3) (second goal)))
           (expression (if output (third goal) (second goal)))
           (variables (variables-in expression)))
      (unless (if testp (= (length goal) 2) (member (length goal) '(2 3)))
        (error "Invalid Lisp bridge goal: ~S" goal))
      `(make-host-goal :function (lambda ,variables
                                  ,@(when variables `((declare (ignorable ,@variables))))
                                  ,expression)
                       :arguments ',variables :output ',output :testp ,testp)))
  (defun goal-form (goal)
    (cond
      ((scoped-goals-p goal)
       `(make-scoped-goals :goals ,(goals-form (scoped-goals-goals goal))))
      ((disjunction-goal-p goal)
       `(make-disjunction-goal :branches
          (list ,@(mapcar #'goals-form (disjunction-goal-branches goal)))))
      ((and (consp goal) (symbolp (car goal))
            (member (symbol-name (car goal)) '("LISP" "LISPP") :test #'string=))
       (host-goal-form goal))
      (t `',goal)))
  (defun goals-form (goals)
    `(list ,@(mapcar #'goal-form (expand-query-goals goals)))))

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
