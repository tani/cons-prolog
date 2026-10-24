(require :asdf)
(asdf:load-asd (merge-pathnames "../cons-prolog.asd" *load-truename*))
(asdf:test-system "cons-prolog")
