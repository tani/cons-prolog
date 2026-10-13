;;; Selected public interface, without internal implementation exports.
(uiop:define-package #:sprolog/src/api/public
  (:use #:cl)
  (:import-from #:sprolog/src/library/standard-library)
  (:import-from #:sprolog/src/prolog/loader #:load-prolog #:load-prolog-string #:load-prolog-file)
  (:import-from #:sprolog/src/prolog/reader #:read-prolog-term #:parse-prolog-string)
  (:import-from #:sprolog/src/api/api #:<- #:<-- #:?- #:prolog #:--> #:--->)
  (:import-from #:sprolog/src/api/registry #:builtin-predicate-inventory)
  (:import-from #:sprolog/src/api/state #:*iso-halt-function*)
  (:import-from #:sprolog/src/kernel/engine #:next-solution #:close-query #:*database*
    #:query-statistics)
  (:import-from #:sprolog/src/kernel/gc #:collect-query-garbage)
  (:import-from #:sprolog/src/kernel/instructions #:tnot)
  (:import-from #:sprolog/src/kernel/model #:slg-incomplete-cut #:make-database #:iso-exception
    #:iso-exception-term)
  (:import-from #:sprolog/src/kernel/slg #:table #:untable)
  (:import-from #:sprolog/src/syntax/compiler #:query #:make-query #:clear-database
    #:disassemble-predicate)
  (:import-from #:sprolog/src/syntax/dcg #:phrase #:dcg-expand)
  (:export #:load-prolog #:load-prolog-string #:load-prolog-file #:read-prolog-term #:parse-prolog-string
    #:<- #:<-- #:?- #:prolog #:--> #:---> #:phrase #:dcg-expand #:query #:make-query
    #:next-solution #:slg-incomplete-cut #:table #:untable #:tnot #:close-query #:clear-database
    #:*database* #:make-database #:*iso-halt-function* #:iso-exception #:iso-exception-term
    #:builtin-predicate-inventory #:collect-query-garbage #:query-statistics
    #:disassemble-predicate))
(in-package #:sprolog/src/api/public)
