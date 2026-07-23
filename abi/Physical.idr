-- SPDX-License-Identifier: AGPL-3.0-or-later
-- SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-- Physical.idr — Physical world configuration
module Physical

%default total

||| Physical properties of the game world.
public export
record PhysicalConfig where
  constructor MkPhysicalConfig
  groundY             : Double
  worldWidth          : Double
  interactionDistance  : Double
  hasPowerSystem      : Bool
  hasSecurityCameras  : Bool
  numberOfCovertLinks : Nat
