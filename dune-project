(lang dune 3.0)

(name miaou-composer)

(generate_opam_files true)

(package
 (name miaou-composer)
 (synopsis "Live dynamic UI compositor for Miaou TUI applications")
 (depends
  (ocaml (>= 5.1))
  (miaou-core (>= 0.4))
  (miaou-runner (>= 0.4))
  (yojson (>= 2.0))
  (eio (>= 1.0))
  (eio_main (>= 1.0))
  (alcotest (and :with-test (>= 1.0)))))
