-- SPDX-License-Identifier: AGPL-3.0-or-later
-- SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-- Assassin.idr — Assassin encounter configuration
module Assassin

import Primitives

%default total

||| Configuration for assassin encounters in a level.
public export
record AssassinConfig where
  constructor MkAssassinConfig
  spawnX           : WorldX
  ambushCount      : Nat
  retreatThreshold : Nat
