# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# connectors.ncl — the Hexadeca-Connector wire order.
#
# THIS IS THE SOURCE OF TRUTH. The Zig enum, the Rust enum and the Idris2 ABI
# module are all generated from it.
#
# The Hexadeca pattern is a sixteen-protocol unified API over one C-ABI core.
# What makes it dangerous is that the *ordinal* is the wire contract: a
# connector's tag travels across the FFI boundary as a `u8`, so if Zig, Rust
# and Idris2 disagree about which number means which protocol, every call
# silently dispatches to the wrong handler. Nothing crashes; the wrong thing
# just happens. That is the known failure mode of this pattern across the
# estate, and it is why the order lives in one file and is gated.
#
# `implemented` is deliberately honest, and today it is FALSE for all sixteen.
#
# What this layer delivers is the *wire contract*: the connector set, the
# ordinals, and cross-language agreement about them — all generated from here
# and gated by tests. What it does NOT deliver is any transport. No connector
# has a handler, and `dispatch` returns error.NotImplemented for every one of
# them rather than a success code.
#
# The reference implementation in paint-type ships sixteen stub connectors
# whose `dispatch` returns 0 and ignores the request: sixteen files that read
# as a transport layer and are not one. Decorative surface is worse than
# absent surface, because it reads as done. When a transport does land, flip
# `implemented` here — the Zig test below fails until the manifest and the
# code agree, so the flag cannot drift from reality in either direction.

let Connector = {
  name | String,
  ordinal | Number,
  # A short note on what this protocol is for in the UMS context.
  doc | String,
  # Whether a real handler exists. False means `dispatch` returns
  # `error.NotImplemented`, never a success code.
  implemented | Bool | default = false,
}
in

let connector_list | Array Connector = [
  # --- Core 12 -------------------------------------------------------------
  { ordinal = 0,  name = "grpc",           doc = "gRPC service surface." },
  { ordinal = 1,  name = "graphql",        doc = "GraphQL query surface." },
  {
    ordinal = 2,
    name = "rest",
    doc = "JSON-in/JSON-out over HTTP — the shape idaptik-ffi already speaks, and the intended first transport for the UMS<->game DLC seam.",
  },
  { ordinal = 3,  name = "flatbuffers",    doc = "FlatBuffers zero-copy payloads." },
  { ordinal = 4,  name = "bebop",          doc = "Bebop binary records." },
  {
    ordinal = 5,
    name = "jsonrpc",
    doc = "JSON-RPC 2.0 — the intended framing for an editor driving ai-edit `solve` and `check`.",
  },
  { ordinal = 6,  name = "websocket",      doc = "Duplex session transport (the game's session relay speaks this)." },
  { ordinal = 7,  name = "mqtt",           doc = "Pub/sub telemetry." },
  { ordinal = 8,  name = "trpc",           doc = "tRPC-style typed procedure calls." },
  { ordinal = 9,  name = "capnproto",      doc = "Cap'n Proto RPC." },
  { ordinal = 10, name = "soap",           doc = "SOAP envelopes (legacy interop)." },
  { ordinal = 11, name = "verisimdb_rest", doc = "VerisimDB REST surface." },
  # --- Umoja substrate 4 ---------------------------------------------------
  { ordinal = 12, name = "bsp",            doc = "Build Server Protocol." },
  { ordinal = 13, name = "scip",           doc = "Source Code Index Protocol." },
  { ordinal = 14, name = "ipfs",           doc = "Content-addressed DLC distribution." },
  { ordinal = 15, name = "arrow_flight",   doc = "Arrow Flight bulk transfer." },
]
in

# Contract: exactly sixteen connectors, ordinals dense from 0, names distinct
# and snake_case. "Hexadeca" is a claim about the count; enforce it.
let Checked =
  std.contract.from_validator (fun cs =>
    if std.array.length cs != 16 then
      'Error { message = "the Hexadeca connector set must have exactly 16 members, found %{std.string.from_number (std.array.length cs)}" }
    else if std.array.map (fun c => c.ordinal) cs != std.array.generate (fun i => i) 16 then
      'Error { message = "ordinals must be dense and in order 0..15: the ordinal IS the wire tag" }
    else if
      std.array.length
        (std.array.fold_left
          (fun acc c => if std.array.elem c.name acc then acc else acc @ [c.name])
          []
          cs)
      != 16
    then
      'Error { message = "connector names must be distinct" }
    else if std.array.any (fun c => !std.string.is_match "^[a-z][a-z0-9_]*$" c.name) cs then
      'Error { message = "connector names must be snake_case" }
    else
      'Ok)
in

{
  connectors | Checked = connector_list,
  count = std.array.length connector_list,
  implemented_count =
    std.array.length (std.array.filter (fun c => c.implemented) connector_list),
}
