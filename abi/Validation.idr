-- SPDX-License-Identifier: AGPL-3.0-or-later
-- SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-- Validation.idr — Cross-domain validation proofs for level integrity
module Validation

import Data.Fin
import Decidable.Equality
import Primitives
import Types
import Devices
import Zones
import Guards
import Level

%default total

------------------------------------------------------------------------
-- Proof: a device IP exists in the device registry
------------------------------------------------------------------------

||| Witness that a given IP address appears in a list of devices.
public export
data InRegistry : (device : IpAddress) -> (devs : List DeviceSpec) -> Type where
  ||| The device is at the head of the list.
  Here  : (prf : ip d = addr) -> InRegistry addr (d :: ds)
  ||| The device is somewhere in the tail.
  There : InRegistry addr ds -> InRegistry addr (d :: ds)

------------------------------------------------------------------------
-- Proof: all guards reference valid zones
------------------------------------------------------------------------

||| Witness that a zone name appears in the zone list.
public export
data ZoneExists : (zoneName : String) -> (zs : List Zone) -> Type where
  ZoneHere  : (prf : name z = n) -> ZoneExists n (z :: zs)
  ZoneThere : ZoneExists n zs -> ZoneExists n (z :: zs)

||| Witness that every guard's zone field names a valid zone.
public export
data GuardsInZones : (gs : List GuardPlacement) -> (zs : List Zone) -> Type where
  ||| No guards — trivially valid.
  NoGuards  : GuardsInZones [] zs
  ||| Head guard is in a valid zone, and the rest are too.
  GuardOk   : ZoneExists (zone g) zs
           -> GuardsInZones gs2 zs
           -> GuardsInZones (g :: gs2) zs

------------------------------------------------------------------------
-- Proof: defence failover/cascade/mirror targets reference real devices
------------------------------------------------------------------------

||| Helper: if a Maybe IpAddress is Just, that IP is in the registry.
public export
data MaybeInRegistry : (target : Maybe IpAddress) -> (devs : List DeviceSpec) -> Type where
  ||| Target is Nothing — no constraint.
  TargetNone : MaybeInRegistry Nothing devs
  ||| Target is Just addr — addr must be in registry.
  TargetSome : InRegistry addr devs -> MaybeInRegistry (Just addr) devs

||| Witness that all defence config targets reference real devices.
public export
data DefenceTargetsValid : (defs : List DeviceDefenceConfig) -> (devs : List DeviceSpec) -> Type where
  ||| No defences — trivially valid.
  NoDefences  : DefenceTargetsValid [] devs
  ||| Head defence has valid targets, and the rest do too.
  DefenceOk   : InRegistry (ip d) devs
             -> MaybeInRegistry (failoverTarget (flags d)) devs
             -> MaybeInRegistry (cascadeTrap (flags d)) devs
             -> MaybeInRegistry (mirrorTarget (flags d)) devs
             -> DefenceTargetsValid ds devs
             -> DefenceTargetsValid (d :: ds) devs

------------------------------------------------------------------------
-- Proof: zone transitions are monotonically increasing in X
------------------------------------------------------------------------

||| Witness that zone transitions are ordered by world X position.
public export
data ZonesOrdered : (transitions : List ZoneTransition) -> Type where
  ||| Empty list is ordered.
  ZonesNil  : ZonesOrdered []
  ||| Single transition is ordered.
  ZonesOne  : ZonesOrdered [t]
  ||| Consecutive transitions: first X <= second X, and the tail is ordered.
  ZonesCons : (lte : position (worldX t1) <= position (worldX t2) = True)
           -> ZonesOrdered (t2 :: ts)
           -> ZonesOrdered (t1 :: t2 :: ts)

------------------------------------------------------------------------
-- Proof: PBX consistency
------------------------------------------------------------------------

||| When hasPBX is True, the pbxAddr must exist in the device registry.
||| When hasPBX is False, no constraint is imposed.
public export
data PBXConsistent : (enabled : Bool) -> (pbxAddr : IpAddress) -> (devs : List DeviceSpec) -> Type where
  ||| PBX is disabled — no constraint.
  PBXOff : PBXConsistent False pbxAddr devs
  ||| PBX is enabled — its IP must be in the registry.
  PBXOn  : InRegistry pbxAddr devs -> PBXConsistent True pbxAddr devs

------------------------------------------------------------------------
-- Validated level: level data + all proofs, erased at runtime
------------------------------------------------------------------------

