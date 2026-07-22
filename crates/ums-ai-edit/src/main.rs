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
    /// Evaluate the ZonesOrdered proof over a shared vector table and print
    /// one verdict per line.
    ///
    /// Exists so `just spark-parity` can drive the SAME vectors through this
    /// engine and through the SPARK reference model in `spark/` and diff the
    /// verdicts. The two must not be able to diverge silently.
    ZonesVerdicts {
        /// Path to the vector table (see spark/vectors.txt for the format).
        vectors: String,
    },
    /// Print the engine's own registry, vocabularies and guarantees as JSON.
    ///
    /// `just ai-edit-reflect` compares this against the Nickel source that
    /// generated it.
    Describe,
}

/// `start,end,tier` -> a zone object. Ids are synthesised: ZonesOrdered does
/// not look at them, and the SPARK model has no notion of them.
fn parse_zone(spec: &str) -> Result<Value, String> {
    let parts: Vec<&str> = spec.split(',').collect();
    if parts.len() != 3 {
        return Err(format!("expected start,end,tier, got {spec:?}"));
    }
    let num = |s: &str| -> Result<i64, String> {
        s.trim().parse::<i64>().map_err(|e| format!("{s:?}: {e}"))
    };
    Ok(json!({
        "id": format!("z{}-{}", num(parts[0])?, num(parts[1])?),
        "worldXStart": num(parts[0])?,
        "worldXEnd": num(parts[1])?,
        "securityTier": num(parts[2])?,
    }))
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
        Command::ZonesVerdicts { vectors } => {
            let text = match std::fs::read_to_string(&vectors) {
                Ok(t) => t,
                Err(e) => {
                    eprintln!("error: {vectors}: {e}");
                    return ExitCode::FAILURE;
                }
            };
            for line in text.lines() {
                let line = line.trim();
                if line.is_empty() || line.starts_with('#') {
                    continue;
                }
                let zones: Vec<Value> = if line == "empty" {
                    Vec::new()
                } else {
                    match line.split(';').map(parse_zone).collect::<Result<_, _>>() {
                        Ok(z) => z,
                        Err(e) => {
                            eprintln!("error: bad vector {line:?}: {e}");
                            return ExitCode::FAILURE;
                        }
                    }
                };
                let state = engine::from_json(&json!({
                    "zones": zones,
                    "devices": [], "guards": [], "dogs": [], "drones": [],
                    "assassins": [], "items": [], "npcs": [], "characters": [],
                    "wiring": [], "zoneTransitions": [], "deviceDefences": [],
                    "mission": null, "physical": null,
                    "hasPBX": false, "pbxIp": null, "pbxWorldX": null
                }));
                let holds = !ums_ai_edit::microkanren::run(Some(1), |q| {
                    ums_ai_edit::microkanren::conj(vec![
                        ums_ai_edit::constraints::zones_ordered(state.clone()),
                        ums_ai_edit::microkanren::eq(q, ums_ai_edit::microkanren::Term::Bool(true)),
                    ])
                })
                .is_empty();
                // Uppercase to match Ada's Boolean'Image, so the harness can
                // diff the two streams directly.
                println!("{}", if holds { "TRUE" } else { "FALSE" });
            }
            ExitCode::SUCCESS
        }

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
