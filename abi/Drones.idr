-- SPDX-License-Identifier: AGPL-3.0-or-later
-- SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-- Drones.idr — Drone placement
module Drones

import Primitives
import Types

%default total

||| A drone placed in the game world.
public export
record DronePlacement where
  constructor MkDronePlacement
  worldX    : WorldX
  archetype : DroneArchetype
  altitude  : Double
