(require :asdf)
(asdf:load-asd (merge-pathnames "../sprolog.asd" *load-truename*))
(asdf:test-system "sprolog")
