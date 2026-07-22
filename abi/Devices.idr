-- SPDX-License-Identifier: AGPL-3.0-or-later
-- SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-- Devices.idr — Device specifications and defence configurations
module Devices

import Primitives
import Types

%default total

||| A device placed in the game world.
public export
record DeviceSpec where
  constructor MkDeviceSpec
  kind     : DeviceKind
  ip       : IpAddress
  name     : String
  security : SecurityLevel

||| Defence flags that can be applied to any device.
public export
record DefenceFlags where
  constructor MkDefenceFlags
  tamperProof          : Bool
  decoy                : Bool
  canary               : Bool
  oneWayMirror         : Bool
  killSwitch           : Bool
  failoverTarget       : Maybe IpAddress
  cascadeTrap          : Maybe IpAddress
  mirrorTarget         : Maybe IpAddress
  instructionWhitelist : Maybe (List String)
  timeBomb             : Maybe Nat
  undoImmunity         : Maybe Nat

||| Sensible defaults: all defences off.
public export
defaultDefenceFlags : DefenceFlags
defaultDefenceFlags = MkDefenceFlags
  False False False False False
  Nothing Nothing Nothing Nothing Nothing Nothing

||| Associates defence flags with a specific device by IP.
public export
record DeviceDefenceConfig where
  constructor MkDeviceDefenceConfig
  ip    : IpAddress
  flags : DefenceFlags
