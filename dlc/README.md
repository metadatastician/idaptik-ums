<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk> -->
# DLC (UMS payload)

- `vm/`              — 23-instruction reversible VM in AffineScript with
                       property tests. Consolidated from the retired
                       `hyperpolymath/idaptik-dlc-vm` repo.
- `legacy-puzzles/` — Authored puzzle JSON preserved from the retired
                         `hyperpolymath/idaptik-dlc-iky` repo. Loadable by
                         `vm/` (instruction set is a superset).

Every artifact here is held to the bridge contracts in `../schemas/`
(manifest envelope + puzzle payload schemas). Run `just dlc-check` to
validate the lot; a failure means the bridge to the game is broken.
