(asdf:defsystem "sprolog"
  :class :package-inferred-system
  :description "Stack-safe S-expression Prolog with a WAM-derived register VM"
  :version "0.10.0"
  :license "MIT"
  :depends-on ("uiop" "sprolog/src/api/package")
  :in-order-to ((asdf:test-op (asdf:test-op "sprolog/tests"))))

;; Module packages own their definitions. Map only the final public facade,
;; test runner, and generated atom namespace to their defining systems.
(asdf:register-system-packages "sprolog/src/api/package" '("CONS" "PROLOG"))
(asdf:register-system-packages "sprolog/src/adapters/term-ops" '("SPROLOG/ATOMS"))
(asdf:register-system-packages "sprolog/tests/suite" '("SPROLOG/TESTS"))

(asdf:defsystem "sprolog/tests"
  :depends-on ("sprolog/tests/suite")
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (uiop:symbol-call :sprolog/tests :run-tests)))
