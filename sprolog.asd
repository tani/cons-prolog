(asdf:defsystem "sprolog"
  :class :package-inferred-system
  :description "Stack-safe S-expression Prolog with a WAM-derived register VM"
  :version "0.9.1"
  :license "MIT"
  :depends-on ("uiop" "sprolog/src/library/standard-library")
  :in-order-to ((asdf:test-op (asdf:test-op "sprolog/tests"))))

;; The inferred module packages declare dependencies while implementation
;; definitions share SPROLOG. Map its public nickname to the defining module.
(asdf:register-system-packages "sprolog/src/api/package" '("SPROLOG"))
(asdf:register-system-packages "sprolog/src/adapters/term-ops" '("SPROLOG/ATOMS"))
(asdf:register-system-packages "sprolog/tests/tests" '("SPROLOG/TESTS"))

(asdf:defsystem "sprolog/tests"
  :depends-on ("sprolog/tests/standard-library")
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (uiop:symbol-call :sprolog/tests :run-tests)))
