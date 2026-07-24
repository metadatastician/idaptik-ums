;; SPDX-License-Identifier: AGPL-3.0-or-later
;; SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
(use-modules (guix packages)
             (guix download)
             (guix build-system gnu)
             (guix licenses)
             (gnu packages)
             (gnu packages rust)
             (gnu packages zig)
             (gnu packages build-tools)
             (gnu packages elixir)
             (gnu packages erlang)
             (gnu packages idris))

(package
  (name "universal-modding-studio-env")
  (version "0.1.0")
  (source #f)
  (build-system gnu-build-system)
  (native-inputs
   (list rust zig just idris2 elixir erlang))
  (synopsis "Development environment for Universal Modding Studio")
  (description "Provides toolchains required by Universal Modding Studio.")
  (home-page "https://github.com/metadatastician/universal-modding-studio")
  (license gpl3+))