||| A level that has been validated against all cross-domain invariants.
||| Proof fields are erased (0-quantity) so they have zero runtime cost.
public export
record ValidatedLevel where
  constructor MkValidatedLevel
  levelData          : LevelData
  0 devicesExist     : DefenceTargetsValid (deviceDefences levelData) (devices levelData)
  0 guardsValid      : GuardsInZones (guards levelData) (zones levelData)
  0 zonesMonotonic   : ZonesOrdered (zoneTransitions levelData)
  0 pbxOk            : PBXConsistent (hasPBX levelData) (pbxIp levelData) (devices levelData)

------------------------------------------------------------------------
-- Decision procedures
--
-- Until 2026-07-27 this module declared every witness type above and
-- provided no way to build one. `ValidatedLevel` appeared nowhere else in
-- the repository, the extractor returned raw unvalidated `LevelData`, and so
-- no `ValidatedLevel` could be constructed by any code that existed. The
-- module typechecked -- declaring a datatype always does -- and counted
-- toward "17/17 modules typecheck" while proving nothing.
--
-- These deciders close that gap. Each returns `Dec`, so a `No` carries a
-- proof that the witness is impossible rather than merely failing to find
-- one, and `validateLevel` below is the only route from `LevelData` to
-- `ValidatedLevel`.
------------------------------------------------------------------------

public export
DecEq IpAddress where
  decEq (MkIpAddress a1 a2 a3 a4) (MkIpAddress b1 b2 b3 b4) =
    case decEq a1 b1 of
      No c => No (\Refl => c Refl)
      Yes Refl => case decEq a2 b2 of
        No c => No (\Refl => c Refl)
        Yes Refl => case decEq a3 b3 of
          No c => No (\Refl => c Refl)
          Yes Refl => case decEq a4 b4 of
            No c => No (\Refl => c Refl)
            Yes Refl => Yes Refl

export
Uninhabited (InRegistry addr []) where
  uninhabited (Here _) impossible
  uninhabited (There _) impossible

export
Uninhabited (ZoneExists n []) where
  uninhabited (ZoneHere _) impossible
  uninhabited (ZoneThere _) impossible

||| Decide whether an IP appears in the device registry.
public export
decInRegistry : (addr : IpAddress) -> (devs : List DeviceSpec)
             -> Dec (InRegistry addr devs)
decInRegistry addr [] = No absurd
decInRegistry addr (d :: ds) = case decEq (ip d) addr of
  Yes prf => Yes (Here prf)
  No notHead => case decInRegistry addr ds of
    Yes rest => Yes (There rest)
    No notTail => No (\w => case w of
                              Here p  => notHead p
                              There r => notTail r)

||| Decide whether a zone name appears in the zone list.
public export
decZoneExists : (n : String) -> (zs : List Zone) -> Dec (ZoneExists n zs)
decZoneExists n [] = No absurd
decZoneExists n (z :: zs) = case decEq (name z) n of
  Yes prf => Yes (ZoneHere prf)
  No notHead => case decZoneExists n zs of
    Yes rest => Yes (ZoneThere rest)
    No notTail => No (\w => case w of
                              ZoneHere p  => notHead p
                              ZoneThere r => notTail r)

||| Decide whether every guard names a zone that exists.
public export
decGuardsInZones : (gs : List GuardPlacement) -> (zs : List Zone)
                -> Dec (GuardsInZones gs zs)
decGuardsInZones [] zs = Yes NoGuards
decGuardsInZones (g :: gs) zs = case decZoneExists (zone g) zs of
  No notHead => No (\w => case w of GuardOk h _ => notHead h)
  Yes here => case decGuardsInZones gs zs of
    Yes rest => Yes (GuardOk here rest)
    No notTail => No (\w => case w of GuardOk _ r => notTail r)

||| Decide the optional-target case.
public export
decMaybeInRegistry : (target : Maybe IpAddress) -> (devs : List DeviceSpec)
                  -> Dec (MaybeInRegistry target devs)
decMaybeInRegistry Nothing devs = Yes TargetNone
decMaybeInRegistry (Just addr) devs = case decInRegistry addr devs of
  Yes prf => Yes (TargetSome prf)
  No contra => No (\w => case w of TargetSome p => contra p)

||| Decide whether every defence config targets a real device.
public export
decDefenceTargetsValid : (defs : List DeviceDefenceConfig)
                      -> (devs : List DeviceSpec)
                      -> Dec (DefenceTargetsValid defs devs)
