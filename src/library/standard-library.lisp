(uiop:define-package #:sprolog/src/library/standard-library
  (:use #:cl)
  (:import-from #:sprolog/src/api/state
    #:*standard-predicates*)
  (:import-from #:sprolog/src/kernel/engine
    #:predicate-key)
  (:import-from #:sprolog/src/kernel/instructions
    #:call #:fail #:true)
  (:import-from #:sprolog/src/kernel/model
    #:make-predicate)
  (:import-from #:sprolog/src/syntax/compiler
    #:compile-predicate)
  (:import-from #:sprolog/src/kernel/protocol)
  (:import-from #:sprolog/src/adapters/builtins)
  (:export #:install-standard-predicate))
(in-package #:sprolog/src/library/standard-library)


(defun install-standard-predicate (clauses)
  "Compile ordinary clauses into the shared, protected base library."
  (let ((key (predicate-key (caar clauses))))
    (setf (gethash (cons (string-upcase (symbol-name (car key))) (cdr key))
                   *standard-predicates*)
          (make-predicate :clauses clauses :code (compile-predicate clauses)
                          :adapter-context
                          (member (string-upcase (symbol-name (car key)))
                                  '("OPEN" "CLOSE" "HALT" "NL" "FLUSH_OUTPUT"
                                    "AT_END_OF_STREAM" "GET_CHAR" "GET_CODE"
                                    "PEEK_CHAR" "PEEK_CODE" "GET_BYTE" "PEEK_BYTE"
                                    "PUT_CHAR" "PUT_CODE" "PUT_BYTE" "ATOM_LENGTH"
                                    "ATOM_CHARS" "NUMBER_CHARS" "SUB_ATOM" "RETRACTALL"
                                    "@<" "@=<" "@>" "@>=" "SETOF" "READ" "READ_TERM"
                                    "WRITE" "WRITEQ" "WRITE_CANONICAL" "WRITE_TERM")
                                  :test #'string=)))))

(eval-when (:load-toplevel :execute)
  (clrhash *standard-predicates*)
  (dolist (clauses
           '((((|\\+| ?goal) (call ?goal) ! fail)
              ((|\\+| ?goal)))
             (((once ?goal) (call ?goal) !))
             (((repeat)) ((repeat) (repeat)))
             (((nonvar ?x) (|\\+| (var ?x))))
             (((number ?x) (integer ?x)) ((number ?x) (float ?x)))
             (((callable ?x) (atom ?x)) ((callable ?x) (compound ?x)))
             (((ground ?x) (term_variables ?x ())))
             (((|\\=| ?x ?y) (|\\+| (= ?x ?y))))
             (((|\\==| ?x ?y) (|\\+| (== ?x ?y))))))
    (install-standard-predicate clauses)))

;;; Adapter wrappers are ordinary clauses; only explicit-stream operations
;;; and argument validation require the host boundary.
(eval-when (:load-toplevel :execute)
  (dolist (clauses
           '((((open ?file ?mode ?stream) (open ?file ?mode ?stream ())))
             (((close ?stream) (close ?stream ())))
             (((halt) (halt 0)))
             (((nl) (current_output ?stream) (nl ?stream)))
             (((nl ?stream) (put_code ?stream 10)))
             (((flush_output) (current_output ?stream) (flush_output ?stream)))
             (((at_end_of_stream) (current_input ?stream) (at_end_of_stream ?stream)))
             (((atom_length ?atom ?length)
               (%output_nonnegative ?length) (atom_codes ?atom ?codes)
               (%list_length ?codes 0 ?length)))
             (((%list_length () ?n ?n))
              ((%list_length (?head . ?tail) ?n ?length)
               (is ?next (+ ?n 1)) (%list_length ?tail ?next ?length)))
             (((sub_atom ?atom ?before ?length ?after ?sub)
               (%sub_atom_arguments ?atom ?before ?length ?after ?sub)
               (atom_concat ?prefix ?rest ?atom)
               (atom_concat ?sub ?suffix ?rest)
               (atom_length ?prefix ?before)
               (atom_length ?sub ?length)
               (atom_length ?suffix ?after)))))
    (install-standard-predicate clauses))
  (dolist (name '(get_char get_code peek_char peek_code get_byte peek_byte
                 put_char put_code put_byte))
    (install-standard-predicate
     (list (list (list name '?value)
                 (list (if (member name '(put_char put_code put_byte))
                           'current_output 'current_input) '?stream)
                 (list name '?stream '?value))))))

;;; Graph copying remains internal to FINDALL. RETRACTALL only needs the
;;; database boundary to ensure an empty dynamic predicate is observable.
(eval-when (:load-toplevel :execute)
  (dolist (clauses
           '((((copy_term ?term ?copy) (findall ?term true (?copy))))
             (((retractall ?head) (%ensure_dynamic ?head) (%retractall ?head)))
             (((%retractall ?head) (%retract_head ?head) fail)
              ((%retractall ?head)))))
    (install-standard-predicate clauses)))

(eval-when (:load-toplevel :execute)
  (dolist (clauses
           '((((atom_chars ?atom ?chars)
               (%chars_arguments atom ?atom ?chars)
               (or (-> (var ?atom)
                       (and (%chars_codes ?chars ?codes) (atom_codes ?atom ?codes)))
                   (and (atom_codes ?atom ?codes) (%chars_codes ?chars ?codes)))))
             (((number_chars ?number ?chars)
               (%chars_arguments number ?number ?chars)
               (or (-> (var ?number)
                       (and (%chars_codes ?chars ?codes) (number_codes ?number ?codes)))
                   (and (number_codes ?number ?codes) (%chars_codes ?chars ?codes)))))
             (((%chars_codes () ()))
              ((%chars_codes (?char . ?chars) (?code . ?codes))
               (char_code ?char ?code) (%chars_codes ?chars ?codes)))))
    (install-standard-predicate clauses)))

(eval-when (:load-toplevel :execute)
  (dolist (clauses
           '((((@< ?a ?b) (compare < ?a ?b)))
             (((@> ?a ?b) (compare > ?a ?b)))
             (((@=< ?a ?b) (compare ?order ?a ?b) (|\\==| ?order >)))
             (((@>= ?a ?b) (compare ?order ?a ?b) (|\\==| ?order <)))
             (((setof ?template ?goal ?set) (bagof ?template ?goal ?bag) (sort ?bag ?set)))))
    (install-standard-predicate clauses)))

(eval-when (:load-toplevel :execute)
  (dolist (clauses
           '((((read ?term) (current_input ?stream) (read ?stream ?term)))
             (((read ?stream ?term) (read_term ?stream ?term ())))
             (((read_term ?term ?options) (current_input ?stream) (read_term ?stream ?term ?options)))
             (((write_term ?term ?options) (current_output ?stream) (write_term ?stream ?term ?options)))))
    (install-standard-predicate clauses))
  (dolist (name '(write writeq write_canonical))
    (install-standard-predicate (list (list (list name '?term) '(current_output ?stream) (list name '?stream '?term))))
    (install-standard-predicate (list (list (list name '?stream '?term)
      (list 'write_term '?stream '?term
            (case name (write nil) (writeq '((quoted true) (numbervars true)))
                       (write_canonical '((quoted true) (ignore_ops true))))))))))
