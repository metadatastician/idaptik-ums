// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
//! `ums-ai-edit` — the AI-edit engine's command line.
//!
//! Replaces `python3 -m ai_edit`. Same three verbs, same exit-code contract:
//! a rejected script exits non-zero so `just ai-edit-check` and CI can gate
//! on it.

use std::process::ExitCode;

use clap::{Parser, Subcommand};
use serde_json::{Value, json};
use ums_ai_edit::{describe, engine, verbs};

#[derive(Parser)]
#[command(
    name = "ums-ai-edit",
    about = "The UMS AI-edit engine: a miniKanren relational kernel over the IDApTIK level object graph.",
    version
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Replay an edit script, rejecting it at the first verb whose result
    /// state has no satisfying model.
    Check {
        /// Path to an idaptik-edit/1 payload.
        script: String,
        /// Optional base state (JSON). Defaults to an empty level.
        #[arg(long)]
        state: Option<String>,
    },
    /// Enumerate concrete edits satisfying a partial goal spec, in which
    /// finite-domain arguments may be "?".
    Solve {
        /// Goal spec as JSON, e.g. '{"verb":"add_guard","id":"g1","rank":"?","zone":"?"}'.
        spec: String,
        /// Base state (JSON). Defaults to an empty level.
        #[arg(long)]
        state: Option<String>,
        /// Maximum number of proposals.
        #[arg(short, long, default_value_t = 5)]
        number: usize,
    },
    /// Print the engine's own registry, vocabularies and guarantees as JSON.
    ///
    /// `just ai-edit-reflect` compares this against the Nickel source that
    /// generated it.
    Describe,
}

fn read_state(path: &Option<String>) -> Result<ums_ai_edit::microkanren::Term, String> {
    match path {
        None => Ok(verbs::initial_state()),
        Some(p) => {
            let text = std::fs::read_to_string(p).map_err(|e| format!("{p}: {e}"))?;
            let value: Value = serde_json::from_str(&text).map_err(|e| format!("{p}: {e}"))?;
            Ok(engine::from_json(&value))
        }
    }
}

fn main() -> ExitCode {
    let cli = Cli::parse();

    match cli.command {
        Command::Describe => {
            println!(
                "{}",
                serde_json::to_string_pretty(&describe::describe()).unwrap()
            );
            ExitCode::SUCCESS
        }

        Command::Check { script, state } => {
            let base = match read_state(&state) {
                Ok(s) => s,
                Err(e) => {
                    eprintln!("error: {e}");
                    return ExitCode::FAILURE;
                }
            };
            let text = match std::fs::read_to_string(&script) {
                Ok(t) => t,
                Err(e) => {
                    eprintln!("error: {script}: {e}");
                    return ExitCode::FAILURE;
                }
            };
            let payload: Value = match serde_json::from_str(&text) {
                Ok(v) => v,
                Err(e) => {
                    eprintln!("error: {script}: {e}");
                    return ExitCode::FAILURE;
                }
            };
            // Accept either a bare payload or a full dlc-manifest envelope.
            let script_value = payload
                .get("payload")
                .filter(|p| p.get("edits").is_some())
                .cloned()
                .unwrap_or(payload);

            let (_, report) = engine::apply_edit_script(&base, &script_value);
            println!(
                "{}",
                serde_json::to_string_pretty(&report.to_json()).unwrap()
            );
            if report.ok {
                ExitCode::SUCCESS
            } else {
                ExitCode::FAILURE
            }
        }

        Command::Solve {
            spec,
            state,
            number,
        } => {
            let base = match read_state(&state) {
                Ok(s) => s,
                Err(e) => {
                    eprintln!("error: {e}");
                    return ExitCode::FAILURE;
                }
            };
            let goal: Value = match serde_json::from_str(&spec) {
                Ok(v) => v,
                Err(e) => {
                    eprintln!("error: goal spec is not valid JSON: {e}");
                    return ExitCode::FAILURE;
                }
            };
            match engine::solve(&base, &goal, number) {
                Ok(proposals) => {
                    let out: Vec<Value> = proposals
                        .iter()
                        .map(|p| json!({ "edit": p.edit, "state": engine::to_json(&p.state) }))
                        .collect();
                    println!("{}", serde_json::to_string_pretty(&out).unwrap());
                    // No proposals means the kernel refused: a real outcome,
                    // and a non-zero exit so a caller can gate on it.
                    if proposals.is_empty() {
                        ExitCode::FAILURE
                    } else {
                        ExitCode::SUCCESS
                    }
                }
                Err(e) => {
                    eprintln!("error: {e}");
                    ExitCode::FAILURE
                }
            }
        }
    }
}
