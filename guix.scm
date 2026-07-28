; SPDX-License-Identifier: MPL-2.0
;; guix.scm — GNU Guix package definition for squisher-corpus
;; Usage: guix shell -f guix.scm

(use-modules (guix packages)
             (guix build-system gnu)
             (guix licenses))

(package
  (name "squisher-corpus")
  (version "0.1.0")
  (source #f)
  (build-system gnu-build-system)
  (native-inputs
   (list rust zig just idris2 elixir erlang))
  (synopsis "Development environment for Universal Modding Studio")
  (description "Provides toolchains required by Universal Modding Studio.")
  (home-page "https://github.com/metadatastician/universal-modding-studio")
  (license agpl3+))
