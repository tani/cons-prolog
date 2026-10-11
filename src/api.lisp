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

(defmacro -> (head &body body)
  (multiple-value-bind (expanded-head expanded-body) (dcg-expand head body)
    `(add-clause ',expanded-head ,(goals-form expanded-body) nil)))
(defmacro --> (head &body body)
  (multiple-value-bind (expanded-head expanded-body) (dcg-expand head body)
    `(add-clause ',expanded-head ,(goals-form expanded-body) t)))

(defmacro <- (head &body body)
  `(add-clause ',head ,(goals-form body) nil))
(defmacro <-- (head &body body)
  `(add-clause ',head ,(goals-form body) t))
(defmacro ?- (&body goals)
  "Noninteractive query: return all substitutions as alists."
  `(query ,(goals-form goals)))
(defmacro prolog (&body goals)
  "Enumerate goals with lexical Lisp callbacks; RETURN-FROM PROLOG exits safely."
  (let ((vm (gensym "VM")) (solution (gensym "SOLUTION")) (found (gensym "FOUND")))
    `(block prolog
       (let ((,vm (make-query ,(goals-form goals))))
         (unwind-protect
              (loop (multiple-value-bind (,solution ,found) (next-solution ,vm)
                      (declare (ignore ,solution)) (unless ,found (return nil))))
           (close-query ,vm))))))