decDefenceTargetsValid [] devs = Yes NoDefences
decDefenceTargetsValid (d :: ds) devs =
  case decInRegistry (ip d) devs of
    No c => No (\w => case w of DefenceOk s _ _ _ _ => c s)
    Yes self => case decMaybeInRegistry (failoverTarget (flags d)) devs of
      No c => No (\w => case w of DefenceOk _ f _ _ _ => c f)
      Yes fo => case decMaybeInRegistry (cascadeTrap (flags d)) devs of
        No c => No (\w => case w of DefenceOk _ _ ct _ _ => c ct)
        Yes ca => case decMaybeInRegistry (mirrorTarget (flags d)) devs of
          No c => No (\w => case w of DefenceOk _ _ _ m _ => c m)
          Yes mi => case decDefenceTargetsValid ds devs of
            Yes rest => Yes (DefenceOk self fo ca mi rest)
            No c => No (\w => case w of DefenceOk _ _ _ _ r => c r)

||| Decide whether zone transitions are monotonically ordered in world X.
public export
decZonesOrdered : (ts : List ZoneTransition) -> Dec (ZonesOrdered ts)
decZonesOrdered [] = Yes ZonesNil
decZonesOrdered (t :: []) = Yes ZonesOne
decZonesOrdered (t1 :: t2 :: ts) =
  case decEq (position (worldX t1) <= position (worldX t2)) True of
    No c => No (\w => case w of ZonesCons l _ => c l)
    Yes lte => case decZonesOrdered (t2 :: ts) of
      Yes rest => Yes (ZonesCons lte rest)
      No c => No (\w => case w of ZonesCons _ r => c r)

||| Decide PBX consistency.
public export
decPBXConsistent : (enabled : Bool) -> (pbxAddr : IpAddress)
                -> (devs : List DeviceSpec)
                -> Dec (PBXConsistent enabled pbxAddr devs)
decPBXConsistent False pbxAddr devs = Yes PBXOff
decPBXConsistent True pbxAddr devs = case decInRegistry pbxAddr devs of
  Yes prf => Yes (PBXOn prf)
  No contra => No (\w => case w of PBXOn p => contra p)

||| The only route from raw `LevelData` to a `ValidatedLevel`.
|||
||| Returns `Just` exactly when all four cross-domain invariants hold, and the
||| returned record carries the erased witnesses establishing them. Callers
||| that require a validated level can now demand `ValidatedLevel` in their
||| signature and be sure the checks ran.
public export
validateLevel : (l : LevelData) -> Maybe ValidatedLevel
validateLevel l =
  case decDefenceTargetsValid (deviceDefences l) (devices l) of
    No _ => Nothing
    Yes dv => case decGuardsInZones (guards l) (zones l) of
      No _ => Nothing
      Yes gv => case decZonesOrdered (zoneTransitions l) of
        No _ => Nothing
        Yes zo => case decPBXConsistent (hasPBX l) (pbxIp l) (devices l) of
          No _ => Nothing
          Yes pb => Just (MkValidatedLevel l dv gv zo pb)

------------------------------------------------------------------------
-- Compile-time evidence that the deciders decide
--
-- These are not runtime tests. Each is a propositional equality checked by
-- the typechecker, so the build fails if a decider stops returning what it
-- should. They exist because a `Dec`-returning function that always answered
-- `No` would still typecheck, still be total, and still be useless.
------------------------------------------------------------------------

||| A registry lookup in an empty list is refuted, not merely unproven.
export
emptyRegistryRefutes : (addr : IpAddress) -> Not (InRegistry addr [])
emptyRegistryRefutes addr = absurd

||| No guards is trivially valid, for any zone list.
export
noGuardsAccepted : (zs : List Zone) -> decGuardsInZones [] zs = Yes NoGuards
noGuardsAccepted zs = Refl

||| An absent optional target imposes no constraint.
export
noTargetAccepted : (devs : List DeviceSpec)
                -> decMaybeInRegistry Nothing devs = Yes TargetNone
noTargetAccepted devs = Refl

||| An empty transition list is ordered.
export
noTransitionsOrdered : decZonesOrdered [] = Yes ZonesNil
noTransitionsOrdered = Refl

||| A single transition is ordered without comparing anything.
export
oneTransitionOrdered : (t : ZoneTransition) -> decZonesOrdered [t] = Yes ZonesOne
oneTransitionOrdered t = Refl

||| A disabled PBX imposes no registry constraint.
export
pbxOffAccepted : (addr : IpAddress) -> (devs : List DeviceSpec)
              -> decPBXConsistent False addr devs = Yes PBXOff
pbxOffAccepted addr devs = Refl

||| An enabled PBX with an empty registry is refuted: there is no device for
||| its address to be, so no witness can exist.
export
pbxOnEmptyRefuted : (addr : IpAddress) -> Not (PBXConsistent True addr [])
pbxOnEmptyRefuted addr (PBXOn p) = absurd p
