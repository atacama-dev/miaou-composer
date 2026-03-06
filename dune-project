(lang dune 3.0)

(name miaou-composer)

(generate_opam_files true)

(package
 (name miaou-composer)
 (synopsis "Live dynamic UI compositor for Miaou TUI applications")
 (license "GPL-3.0-or-later")
 (authors "Mathias Bourgoin <mathias.bourgoin@atacama.tech>")
 (maintainers "Mathias Bourgoin <mathias.bourgoin@atacama.tech>")
 (homepage "https://github.com/atacama-dev/miaou-composer")
 (source (github atacama-dev/miaou-composer))
 (bug_reports "https://github.com/atacama-dev/miaou-composer/issues")
 (depends
  (ocaml (>= 5.2))
  (miaou-core (>= 0.4.2))
  (miaou-runner (>= 0.4.2))
  (miaou-registry (>= 0.4.2))
  (yojson (>= 2.0))
  (eio (>= 1.0))
  (eio_main (>= 1.0))
  (alcotest (and :with-test (>= 1.0)))))
