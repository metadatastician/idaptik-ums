// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
//! `ums-dlc` — the UMS <-> game bridge smoke test.
//!
//! Replaces `scripts/validate_dlc.py`. Same contract: exit 0 when every
//! artifact is valid, 1 when any is not, and report EVERY violation rather
//! than stopping at the first.

use std::path::{Path, PathBuf};
use std::process::ExitCode;

use clap::Parser;
use serde_json::Value;

#[derive(Parser)]
#[command(
    name = "ums-dlc",
    about = "Validate every DLC artifact against the bridge contracts in schemas/.",
    version
)]
struct Cli {
    /// Repository root (defaults to the current directory).
    #[arg(long, default_value = ".")]
    root: PathBuf,
}

/// Every .json under `dir`, sorted, so output order is deterministic.
fn json_files(dir: &Path) -> Vec<PathBuf> {
    let mut found = Vec::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(d) = stack.pop() {
        let Ok(entries) = std::fs::read_dir(&d) else {
            continue;
        };
        for entry in entries.flatten() {
            let p = entry.path();
            if p.is_dir() {
                stack.push(p);
            } else if p.extension().and_then(|e| e.to_str()) == Some("json") {
                found.push(p);
            }
        }
    }
    found.sort();
    found
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    let root = &cli.root;
    let dlc = root.join("dlc");
    let taxonomy_path = root.join("schemas/taxonomy-map.json");

    if !dlc.is_dir() {
        eprintln!("error: {} does not exist", dlc.display());
        return ExitCode::FAILURE;
    }

    let mut failures = 0usize;
    let mut checked = 0usize;

    // The taxonomy map first: it is the seam contract every edit script is
    // validated against, so an incoherent map must fail loudly rather than
    // silently loosening everything downstream.
    checked += 1;
    match std::fs::read_to_string(&taxonomy_path)
        .ok()
        .and_then(|t| serde_json::from_str::<Value>(&t).ok())
    {
        None => {
            println!("FAIL schemas/taxonomy-map.json: missing or unparseable");
            failures += 1;
        }
        Some(doc) => {
            let errors = ums_dlc::taxonomy::check(&doc);
            if errors.is_empty() {
                println!("ok   schemas/taxonomy-map.json");
            } else {
                println!("FAIL schemas/taxonomy-map.json");
                for e in &errors {
                    println!("     - {e}");
                }
                failures += 1;
            }
        }
    }

    for path in json_files(&dlc) {
        let rel = path
            .strip_prefix(root)
            .unwrap_or(&path)
            .display()
            .to_string();
        checked += 1;
        let mut errors: Vec<String> = Vec::new();

        let doc: Value = match std::fs::read_to_string(&path)
            .map_err(|e| e.to_string())
            .and_then(|t| serde_json::from_str(&t).map_err(|e| e.to_string()))
        {
            Ok(d) => d,
            Err(e) => {
                println!("FAIL {rel}: unparseable JSON ({e})");
                failures += 1;
                continue;
            }
        };

        if !doc.is_object() {
            errors.push("top level must be an object".into());
        } else {
            ums_dlc::classify_and_check(&path, &doc, &mut errors);
        }

        if errors.is_empty() {
            println!("ok   {rel}");
        } else {
            println!("FAIL {rel}");
            for e in &errors {
                println!("     - {e}");
            }
            failures += 1;
        }
    }

    println!("\n{checked} artifacts checked, {failures} invalid");
    if failures > 0 {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}
