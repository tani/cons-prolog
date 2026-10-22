(uiop:define-package #:sprolog/tests/native
  (:use #:cl #:sprolog)
  (:import-from #:sprolog/tests/tests #:check)
  (:import-from #:sprolog/src/syntax/native #:*native-enabled*)
  (:export #:run-native-tests))
(in-package #:sprolog/tests/native)
(defun snapshot (text enabled)
  (let ((*native-enabled* (and enabled #+sbcl t #-sbcl nil)) (*print-circle* t) (*print-pretty* nil)
        (*print-gensym* nil))
    (handler-case
        (write-to-string (query (parse-prolog-string text) :gc-threshold 1 :limit 100))
      (iso-exception (c) (write-to-string (iso-exception-term c))))))
(defun run-native-tests ()
  (let ((*database* (make-database)))
    (load-prolog-string
     "q(1). q(2). q(3).
      pick(X) :- q(X), X > 1.
      picks(L) :- findall(X,pick(X),L).
      stop(X) :- q(X), X > 1, !.
      stops(L) :- findall(X,stop(X),L).
      failed_cut(X) :- q(X), !, X > 1.
      failed_cuts(L) :- findall(X,failed_cut(X),L).
      p(a,b) :- !. p(c,c).
      shaped(g(1)) :- !. shaped(f(2)).
      shape(X) :- shaped(f(X)).
      shared(f(a,b)) :- !. shared(f(c,c)).
      sharing(X) :- shared(f(X,X)).
      factorial(0,1) :- !.
      factorial(N,R) :- N > 0, M is N-1, factorial(M,S), R is N*S.
      copylist([],[]). copylist([X|Xs],[X|Ys]) :- copylist(Xs,Ys).
      countdown(0) :- !. countdown(N) :- M is N-1, countdown(M).
      arithmetic(X,R) :- R is X+1.
      zero(R) :- R is 1 mod 0.
      identity(X,X).
      nested(0,a) :- !. nested(N,L) :- M is N-1, findall(X,nested(M,X),L).
      version(1). dependent(X) :- version(X).")
    (dolist (text '("picks(L)." "stops(L)." "failed_cuts(L)." "p(X,X)."
                    "shape(X)." "sharing(X)." "shaped(f(X))."
                    "nested(3,L)." "factorial(0,R)." "factorial(30,R)." "factorial(-1,R)."
                    "factorial(4,24)." "factorial(4,25)."
                    "arithmetic(2,R)." "arithmetic(2.5,R)." "arithmetic(bad,R)."
                    "arithmetic(X,R)." "zero(R)."
                    "identity(X,X)." "identity(f(X,X),Y)."
                    "identity([1,2|X],Y)." "identity([1,2],Y)."))
      (check (string= (snapshot text nil) (snapshot text t)) text))
    ;; Exhaust the small combinations that move failure across cuts and answers.
    (dolist (left '("!" "X>1" "Y>1" "X=Y" "fail" "true" "q(X)"))
      (dolist (right '("!" "X>1" "Y>1" "X=Y" "fail" "true" "q(X)"))
        (load-prolog-string
         (format nil "sample(X,Y) :- q(X),q(Y),~A,~A. sample(9,9). samples(L) :- findall(pair(X,Y),sample(X,Y),L)." left right))
        (check (string= (snapshot "samples(L)." nil) (snapshot "samples(L)." t))
               (format nil "cut/guard enumeration: ~A,~A" left right))))
    ;; A pure call that exceeds the native depth budget resumes on the VM.
    #+sbcl
    (unless (uiop:getenv "SPROLOG_DISABLE_NATIVE")
    (let* ((vm (make-query (parse-prolog-string "countdown(10000)."))))
      (unwind-protect
           (progn (check (nth-value 1 (next-solution vm)) "deep native bailout succeeds")
                  (check (plusp (getf (query-statistics vm) :native-deoptimizations)) "native bailout observed"))
        (close-query vm)))
    (let ((vm (make-query (parse-prolog-string "factorial(10,R)."))))
      (unwind-protect
           (progn (check (nth-value 1 (next-solution vm)) "compiled arithmetic succeeds")
                  (check (plusp (getf (query-statistics vm) :native-calls)) "native compiler exercised"))
        (close-query vm)))
    (let ((vm (make-query (list (list 'copylist (make-list 10000 :initial-element 1) '?copy)))))
      (unwind-protect
           (multiple-value-bind (answer found) (next-solution vm)
             (check found "non-tail native stack bailout succeeds")
             (check (= 10000 (length (cdr (assoc '?copy answer)))) "non-tail bailout preserves output")
             (check (plusp (getf (query-statistics vm) :native-deoptimizations)) "non-tail bailout observed"))
        (close-query vm))))
    (check (string= (snapshot "dependent(X)." nil) (snapshot "dependent(X)." t)) "initial dependency")
    (load-prolog-string "version(2).")
    (check (string= (snapshot "dependent(X)." nil) (snapshot "dependent(X)." t)) "dependency cache invalidation")
    (let ((goals (list (list '= '?x (list 'a '?x)) (list 'identity '?x '?y))))
      (let ((*native-enabled* #+sbcl t #-sbcl nil))
        (let* ((answer (first (query goals :gc-threshold 1))) (term (cdr (assoc '?y answer))))
          (check (eq term (second term)) "rational input survives native fallback"))))
    ;; Mixed heads must retain source order, including the variable fallback.
    (<-- (indexed a 1)) (<- (indexed ?x 2)) (<- (indexed b 3)) (<- (indexed a 4))
    (let ((*native-enabled* nil))
      (check (equal (mapcar (lambda (answer) (cdr (assoc '?n answer)))
                           (query '((indexed a ?n)) :gc-threshold 1)) '(1 2 4)) "indexed clause order")
      (check (= 4 (length (query '((indexed ?x ?n))))) "unbound index fallback"))
    (let ((seen nil))
      (sprolog/src/kernel/engine:map-term '(a (b c) d)
        (lambda (x) (when (symbolp x) (push x seen)) x))
      (check (equal (reverse seen) '(a b c nil d nil)) "graph visitor preorder"))))
