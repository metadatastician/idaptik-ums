// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
//! The UMS AI-edit engine.
//!
//! A Kautz type-6 neurosymbolic system over a miniKanren relational kernel
//! (`docs/adr/0001-ai-edit-kautz6-nesy.adoc`): the symbolic engine sits inside
//! the proposer's action loop rather than downstream of it. The proposer emits
//! a *partial* edit — a relational goal with fresh logic variables — and the
//! kernel completes or refutes it as part of the same act.
//!
//! - [`microkanren`] — the relational kernel: terms, unification, interleaved
//!   streams, goals.
//! - [`vocab`] — the closed worlds, generated from `config/vocab.ncl`.
//! - [`verbs`] — the edit verbs as state-in/state-out relations.
//! - [`constraints`] — the six validity proofs, as goals over a state term.
//! - [`engine`] — `solve()` (generative) and `apply_edit_script()` (checking).
//! - [`describe`] — runtime reflection: the registry as data.
//!
//! `#![forbid(unsafe_code)]`: nothing here needs it, and the guarantee that
//! an edit cannot corrupt a level should not rest on unaudited pointer work.

#![forbid(unsafe_code)]

pub mod constraints;
pub mod describe;
pub mod engine;
pub mod microkanren;
pub mod verbs;
pub mod vocab;

/// Placeholder marking an argument the engine should solve for.
pub const FRESH: &str = "?";

/// Guarantees (in the `dlc-manifest` sense) this engine backs.
pub const GUARANTEES: [&str; 2] = ["constraint-checked-edits", "replayable-edit-history"];
