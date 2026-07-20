-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
-- ProvenBridge.idr — idaptik's use of the proven library.
--
-- Re-exports the five Safe* modules idaptik depends on, plus the
-- idaptik-domain extractors (LevelData / DeviceSpec / Zone / Guard /
-- ZoneTransition) and game-specific combinators built on them.
--
-- Before the proven dependency landed, this file was a 1658-line
-- placeholder mirroring each proven module locally so idaptik could
-- compile in isolation. Closes idaptik-side of hyperpolymath/proven#8.
module ProvenBridge

import public Proven.SafeJson           -- JsonValue + get/asString/asNumber/asInt/asBool/asArray/asObject
import public Proven.SafeJson.Parser    -- parse, ParseError, JsonValue constructors
import public Proven.SafeJson.Access    -- field, AccessError, getAt, etc.
import public Proven.SafeMath           -- addChecked, subChecked, mulChecked, divChecked, clamp, percentOf
import public Proven.SafeString         -- charAt, substring, trim, truncate, split, isAscii, parseNat, parseInt
import public Proven.SafeCrypto         -- Byte, Bytes, constantTimeEq, hexToBytes, bytesToHex
import public Proven.SafeInput          -- InputBuffer, Keystroke, CharClass, InputResult, handleKey, validate*

import Primitives
import Types
import Devices
import Zones
import Inventory
import Guards
import Dogs
import Drones
import Assassin
import Mission
import Wiring
import Physical
import Level
import Validation

import Data.Fin
import Data.List
import Data.List1
import Data.String

%default total

-- Wide tuple scrutinees (up to 9 fields in extractLevelData) nest
-- Builtin.MkPair beyond the default ambiguity depth of 3.
%ambiguity_depth 12

-- Hide Ok / Err brought in via Proven.Core (where `data Result` is
-- declared directly in the module, so the constructors' full names are
-- Proven.Core.Ok / Proven.Core.Err) so the local Extracted type's
-- Got/Errs constructors disambiguate without explicit qualification.
%hide Proven.Core.Ok
%hide Proven.Core.Err

-- Prefer Proven.SafeString's trim/padRight over Data.String's: this
-- bridge exists to route through proven, and the unqualified uses in
-- the string helpers below are otherwise ambiguous.
%hide Data.String.trim
%hide Data.String.padRight

------------------------------------------------------------------------
-- Level data extraction from JSON (idaptik-domain, built on Proven.SafeJson)
------------------------------------------------------------------------

||| Errors collected during level data extraction.
||| Each entry is a human-readable description of what went wrong.
public export
ExtractionErrors : Type
ExtractionErrors = List String

||| Result of extracting a value: either the value or accumulated errors.
||| We use `List String` rather than a single error so extraction can
||| report ALL problems in one pass, not just the first.
|||
||| The constructor is named `Got` (not `Ok`) to avoid ambiguity with
||| `Proven.Core.Result.Ok`, which is in scope via the `Proven.SafeJson`
||| re-export above.
public export
data Extracted : Type -> Type where
  ||| Extraction succeeded with a value.
  Got  : a -> Extracted a
  ||| Extraction failed with one or more error descriptions.
  Errs : (errors : ExtractionErrors) -> Extracted a

||| Functor-like map for Extracted.
export
mapExtracted : (a -> b) -> Extracted a -> Extracted b
mapExtracted f (Got x)    = Got (f x)
mapExtracted _ (Errs es)  = Errs es

||| Combine two Extracted values, accumulating errors from both sides.
export
combineExtracted : Extracted a -> Extracted b -> Extracted (a, b)
combineExtracted (Got x)   (Got y)   = Got (x, y)
combineExtracted (Errs e1) (Errs e2) = Errs (e1 ++ e2)
combineExtracted (Errs e1) _         = Errs e1
combineExtracted _         (Errs e2) = Errs e2

