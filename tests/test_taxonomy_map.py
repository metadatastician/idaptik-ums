# SPDX-License-Identifier: MPL-2.0
"""Lockstep tests for the UMS <-> game taxonomy map (schemas/taxonomy-map.json).

The map is the versioned contract at the DLC manifest seam (docs/adr/0002):
scripts/validate_dlc.py derives its device and segment vocabularies from it.
These tests pin the map to the other copies of the same closed worlds —
ai_edit/vocab.py and the JSON schemas — so drift in any one of them fails
here rather than at load time in the game.

Run from the repository root with:
    python3 -m unittest discover -s tests
"""

from __future__ import annotations

import importlib.util
import json
import unittest
from pathlib import Path

from ai_edit import vocab

ROOT = Path(__file__).resolve().parent.parent
MAP_PATH = ROOT / "schemas" / "taxonomy-map.json"
EDIT_SCHEMA_PATH = ROOT / "schemas" / "edit-script.schema.json"

_spec = importlib.util.spec_from_file_location(
    "validate_dlc", ROOT / "scripts" / "validate_dlc.py"
)
validate_dlc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(validate_dlc)


def _load(path):
    return json.loads(path.read_text(encoding="utf-8"))


class TaxonomyMapTests(unittest.TestCase):
    def setUp(self):
        self.map = _load(MAP_PATH)
        self.schema = _load(EDIT_SCHEMA_PATH)

    def test_map_is_internally_coherent(self):
        self.assertEqual(validate_dlc.check_taxonomy_map(self.map), [])

    def test_device_kinds_cover_the_ums_vocabulary_exactly(self):
        self.assertEqual(
            set(self.map["device-kinds"]),
            set(vocab.DEVICE_KINDS),
            "taxonomy-map device-kinds must match ai_edit/vocab.py DEVICE_KINDS",
        )

    def test_device_mapping_is_lossless_one_to_one(self):
        values = list(self.map["device-kinds"].values())
        self.assertEqual(len(values), len(set(values)), "no two UMS kinds may collapse")
        self.assertTrue(
            set(values) <= set(self.map["game-device-kinds"]),
            "every mapped game kind must exist in the game enum",
        )

    def test_extend_the_enum_ruling_is_reflected_in_the_game_enum(self):
        # The 7 kinds the game PR (IDApTIK feat/devicekind-ums-parity) appends.
        added = {
            "PatchPanel", "FibreHub", "PhoneSystem", "AccessPoint",
            "Switch", "Desktop", "PowerSupply",
        }
        self.assertTrue(added <= set(self.map["game-device-kinds"]))

    def test_edit_schema_device_enum_matches_the_map(self):
        schema_kinds = set(
            self.schema["$defs"]["add_device"]["properties"]["kind"]["enum"]
        )
        self.assertEqual(schema_kinds, set(self.map["device-kinds"]))

    def test_edit_schema_segment_enum_matches_the_map(self):
        schema_segments = set(
            self.schema["$defs"]["add_zone"]["properties"]["segment"]["enum"]
        )
        self.assertEqual(schema_segments, set(self.map["zone-segments"]))

    def test_validator_vocabularies_are_derived_from_the_map(self):
        self.assertEqual(validate_dlc.DEVICE_KINDS, set(self.map["device-kinds"]))
        self.assertEqual(validate_dlc.GAME_SEGMENTS, set(self.map["zone-segments"]))

    def test_default_bands_resolve_every_tier(self):
        # DEFAULT PENDING HUMAN RULING (zone-defaults-status): the banding must
        # still be total — the highest min-tier <= tier must exist for any Nat.
        bands = self.map["zone-tier-bands"]
        self.assertEqual(bands[0]["min-tier"], 0)
        tiers = [band["min-tier"] for band in bands]
        self.assertEqual(tiers, sorted(set(tiers)), "bands strictly increasing")
        for band in bands:
            self.assertIn(band["segment"], self.map["zone-segments"])
        self.assertEqual(self.map["zone-defaults-status"], "default-pending-human-ruling")


class SegmentOverrideValidationTests(unittest.TestCase):
    def _errors(self, zone_extra):
        doc = {
            "target": "sample",
            "edits": [
                {
                    "verb": "add_zone",
                    "id": "lobby",
                    "securityTier": 0,
                    "worldXStart": 0,
                    "worldXEnd": 10,
                    **zone_extra,
                }
            ],
        }
        errors = []
        validate_dlc.check_edit_script(doc, errors)
        return errors

    def test_add_zone_without_override_is_valid(self):
        self.assertEqual(self._errors({}), [])

    def test_add_zone_with_valid_override_is_valid(self):
        self.assertEqual(self._errors({"segment": "Iot"}), [])

    def test_add_zone_with_unknown_segment_is_rejected(self):
        errors = self._errors({"segment": "Backstage"})
        self.assertEqual(len(errors), 1)
        self.assertIn("segment", errors[0])

    def test_add_zone_with_unknown_field_is_still_rejected(self):
        errors = self._errors({"segmnet": "Lan"})
        self.assertEqual(len(errors), 1)
        self.assertIn("optional", errors[0])


if __name__ == "__main__":
    unittest.main()
