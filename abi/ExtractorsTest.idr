-- SPDX-License-Identifier: AGPL-3.0-or-later
-- SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
--
-- ExtractorsTest.idr — executable test for the ProvenBridge JSON
-- extractors. Typechecking with %default total proves the extractors
-- cannot crash or loop; this main proves they compute the RIGHT
-- values, by parsing a fixture that exercises every LevelData section
-- and asserting on the decoded records, plus negative fixtures whose
-- errors must carry the expected context labels.
--
-- Lives in abi/ (not tests/) because extractors-test.ipkg reuses the
-- ABI sourcedir so the test can import the modules directly instead of
-- requiring an installed idaptikums package.
--
-- Run: idris2 --build extractors-test.ipkg && ./build/exec/extractors-test
module ExtractorsTest

import ProvenBridge
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

import Data.Fin
import Data.List
import Data.String
import System

||| A level document exercising every extracted section, in the
||| snake_case wire format shared with ffi/zig/src/types.zig.
fixture : String
fixture = """
{
  "devices": [
    { "kind": "server", "ip": "10.1.2.3", "name": "core-db", "security": "strong" }
  ],
  "zones": [ { "name": "dmz", "security_tier": 1 } ],
  "guards": [
    { "world_x": 12.5, "zone": "dmz", "rank": "enforcer", "patrol_radius": 30.0 }
  ],
  "dogs": [
    { "world_x": 40.0, "breed": "robo_dog", "patrol_radius": 15.0 }
  ],
  "drones": [
    { "world_x": 60.0, "archetype": "killer", "altitude": 120.0 },
    { "world_x": 10.0, "archetype": "helper", "altitude": 35.5 }
  ],
  "assassins": [
    { "spawn_x": 300.0, "ambush_count": 2, "retreat_threshold": 40 }
  ],
  "items": [
    { "item": { "id": "cbl-1",
                "kind": { "type": "cable", "sub_type": "fibre_lc" },
                "name": "LC patch lead", "weight": 1, "condition": "worn" },
      "world_x": 22.0, "container": "core-db" },
    { "item": { "id": "key-dmz",
                "kind": { "type": "keycard", "zone": "dmz" },
                "name": "DMZ keycard", "weight": 0, "condition": "pristine",
                "uses_remaining": 3 },
      "world_x": 25.0, "container": "core-db" }
  ],
  "wiring": [
    { "kind": "patch_panel", "device_ip": "10.1.2.3", "difficulty": 4 }
  ],
  "device_defences": [
    { "ip": "10.1.2.3",
      "flags": { "tamper_proof": true, "kill_switch": true,
                 "failover_target": "10.1.2.4",
                 "instruction_whitelist": ["ls", "ping"],
                 "time_bomb": 120 } },
    { "ip": "10.1.2.4" }
  ],
  "zone_transitions": [
    { "world_x": 50.0, "from_zone": "dmz", "to_zone": "internal" }
  ],
  "has_pbx": false,
  "mission": { "mission_id": "m1", "location_id": "exchange-house" },
  "physical": { "ground_y": 0.0, "world_width": 800.0,
                "interaction_distance": 2.5, "has_power_system": true,
                "has_security_cameras": true, "covert_links": 2 }
}
"""

-- ItemKind / WiringType have no Eq instances; match structurally.

isCableFibreLC : ItemKind -> Bool
isCableFibreLC (Cable FibreLC) = True
isCableFibreLC _               = False

