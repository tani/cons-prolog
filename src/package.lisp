(defpackage #:sprolog
  (:use #:cl)
  (:export #:<- #:<-- #:?- #:prolog #:-> #:--> #:phrase #:dcg-expand #:query #:make-query #:next-solution
           #:slg-incomplete-cut #:table #:untable #:tnot #:close-query #:clear-database #:*database* #:make-database
           #:collect-query-garbage #:query-statistics #:disassemble-predicate))
(in-package #:sprolog)
