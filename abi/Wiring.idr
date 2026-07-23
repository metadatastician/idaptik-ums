-- SPDX-License-Identifier: AGPL-3.0-or-later
-- SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-- Wiring.idr — Hardware wiring challenges (ADR-0012)
module Wiring

import Primitives

%default total

||| Types of physical wiring challenge.
public export
data WiringType
  = PatchPanel
  | SwitchBackplane
  | ServerRack
  | FibreSplicing
  | PBXComms

||| A wiring challenge attached to a specific device.
public export
record WiringChallenge where
  constructor MkWiringChallenge
  kind       : WiringType
  deviceIp   : IpAddress
  difficulty : Nat
