;;; Selected public interface, without internal implementation exports.
(uiop:define-package #:cons-prolog/src/api/public
  (:use #:cl)
  (:import-from #:cons-prolog/src/library/standard-library)
  (:import-from #:cons-prolog/src/prolog/loader #:load-prolog #:load-prolog-string #:load-prolog-file)
  (:import-from #:cons-prolog/src/prolog/reader #:read-prolog-term #:parse-prolog-string)
  (:import-from #:cons-prolog/src/api/api #:<- #:<-- #:?- #:prolog #:--> #:--->)
  (:import-from #:cons-prolog/src/api/registry #:builtin-predicate-inventory)
  (:import-from #:cons-prolog/src/api/state #:*iso-halt-function*)
  (:import-from #:cons-prolog/src/kernel/engine #:next-solution #:close-query #:*database*
    #:query-statistics)
  (:import-from #:cons-prolog/src/kernel/gc #:collect-query-garbage)
  (:import-from #:cons-prolog/src/kernel/instructions #:tnot)
  (:import-from #:cons-prolog/src/kernel/model #:slg-incomplete-cut #:make-database #:iso-exception
    #:iso-exception-term #:database-term-model #:$cons #:$nil)
  (:import-from #:cons-prolog/src/kernel/slg #:table #:untable)
  (:import-from #:cons-prolog/src/syntax/compiler #:query #:make-query #:clear-database
    #:disassemble-predicate)
  (:import-from #:cons-prolog/src/syntax/dcg #:phrase #:dcg-expand)
  (:export #:load-prolog #:load-prolog-string #:load-prolog-file #:read-prolog-term #:parse-prolog-string
    #:<- #:<-- #:?- #:prolog #:--> #:---> #:phrase #:dcg-expand #:query #:make-query
    #:next-solution #:slg-incomplete-cut #:table #:untable #:tnot #:close-query #:clear-database
    #:*database* #:make-database #:database-term-model #:$cons #:$nil #:*iso-halt-function* #:iso-exception #:iso-exception-term
    #:builtin-predicate-inventory #:collect-query-garbage #:query-statistics
    #:disassemble-predicate))
(in-package #:cons-prolog/src/api/public)