||| Convert an Extracted to Either, joining errors with newlines.
export
extractedToEither : Extracted a -> Either String a
extractedToEither (Got x)   = Right x
extractedToEither (Errs es) = Left (joinBy "\n" es)

||| Error contents of an Extracted; empty when extraction succeeded.
||| Works across differently-typed extraction results (unlike folding a
||| `List (Extracted a)`, which forces every element to one type), so
||| call sites can concatenate errors from heterogeneous record fields.
export
errsOf : Extracted a -> ExtractionErrors
errsOf (Got _)   = []
errsOf (Errs es) = es

export
Functor Extracted where
  map = mapExtracted

||| Error-ACCUMULATING applicative (like Haskell's Validation): when
||| both sides fail, `<*>` keeps the errors of both. Lets record
||| extractors chain differently-typed fields while still reporting
||| every problem in one pass.
export
Applicative Extracted where
  pure = Got
  (Got f)   <*> (Got x)   = Got (f x)
  (Errs e1) <*> (Errs e2) = Errs (e1 ++ e2)
  (Errs e1) <*> _         = Errs e1
  _         <*> (Errs e2) = Errs e2

||| Extract a Nat from a JSON value (returns Nothing for negatives).
||| Proven.SafeJson exposes `asInt` but not `asNat`; this is the
||| idaptik-side helper that adds the non-negativity check.
export
asNat : JsonValue -> Maybe Nat
asNat (JsonNumber n) = if n >= 0.0 then Just (cast (cast {to=Integer} n)) else Nothing
asNat _              = Nothing

||| Require a field to exist and satisfy a predicate.
export
requireField : String -> String -> (JsonValue -> Maybe a) -> JsonValue -> Extracted a
requireField context fieldName extract json =
  case get fieldName json of
    Nothing  => Errs [context ++ ": missing required field '" ++ fieldName ++ "'"]
    Just val =>
      case extract val of
        Nothing => Errs [context ++ ": field '" ++ fieldName ++ "' has wrong type"]
        Just x  => Got x

||| Require an optional field: if present it must parse, if absent returns Nothing.
export
optionalField : String -> String -> (JsonValue -> Maybe a) -> JsonValue -> Extracted (Maybe a)
optionalField context fieldName extract json =
  case get fieldName json of
    Nothing  => Got Nothing
    Just val =>
      case extract val of
        Nothing => Errs [context ++ ": field '" ++ fieldName ++ "' has wrong type"]
        Just x  => Got (Just x)

------------------------------------------------------------------------
-- Octet / IpAddress extraction
------------------------------------------------------------------------

||| Parse an octet (0-255) from a JsonValue number.
export
extractOctet : String -> JsonValue -> Extracted (Fin 256)
extractOctet context json =
  case asInt json of
    Nothing => Errs [context ++ ": expected integer for octet"]
    Just n  =>
      if n >= 0 && n <= 255
        then case natToFin (cast n) 256 of
               Just f  => Got f
               Nothing => Errs [context ++ ": octet out of range (internal)"]
        else Errs [context ++ ": octet " ++ show n ++ " out of range 0-255"]

||| Parse an IP address from a JSON string in "a.b.c.d" format.
export
extractIpAddress : String -> JsonValue -> Extracted IpAddress
extractIpAddress context json =
  case asString json of
    Nothing => Errs [context ++ ": expected string for IP address"]
    Just s  =>
      case Data.String.split (== '.') s of
        -- split returns a List1 (SnocList), so we convert and check length
        parts =>
          let partsList = forget parts
          in case partsList of
               [a, b, c, d] =>
                 case (parseOctetStr a, parseOctetStr b, parseOctetStr c, parseOctetStr d) of
                   (Just o1, Just o2, Just o3, Just o4) =>
                     Got (MkIpAddress o1 o2 o3 o4)
                   _ => Errs [context ++ ": invalid IP address octets in '" ++ s ++ "'"]
               _ => Errs [context ++ ": IP address must have exactly 4 octets, got '" ++ s ++ "'"]
  where
    ||| Parse a single octet string to Fin 256.
    parseOctetStr : String -> Maybe (Fin 256)
    parseOctetStr s =
      case parsePositive {a=Integer} s of
        Nothing => Nothing
        Just n  => if n >= 0 && n <= 255
                     then natToFin (cast n) 256
                     else Nothing

------------------------------------------------------------------------
-- Enum extraction helpers
------------------------------------------------------------------------

||| Parse a SecurityLevel from a JSON string.
export
extractSecurityLevel : String -> JsonValue -> Extracted SecurityLevel
extractSecurityLevel ctx json =
  case asString json of
    Nothing => Errs [ctx ++ ": expected string for security level"]
    Just "open"   => Got Open
    Just "weak"   => Got Weak
    Just "medium" => Got Medium
    Just "strong" => Got Strong
    Just other    => Errs [ctx ++ ": unknown security level '" ++ other ++ "'"]

||| Parse a DeviceKind from a JSON string.
export
extractDeviceKind : String -> JsonValue -> Extracted DeviceKind
extractDeviceKind ctx json =
  case asString json of
    Nothing => Errs [ctx ++ ": expected string for device kind"]
    Just "laptop"       => Got Laptop
    Just "desktop"      => Got Desktop
    Just "server"       => Got Server
    Just "router"       => Got Router
    Just "switch"       => Got Switch
    Just "firewall"     => Got Firewall
    Just "camera"       => Got Camera
    Just "access_point" => Got AccessPoint
    Just "patch_panel"  => Got PatchPanel
    Just "power_supply" => Got PowerSupply
    Just "phone_system" => Got PhoneSystem
    Just "fibre_hub"    => Got FibreHub
    Just other          => Errs [ctx ++ ": unknown device kind '" ++ other ++ "'"]

||| Parse a GuardRank from a JSON string.
export
extractGuardRank : String -> JsonValue -> Extracted GuardRank
extractGuardRank ctx json =
  case asString json of
    Nothing => Errs [ctx ++ ": expected string for guard rank"]
    Just "basic"          => Got BasicGuard
    Just "enforcer"       => Got Enforcer
    Just "anti_hacker"    => Got AntiHacker
    Just "sentinel"       => Got Sentinel
    Just "assassin"       => Got Assassin
    Just "elite"          => Got EliteGuard
    Just "security_chief" => Got SecurityChief
    Just "rival_hacker"   => Got RivalHacker
    Just other            => Errs [ctx ++ ": unknown guard rank '" ++ other ++ "'"]

------------------------------------------------------------------------
-- Record extraction
------------------------------------------------------------------------

||| Extract a DeviceSpec from a JSON object.
export
extractDevice : String -> JsonValue -> Extracted DeviceSpec
extractDevice ctx json =
  case ( extractDeviceKind (ctx ++ ".kind") =<< maybeToExtracted (ctx ++ ".kind") (get "kind" json)
       , extractIpAddress (ctx ++ ".ip") =<< maybeToExtracted (ctx ++ ".ip") (get "ip" json)
       , requireField ctx "name" asString json
       , extractSecurityLevel (ctx ++ ".security") =<< maybeToExtracted (ctx ++ ".security") (get "security" json)
       ) of
    (Got k, Got i, Got n, Got s) => Got (MkDeviceSpec k i n s)
    -- errsOf per field (not a List fold): the four results have
    -- different element types, so a List (Extracted a) cannot hold them.
    (e1, e2, e3, e4)             => Errs (errsOf e1 ++ errsOf e2 ++ errsOf e3 ++ errsOf e4)
  where
    ||| Bind-like operation for Extracted. Applies f to the inner value,
    ||| or propagates errors.
    (=<<) : (a -> Extracted b) -> Extracted a -> Extracted b
    (=<<) f (Got x)   = f x
    (=<<) _ (Errs es) = Errs es

    ||| Lift a Maybe into Extracted, using the given context for error messages.
    maybeToExtracted : String -> Maybe a -> Extracted a
    maybeToExtracted _   (Just x) = Got x
    maybeToExtracted msg Nothing  = Errs [msg ++ ": field missing"]

||| Extract a Zone from a JSON object.
export
extractZone : String -> JsonValue -> Extracted Zone
extractZone ctx json =
  case (requireField ctx "name" asString json,
        requireField ctx "security_tier" asNat json) of
    (Got n, Got t)     => Got (MkZone n t)
    (Errs e1, Errs e2) => Errs (e1 ++ e2)
    (Errs e1, _)       => Errs e1
    (_, Errs e2)       => Errs e2

||| Extract a GuardPlacement from a JSON object.
export
extractGuard : String -> JsonValue -> Extracted GuardPlacement
extractGuard ctx json =
  case ( requireField ctx "world_x" asNumber json
       , requireField ctx "zone" asString json
       , extractGuardRank ctx =<< maybeToExtracted (ctx ++ ".rank") (get "rank" json)
       , requireField ctx "patrol_radius" asNumber json
       ) of
    (Got wx, Got z, Got r, Got pr) => Got (MkGuardPlacement (MkWorldX wx) z r pr)
    (e1, e2, e3, e4)               => Errs (errsOf e1 ++ errsOf e2 ++ errsOf e3 ++ errsOf e4)
  where
    (=<<) : (a -> Extracted b) -> Extracted a -> Extracted b
    (=<<) f (Got x)   = f x
    (=<<) _ (Errs es) = Errs es

    maybeToExtracted : String -> Maybe a -> Extracted a
    maybeToExtracted _   (Just x) = Got x
    maybeToExtracted msg Nothing  = Errs [msg ++ ": field missing"]

||| Extract a ZoneTransition from a JSON object.
export
extractZoneTransition : String -> JsonValue -> Extracted ZoneTransition
extractZoneTransition ctx json =
  case ( requireField ctx "world_x" asNumber json
       , requireField ctx "from_zone" asString json
       , requireField ctx "to_zone" asString json
       ) of
    (Got wx, Got fz, Got tz) => Got (MkZoneTransition (MkWorldX wx) fz tz)
    (e1, e2, e3)             => Errs (errsOf e1 ++ errsOf e2 ++ errsOf e3)

------------------------------------------------------------------------
-- List extraction helper
------------------------------------------------------------------------

||| Extract a list of items from a JSON array, accumulating all errors.
||| Each element is labelled with its index for error context.
export
extractList : String -> (String -> JsonValue -> Extracted a) -> JsonValue -> Extracted (List a)
extractList ctx extractor json =
  case asArray json of
    Nothing => Errs [ctx ++ ": expected JSON array"]
    Just xs => go xs 0 [] []
  where
    go : List JsonValue -> Nat -> List a -> ExtractionErrors -> Extracted (List a)
    go [] _ acc [] = Got (reverse acc)
    go [] _ _   errs = Errs (reverse errs)
    go (x :: xs) idx acc errs =
      let elemCtx = ctx ++ "[" ++ show idx ++ "]"
      in case extractor elemCtx x of
           Got val  => go xs (S idx) (val :: acc) errs
           Errs es  => go xs (S idx) acc (es ++ errs)

------------------------------------------------------------------------
-- Mission / Physical extraction
------------------------------------------------------------------------

||| Extract a single MissionObjective from a JSON object.
||| Schema: { "id": string, "description": string, "required": bool }
export
extractObjective : String -> JsonValue -> Extracted MissionObjective
extractObjective ctx json =
  case ( requireField ctx "id" asString json
       , requireField ctx "description" asString json
       , requireField ctx "required" asBool json
       ) of
    (Got oid, Got desc, Got req) => Got (MkMissionObjective oid desc req)
    (e1, e2, e3) => Errs (errsOf e1 ++ errsOf e2 ++ errsOf e3)

||| Extract a MissionConfig from a JSON object.
||| Schema: { "mission_id": string, "location_id": string,
|||           "objectives": [MissionObjective...],   -- optional, defaults []
|||           "time_limit": nat }                    -- optional
export
extractMission : String -> JsonValue -> Extracted MissionConfig
extractMission ctx json =
  case ( requireField ctx "mission_id" asString json
       , requireField ctx "location_id" asString json
       , objectivesR
       , optionalField ctx "time_limit" asNat json
       ) of
    (Got mid, Got lid, Got objs, Got tl) => Got (MkMissionConfig mid lid objs tl)
    (e1, e2, e3, e4) => Errs (errsOf e1 ++ errsOf e2 ++ errsOf e3 ++ errsOf e4)
  where
    objectivesR : Extracted (List MissionObjective)
    objectivesR =
      case get "objectives" json of
        Nothing => Got []
        Just v  => extractList (ctx ++ ".objectives") extractObjective v

||| Extract a PhysicalConfig from a JSON object.
||| Schema: { "ground_y": number, "world_width": number,
|||           "interaction_distance": number, "has_power_system": bool,
|||           "has_security_cameras": bool, "covert_links": nat }
export
extractPhysical : String -> JsonValue -> Extracted PhysicalConfig
extractPhysical ctx json =
  case ( requireField ctx "ground_y" asNumber json
       , requireField ctx "world_width" asNumber json
       , requireField ctx "interaction_distance" asNumber json
       , requireField ctx "has_power_system" asBool json
       , requireField ctx "has_security_cameras" asBool json
       , requireField ctx "covert_links" asNat json
       ) of
    (Got gy, Got ww, Got idist, Got pow, Got cam, Got links) =>
      Got (MkPhysicalConfig gy ww idist pow cam links)
    (e1, e2, e3, e4, e5, e6) =>
      Errs (errsOf e1 ++ errsOf e2 ++ errsOf e3 ++ errsOf e4 ++ errsOf e5 ++ errsOf e6)

||| Default mission when the level JSON has no "mission" object.
||| Mirrors the [] defaults of the sibling list fields: an absent
||| optional section yields an empty-but-valid config, not an error.
export
defaultMissionConfig : MissionConfig
defaultMissionConfig = MkMissionConfig "" "" [] Nothing

||| Default physical config when the level JSON has no "physical" object.
export
defaultPhysicalConfig : PhysicalConfig
defaultPhysicalConfig = MkPhysicalConfig 0.0 0.0 0.0 False False 0

------------------------------------------------------------------------
-- Top-level: parseLevelJson
------------------------------------------------------------------------

||| Parse a raw JSON string into a LevelData record.
|||
||| This function is total: malformed JSON or missing/wrong-typed fields
||| produce a Left with human-readable error descriptions. It never crashes.
|||
||| Expected JSON schema (top-level object):
|||   { "devices": [...], "zones": [...], "guards": [...],
|||     "zone_transitions": [...], "has_pbx": bool, "pbx_ip": "a.b.c.d",
|||     "pbx_world_x": number, "mission": {...}, "physical": {...},
|||     ... }
|||
||| Fields not yet extracted (dogs, drones, assassins, items, wiring,
||| device_defences) return empty defaults. These will be filled in as
||| their respective extractors are implemented. `mission` and `physical`
||| are extracted for real; when the section is absent the default
||| config records are used (mirroring the [] defaults of list fields).
export
parseLevelJson : String -> Either String LevelData
parseLevelJson input =
  case parse input of
    Left err   => Left ("JSON parse failure: " ++ show err)
    Right json => extractedToEither (extractLevelData json)
  where
    ||| Build a LevelData from the top-level JSON object.
    ||| Accumulates errors across all fields so the caller gets a complete
    ||| report rather than stopping at the first problem.
    extractLevelData : JsonValue -> Extracted LevelData
    extractLevelData json =
      let devicesR = case get "devices" json of
                       Nothing => Got []
                       Just v  => extractList "devices" extractDevice v
          zonesR   = case get "zones" json of
                       Nothing => Got []
                       Just v  => extractList "zones" extractZone v
          guardsR  = case get "guards" json of
                       Nothing => Got []
                       Just v  => extractList "guards" extractGuard v
          ztR      = case get "zone_transitions" json of
                       Nothing => Got []
                       Just v  => extractList "zone_transitions" extractZoneTransition v
          hasPbxR  = case get "has_pbx" json of
                       Nothing => Got False
                       Just v  => case asBool v of
                                    Just b  => Got b
                                    Nothing => Errs ["has_pbx: expected boolean"]
          pbxIpR   = case get "pbx_ip" json of
                       Nothing => Got (MkIpAddress 0 0 0 0)
                       Just v  => extractIpAddress "pbx_ip" v
          pbxWxR   = case get "pbx_world_x" json of
                       Nothing => Got (MkWorldX 0.0)
                       Just v  => case asNumber v of
                                    Just n  => Got (MkWorldX n)
                                    Nothing => Errs ["pbx_world_x: expected number"]
          missionR = case get "mission" json of
                       Nothing => Got defaultMissionConfig
                       Just v  => extractMission "mission" v
          physicalR = case get "physical" json of
                        Nothing => Got defaultPhysicalConfig
                        Just v  => extractPhysical "physical" v
      -- Applicative chain (not a 9-tuple case): the error-accumulating
      -- Applicative Extracted collects errors from every failed field
      -- while staying within the elaborator's comfort zone for nested
      -- pairs.
      in mk <$> devicesR <*> zonesR <*> guardsR <*> ztR <*> hasPbxR
            <*> pbxIpR <*> pbxWxR <*> missionR <*> physicalR
      where
        ||| Assemble a LevelData from the successfully extracted fields.
        ||| The remaining list fields are stubbed to [] pending their
        ||| extractors (documented forward work).
        mk : List DeviceSpec -> List Zone -> List GuardPlacement
           -> List ZoneTransition -> Bool -> IpAddress -> WorldX
           -> MissionConfig -> PhysicalConfig -> LevelData
        mk devs zs gs zt hp pip pwx mis phy =
          MkLevelData
            devs          -- devices
            zs            -- zones
            gs            -- guards
            []            -- dogs (TODO: implement extractDog)
            []            -- drones (TODO: implement extractDrone)
            []            -- assassins (TODO: implement extractAssassin)
            []            -- items (TODO: implement extractItem)
            []            -- wiring (TODO: implement extractWiring)
            mis           -- mission
            phy           -- physical
            zt            -- zoneTransitions
            []            -- deviceDefences (TODO: implement extractDefence)
            hp            -- hasPBX
            pip           -- pbxIp
            pwx           -- pbxWorldX

------------------------------------------------------------------------
-- validateAndReport: human-readable validation diagnostics
------------------------------------------------------------------------

||| Run cross-domain validation checks on a LevelData and collect all
||| failures as human-readable strings.
|||
||| Performs the decidable (Bool-returning) subset of the checks that
||| Validation.idr encodes as proofs. It cannot construct the proof
||| witnesses (those require compile-time evidence) but it can report
||| whether the data WOULD pass validation.
|||
||| Checks performed:
|||   1. Every guard references a zone that exists in the zone list.
|||   2. Zone transitions are monotonically increasing in world X.
|||   3. PBX IP (when enabled) exists in the device registry.
|||   4. No duplicate device IPs.
|||   5. No duplicate zone names.
export
validateAndReport : LevelData -> List String
validateAndReport level =
     checkGuardZones (guards level) (zones level)
  ++ checkZoneOrder (zoneTransitions level)
  ++ checkPBX (hasPBX level) (pbxIp level) (devices level)
  ++ checkDuplicateIPs (devices level)
  ++ checkDuplicateZoneNames (zones level)
  where
    ||| Check that every guard's zone field names an existing zone.
    checkGuardZones : List GuardPlacement -> List Zone -> List String
    checkGuardZones [] _ = []
    checkGuardZones (g :: gs) zs =
      let zoneNames = map name zs
          errors = if zone g `elem` zoneNames
                     then []
                     else ["Guard at x=" ++ show (position (worldX g))
                           ++ " references unknown zone '" ++ zone g ++ "'"]
      in errors ++ checkGuardZones gs zs

    ||| Check that zone transitions are monotonically non-decreasing in X.
    checkZoneOrder : List ZoneTransition -> List String
    checkZoneOrder [] = []
    checkZoneOrder [_] = []
    checkZoneOrder (t1 :: t2 :: ts) =
      let errors = if position (worldX t1) <= position (worldX t2)
                     then []
                     else ["Zone transition at x=" ++ show (position (worldX t1))
                           ++ " is not <= next transition at x="
                           ++ show (position (worldX t2))]
      in errors ++ checkZoneOrder (t2 :: ts)

    ||| When PBX is enabled, its IP must exist among devices.
    checkPBX : Bool -> IpAddress -> List DeviceSpec -> List String
    checkPBX False _ _ = []
    checkPBX True addr devs =
      let deviceIPs = map ip devs
      in if addr `elem` deviceIPs
           then []
           else ["PBX is enabled but pbx_ip does not match any device IP"]

    ||| Check for duplicate device IPs.
    checkDuplicateIPs : List DeviceSpec -> List String
    checkDuplicateIPs devs =
      let ips = map ip devs
      in findDups ips []
      where
        findDups : List IpAddress -> List IpAddress -> List String
        findDups [] _ = []
        findDups (x :: xs) seen =
          if x `elem` seen
            then ("Duplicate device IP found") :: findDups xs seen
            else findDups xs (x :: seen)

    ||| Check for duplicate zone names.
    checkDuplicateZoneNames : List Zone -> List String
    checkDuplicateZoneNames zs =
      let names = map name zs
      in findDupNames names []
      where
        findDupNames : List String -> List String -> List String
        findDupNames [] _ = []
        findDupNames (x :: xs) seen =
          if x `elem` seen
            then ("Duplicate zone name '" ++ x ++ "'") :: findDupNames xs seen
            else findDupNames xs (x :: seen)

------------------------------------------------------------------------
-- Game-specific arithmetic (built on Proven.SafeMath)
------------------------------------------------------------------------

||| Clamp HP to [0, maxHP]. Specialisation of Proven.SafeMath.clamp.
export
clampHP : (maxHP : Integer) -> (rawHP : Integer) -> Integer
clampHP maxHP rawHP = clamp 0 maxHP rawHP

||| Clamp alert level to [0, 5]. IDApTIK uses 6 alert tiers:
||| 0 (undetected) through 5 (lockdown).
export
clampAlertLevel : Integer -> Integer
clampAlertLevel raw = clamp 0 5 raw

||| Apply damage to current HP, clamping to [0, maxHP].
||| Total: cannot crash, always returns a valid HP value.
||| Underflow (massive damage) floors HP to 0.
export
applyDamage : (maxHP : Integer) -> (currentHP : Integer) -> (damage : Integer) -> Integer
applyDamage maxHP currentHP damage =
  case subChecked currentHP damage of
    Just newHP => clampHP maxHP newHP
    Nothing    => 0

||| Critical hit damage with overflow protection.
||| Multiplies base damage by a multiplier, clamping to maxDamage cap.
||| Overflow (huge multiplier) caps to maxDamage.
export
critDamage : (baseDamage : Integer) -> (multiplier : Integer) -> (maxDamage : Integer) -> Integer
critDamage baseDamage multiplier maxDamage =
  case mulChecked baseDamage multiplier of
    Just product => clamp 0 maxDamage product
    Nothing      => maxDamage

||| Check if an alert threshold has been reached.
||| Returns True when current detection meets or exceeds
||| `thresholdPercent` of maxDetection. On overflow, conservatively
||| reports threshold as reached (worst-case for the player).
export
alertThresholdReached : (thresholdPercent : Integer)
                      -> (currentDetection : Integer)
                      -> (maxDetection : Integer) -> Bool
alertThresholdReached thresholdPercent currentDetection maxDetection =
  case percentOf thresholdPercent maxDetection of
    Just threshold => currentDetection >= threshold
    Nothing        => True

------------------------------------------------------------------------
-- Game-specific string operations (built on Proven.SafeString)
------------------------------------------------------------------------

||| Validate a level name: must be non-empty, ASCII-only, within length limit.
export
validateLevelName : (maxLen : Nat) -> (name : String) -> Either String String
validateLevelName maxLen rawName =
  let trimmed = trim rawName
  in if length trimmed == 0
       then Left "Level name must not be empty"
       else if not (isAscii trimmed)
         then Left "Level name must contain only ASCII characters"
         else if length trimmed > maxLen
           then Left ("Level name exceeds maximum length of " ++ show maxLen)
           else Right trimmed

||| Format a device name for display in the network map panel.
||| Truncates to panel width with ellipsis, then right-pads with spaces.
export
formatDeviceLabel : (panelWidth : Nat) -> (deviceName : String) -> String
formatDeviceLabel panelWidth deviceName =
  let truncated = truncateWithEllipsis panelWidth deviceName
  in padRight panelWidth ' ' truncated

||| Sanitise player-typed terminal command: trim, truncate, and reject
||| non-ASCII to prevent injection of control characters.
export
sanitiseTerminalInput : (maxLen : Nat) -> (raw : String) -> Either String String
sanitiseTerminalInput maxLen raw =
  let trimmed = trim raw
  in if length trimmed == 0
       then Left "Empty command"
       else if not (isAscii trimmed)
         then Left "Non-ASCII characters not permitted in terminal"
         else Right (truncate maxLen trimmed)

------------------------------------------------------------------------
-- Game-specific crypto (built on Proven.SafeCrypto)
------------------------------------------------------------------------

||| Verify a multiplayer auth token using constant-time comparison.
||| Compares a received hex-encoded token against expected token bytes.
||| Returns False (not an error) on invalid hex.
export
verifyAuthToken : (expectedBytes : Bytes) -> (receivedHex : String) -> Bool
verifyAuthToken expectedBytes receivedHex =
  case hexToBytes receivedHex of
    Nothing            => False
    Just receivedBytes => constantTimeEq expectedBytes receivedBytes

-- gameSyncTag (previously a stub returning []) was dropped here:
-- callers should use Proven.SafeCrypto.hmac directly once it has a
-- real FFI backing. Re-introduce a wrapper if a stable idaptik-named
-- entry point is needed.

------------------------------------------------------------------------
-- Game-specific input (built on Proven.SafeInput)
------------------------------------------------------------------------

||| Terminal hacking input buffer: printable ASCII, 80 chars max.
export
terminalHackBuffer : InputBuffer
terminalHackBuffer = filteredBuffer 80 Printable

||| Numeric entry buffer: 5 digits max (enough for ports 0-65535).
export
numericEntryBuffer : InputBuffer
numericEntryBuffer = filteredBuffer 5 Numeric

||| Hex entry buffer: 64 hex chars max (256-bit hash).
export
hexEntryBuffer : InputBuffer
hexEntryBuffer = filteredBuffer 64 HexDigit

||| Process a keystroke and validate the resulting buffer as an integer.
export
handleAndValidateInt : Keystroke -> InputBuffer -> (InputBuffer, InputResult Integer)
handleAndValidateInt key buf =
  let newBuf = handleKey key buf
  in (newBuf, validateInt (getContent newBuf))

||| Process a keystroke and validate as a Nat.
export
handleAndValidateNat : Keystroke -> InputBuffer -> (InputBuffer, InputResult Nat)
handleAndValidateNat key buf =
  let newBuf = handleKey key buf
  in (newBuf, validateNat (getContent newBuf))
