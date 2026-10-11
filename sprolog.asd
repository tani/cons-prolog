(asdf:defsystem "sprolog"
  :description "Stack-safe S-expression Prolog with a WAM-derived register VM"
  :version "0.9.0" :license "MIT" :serial t
  :components ((:file "src/package") (:file "src/engine") (:file "src/gc") (:file "src/wam") (:file "src/dcg") (:file "src/compiler") (:file "src/wam-compiler") (:file "src/slg") (:file "src/api") (:file "src/builtins"))
  :in-order-to ((asdf:test-op (asdf:test-op "sprolog/tests"))))
(asdf:defsystem "sprolog/tests"
  :depends-on ("sprolog") :components ((:file "tests/tests") (:file "tests/wam-gc") (:file "tests/dcg") (:file "tests/slg") (:file "tests/slg-cut") (:file "tests/builtins") (:file "tests/term-syntax") (:file "tests/interactive"))
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (uiop:symbol-call :sprolog/tests :run-tests)))
