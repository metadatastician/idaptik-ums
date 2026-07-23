# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# edit-script-schema.ncl — generates schemas/edit-script.schema.json.
#
# The JSON Schema is a VIEW of config/verbs.ncl, not a hand-maintained
# artifact. Every `$defs` entry, every `enum` array and every `required` list
# below is derived from the verb registry, so adding a DeviceKind or a verb
# argument cannot leave the wire contract behind.
#
# Regenerate with `just gen`; `just gen-check` fails if the committed file has
# drifted from this source.

let vocab = import "./vocab.ncl" in
let registry = import "./verbs.ncl" in

let entity_id_ref = { "$ref" = "#/$defs/entityId" } in

# An argument's JSON Schema fragment. `id` and `zone` are entity references;
# an argument with a domain becomes a closed `enum`; everything else is a
# plain JSON type.
let arg_schema = fun arg =>
  if arg.name == "id" || arg.name == "zone" then
    entity_id_ref
  else if std.record.has_field "domain" arg then
    { enum = std.record.get arg.domain vocab }
  else
    let ty = std.string.from_enum arg.type in
    if ty == "integer" then
      { type = "integer", minimum = 0 }
    else
      { type = ty }
in

let verb_def = fun v =>
  let required_args =
    std.array.filter
      (fun a => !std.record.has_field "required" a || a.required)
      v.args
  in
  {
    type = "object",
    description = v.doc,
    required = ["verb"] @ std.array.map (fun a => a.name) required_args,
    additionalProperties = false,
    properties =
      { verb = { "const" = v.name } }
      & std.array.fold_left
          (fun acc a => acc & { "%{a.name}" = arg_schema a })
          {}
          v.args,
  }
in

{
  "$schema" = "https://json-schema.org/draft/2020-12/schema",
  "$id" = "https://github.com/metadatastician/idaptik-ums/blob/main/schemas/edit-script.schema.json",
  title = "IDApTIK edit script (idaptik-edit/1)",
  description = m%"
    Payload for kind: edit-script DLC artifacts. An ordered list of edit verbs
    over a scenario's level object graph, produced by the UMS AI-edit engine.
    Edits are data: replayable, auditable, and constraint-checked — the engine
    only emits a script when every intermediate state satisfies the validity
    proofs (guards-in-zones, defence-targets, zones-ordered, pbx-consistent,
    devices-exist, items-in-zones). UMS owns this payload format as the editor
    authority. GENERATED from config/edit-script-schema.ncl — do not edit by
    hand; run `just gen`. Architecture: docs/adr/0001-ai-edit-kautz6-nesy.adoc.
  "%,
  type = "object",
  required = ["target", "edits"],
  additionalProperties = false,
  properties = {
    "$schema" = { type = "string" },
    "format-note" = {
      type = "string",
      description = "Human-readable reminder of the wire format, e.g. 'idaptik-edit/1'.",
    },
    target = {
      type = "string",
      pattern = "^[a-z0-9][a-z0-9-]*$",
      description = "Id of the scenario the script edits (a scenario-definition artifact id, or a new scenario id when the script builds a level from empty).",
    },
    edits = {
      type = "array",
      minItems = 1,
      items = {
        oneOf =
          std.array.map
            (fun v => { "$ref" = "#/$defs/%{v.name}" })
            registry.verbs,
      },
      description = "Verbs applied in order. Zones referenced by later verbs must be declared earlier in the script or already exist on the target scenario.",
    },
  },
  "$defs" =
    {
      entityId = {
        type = "string",
        pattern = "^[a-z0-9][a-z0-9-]*$",
        description = "Lowercase-kebab identifier, unique within its collection.",
      },
    }
    & std.array.fold_left
        (fun acc v => acc & { "%{v.name}" = verb_def v })
        {}
        registry.verbs,
}
