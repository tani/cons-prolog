(asdf:defsystem "cons-prolog"
  :class :package-inferred-system
  :description "Stack-safe S-expression Prolog with a WAM-derived register VM"
  :version "0.10.0"
  :license "MIT"
  :depends-on ("uiop" "cons-prolog/src/api/package")
  :in-order-to ((asdf:test-op (asdf:test-op "cons-prolog/tests"))))

;; Module packages own their definitions. Map only the final public facade,
;; test runner, and generated atom namespace to their defining systems.
(asdf:register-system-packages "cons-prolog/src/api/package" '("CONS" "PROLOG"))
(asdf:register-system-packages "cons-prolog/src/adapters/term-ops" '("CONS-PROLOG/ATOMS"))
(asdf:register-system-packages "cons-prolog/tests/suite" '("CONS-PROLOG/TESTS"))

(asdf:defsystem "cons-prolog/tests"
  :depends-on ("cons-prolog/tests/suite")
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (uiop:symbol-call :cons-prolog/tests :run-tests)))
