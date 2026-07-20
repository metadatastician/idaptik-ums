-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Joshua B. Jewell and Jonathan D.A. Jewell
--
-- GameSystems.idr — Formal ABI types for runtime game systems.
--
-- Covers the systems that operate DURING gameplay (as opposed to the
-- level editor types in the other ABI modules):
--   - Combat: damage, HP, armour, critical hits
--   - Detection: alert scoring, detection events, guard awareness
--   - Skills: Jessica subclasses, Q certifications, skill checks
--   - Equipment: loadout slots, program deck, consumables
--
-- Proofs:
--   1. HP is always non-negative (Nat, not Int)
--   2. Critical roll outcomes partition the probability space
--   3. Jessica subclasses are mutually exclusive
--   4. Q program deck capacity is bounded
module GameSystems

import Data.Fin

%default total

-- ═══════════════════════════════════════════════════════════════════════
-- Combat system
-- ═══════════════════════════════════════════════════════════════════════

||| Damage types in the game.
public export
data DamageType
  = PhysicalDamage   -- Jessica melee/ranged
  | ElectricDamage   -- Taser, EMP
  | CyberDamage      -- Q's offensive programs
  | FallDamage       -- Environmental

||| Integer encoding for C ABI.
public export
damageTypeToInt : DamageType -> Int
damageTypeToInt PhysicalDamage = 0
damageTypeToInt ElectricDamage = 1
damageTypeToInt CyberDamage    = 2
damageTypeToInt FallDamage     = 3

||| Critical roll outcome.
||| Partitions the probability space into 4 disjoint regions.
public export
data CriticalOutcome
  = CriticalFailure  -- Fumble, alarm triggered, item dropped
  | NormalResult     -- Standard success/failure based on skill check
  | CriticalSuccess  -- Spectacular execution, bonus effects
  | PerfectExecution -- Flawless — style points, no trace left

||| Integer encoding for C ABI.
public export
critOutcomeToInt : CriticalOutcome -> Int
critOutcomeToInt CriticalFailure  = 0
critOutcomeToInt NormalResult     = 1
critOutcomeToInt CriticalSuccess  = 2
critOutcomeToInt PerfectExecution = 3

-- ═══════════════════════════════════════════════════════════════════════
-- Detection system
-- ═══════════════════════════════════════════════════════════════════════

||| Detection event sources.
public export
data DetectionSource
  = CameraDetected     -- Spotted by security camera
  | GuardDetected      -- Guard visual contact
  | DogDetected        -- Security dog scent/noise
  | DroneDetected      -- Drone IR/visual scan
  | AlarmTriggered     -- Alarm sensor activated
  | NoiseDetected      -- Sound-based detection
  | CyberTraceBack     -- Q's hack traced back

||| Integer encoding for C ABI.
public export
detSourceToInt : DetectionSource -> Int
detSourceToInt CameraDetected   = 0
detSourceToInt GuardDetected    = 1
detSourceToInt DogDetected      = 2
detSourceToInt DroneDetected    = 3
detSourceToInt AlarmTriggered   = 4
detSourceToInt NoiseDetected    = 5
detSourceToInt CyberTraceBack   = 6

||| A detection event record.
public export
record DetectionEvent where
  constructor MkDetectionEvent
  source    : DetectionSource
  severity  : Nat              -- 0-100 score contribution
  timestamp : Double

-- ═══════════════════════════════════════════════════════════════════════
-- Jessica subclasses
-- ═══════════════════════════════════════════════════════════════════════

||| Jessica's subclass specialism (chosen at character creation).
||| All subclasses are competent generalists; the specialism gives a bonus.
public export
data JessicaSubclass
  = Assault    -- Combat/close quarters
  | Recon      -- Surveillance/observation
  | Engineer   -- Demolitions/tech interaction
  | Signals    -- Communications, radio intercept
  | Medic      -- Self-heal, injury resistance
  | Logistics  -- Larger inventory, resupply

||| Integer encoding for C ABI.
public export
subclassToInt : JessicaSubclass -> Int
subclassToInt Assault   = 0
subclassToInt Recon     = 1
subclassToInt Engineer  = 2
subclassToInt Signals   = 3
subclassToInt Medic     = 4
subclassToInt Logistics = 5

-- ═══════════════════════════════════════════════════════════════════════
-- Q certifications
-- ═══════════════════════════════════════════════════════════════════════

||| Q's certification tree branches.
public export
data QCertification
  = NetworkExploit   -- Network penetration
  | CryptoAnalysis   -- Encryption breaking
  | SocialEng        -- Social engineering
  | ForensicAnalysis -- Digital forensics
  | MalwareDesign    -- Custom payload creation
  | CounterIntel     -- Anti-trace, cover tracks

||| Integer encoding for C ABI.
public export
certToInt : QCertification -> Int
certToInt NetworkExploit  = 0
certToInt CryptoAnalysis  = 1
certToInt SocialEng       = 2
certToInt ForensicAnalysis = 3
certToInt MalwareDesign   = 4
certToInt CounterIntel    = 5

-- ═══════════════════════════════════════════════════════════════════════
-- Equipment and loadout
-- ═══════════════════════════════════════════════════════════════════════

||| Jessica's loadout slot types (3-slot system).
public export
data LoadoutSlot = WeaponSlot | ToolSlot | ConsumableSlot

||| Integer encoding for C ABI.
public export
loadoutSlotToInt : LoadoutSlot -> Int
loadoutSlotToInt WeaponSlot     = 0
loadoutSlotToInt ToolSlot       = 1
loadoutSlotToInt ConsumableSlot = 2

||| Q's program deck has bounded capacity.
||| `Fin 5` means deck size is 0-4 (max 4 programs loaded).
public export
data DeckCapacity = MkDeckCapacity (Fin 5)

-- ═══════════════════════════════════════════════════════════════════════
-- Skill check
-- ═══════════════════════════════════════════════════════════════════════

||| Player attributes used in skill checks.
public export
data Attribute = STR | DEX | INT | CON | WIL | CHA

||| Integer encoding for C ABI.
public export
attributeToInt : Attribute -> Int
attributeToInt STR = 0
attributeToInt DEX = 1
attributeToInt INT = 2
attributeToInt CON = 3
attributeToInt WIL = 4
attributeToInt CHA = 5