isKeycardFor : String -> ItemKind -> Bool
isKeycardFor z (Keycard z') = z == z'
isKeycardFor _ _            = False

isPatchPanelWiring : WiringType -> Bool
isPatchPanelWiring PatchPanel = True
isPatchPanelWiring _          = False

dogChecks : List DogPlacement -> List (String, Bool)
dogChecks [d] =
  [ ("dog breed is robo_dog",   d.breed == RoboDog)
  , ("dog patrol radius",       d.patrolRadius == 15.0)
  , ("dog world_x",             d.worldX.position == 40.0)
  ]
dogChecks _ = [("exactly one dog decoded", False)]

droneChecks : List DronePlacement -> List (String, Bool)
droneChecks [d1, d2] =
  [ ("drone 1 archetype killer", d1.archetype == Killer)
  , ("drone 1 altitude",         d1.altitude == 120.0)
  , ("drone 2 archetype helper", d2.archetype == Helper)
  , ("drone 2 altitude",         d2.altitude == 35.5)
  ]
droneChecks _ = [("exactly two drones decoded", False)]

assassinChecks : List AssassinConfig -> List (String, Bool)
assassinChecks [a] =
  [ ("assassin spawn_x",           a.spawnX.position == 300.0)
  , ("assassin ambush count",      a.ambushCount == 2)
  , ("assassin retreat threshold", a.retreatThreshold == 40)
  ]
assassinChecks _ = [("exactly one assassin decoded", False)]

itemChecks : List WorldItem -> List (String, Bool)
itemChecks [w1, w2] =
  [ ("item 1 id",             w1.item.id == "cbl-1")
  , ("item 1 kind cable/lc",  isCableFibreLC w1.item.kind)
  , ("item 1 condition worn", w1.item.condition == Worn)
  , ("item 1 uses default",   w1.item.usesRemaining == Nothing)
  , ("item 1 container",      w1.container == "core-db")
  , ("item 2 kind keycard",   isKeycardFor "dmz" w2.item.kind)
  , ("item 2 condition",      w2.item.condition == Pristine)
  , ("item 2 uses remaining", w2.item.usesRemaining == Just 3)
  , ("item 2 world_x",        w2.worldX.position == 25.0)
  ]
itemChecks _ = [("exactly two items decoded", False)]

wiringChecks : List WiringChallenge -> List (String, Bool)
wiringChecks [w] =
  [ ("wiring kind patch_panel", isPatchPanelWiring w.kind)
  , ("wiring device ip",        w.deviceIp == MkIpAddress 10 1 2 3)
  , ("wiring difficulty",       w.difficulty == 4)
  ]
wiringChecks _ = [("exactly one wiring challenge decoded", False)]

defenceChecks : List DeviceDefenceConfig -> List (String, Bool)
defenceChecks [d1, d2] =
  [ ("defence 1 ip",              d1.ip == MkIpAddress 10 1 2 3)
  , ("defence 1 tamper_proof on", d1.flags.tamperProof == True)
  , ("defence 1 decoy off",       d1.flags.decoy == False)
  , ("defence 1 kill_switch on",  d1.flags.killSwitch == True)
  , ("defence 1 failover target", d1.flags.failoverTarget == Just (MkIpAddress 10 1 2 4))
  , ("defence 1 whitelist",       d1.flags.instructionWhitelist == Just ["ls", "ping"])
  , ("defence 1 time bomb",       d1.flags.timeBomb == Just 120)
  , ("defence 1 undo immunity",   d1.flags.undoImmunity == Nothing)
  , ("defence 2 flags default",   d2.flags.tamperProof == False
                                    && d2.flags.killSwitch == False
                                    && d2.flags.failoverTarget == Nothing)
  ]
defenceChecks _ = [("exactly two defences decoded", False)]

positiveChecks : LevelData -> List (String, Bool)
positiveChecks lvl =
     [ ("one device decoded", length lvl.devices == 1)
     , ("one zone decoded",   length lvl.zones == 1)
     , ("one guard decoded",  length lvl.guards == 1)
     , ("fixture passes validateAndReport", validateAndReport lvl == [])
     ]
  ++ dogChecks lvl.dogs
  ++ droneChecks lvl.drones
  ++ assassinChecks lvl.assassins
  ++ itemChecks lvl.items
  ++ wiringChecks lvl.wiring
  ++ defenceChecks lvl.deviceDefences

||| True when parsing fails AND the error mentions the needle —
||| negative fixtures must not just fail, they must fail with a
||| context label pointing at the right field.
failsMentioning : String -> String -> Bool
failsMentioning doc needle =
  case parseLevelJson doc of
    Left err => needle `isInfixOf` err
    Right _  => False

negativeChecks : List (String, Bool)
negativeChecks =
  let badBreed = """
        { "dogs": [ { "world_x": 1.0, "breed": "poodle", "patrol_radius": 2.0 } ] }
        """
      badTwoSections = """
        { "wiring": [ { "kind": "laser", "device_ip": "10.0.0.1", "difficulty": 1 } ],
          "device_defences": [ { "ip": "not-an-ip" } ] }
        """
      missingFields = """
        { "items": [ { "item": { "id": "x", "kind": { "type": "radio" },
                                 "name": "r", "weight": 1 },
                       "world_x": 0.0 } ] }
        """
  in [ ("unknown breed rejected with context",
          failsMentioning badBreed "dogs[0].breed: unknown dog breed 'poodle'")
     , ("bad wiring kind reported",
          failsMentioning badTwoSections "wiring[0].kind: unknown wiring type 'laser'")
     , ("bad defence ip reported from the same document",
          failsMentioning badTwoSections "device_defences[0].ip")
     , ("missing item condition reported",
          failsMentioning missingFields "condition")
     , ("missing container reported",
          failsMentioning missingFields "container")
     ]

report : (String, Bool) -> IO Bool
report (label, ok) = do
  putStrLn ((if ok then "  ok   " else "  FAIL ") ++ label)
  pure ok

covering
main : IO ()
main =
  case parseLevelJson fixture of
    Left err => do
      putStrLn ("FAIL: fixture did not parse:\n" ++ err)
      exitWith (ExitFailure 1)
    Right lvl => do
      putStrLn "extractor checks:"
      results <- traverse report (positiveChecks lvl ++ negativeChecks)
      -- Single let on purpose: idris2 0.7.0 fails to parse two
      -- consecutive do-lets when the do-block is a case-alternative
      -- RHS (error misreported at the alternative head).
      let passed = length (filter Prelude.id results)
      putStrLn (show passed ++ "/" ++ show (length results) ++ " checks passed")
      if passed == length results
        then putStrLn "PASS"
        else exitWith (ExitFailure 1)
