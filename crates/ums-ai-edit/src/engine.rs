// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
//! The AI-edit engine: apply edit scripts, or solve for edits.
//!
//! Two directions over the same relational kernel:
//!
//! * [`apply_edit_script`] — the checking direction. Applies the script's
//!   verbs in order; after every verb the validity proofs must have a
//!   satisfying model or the script is rejected at that verb.
//!
//! * [`solve`] — the generative direction. A goal spec is an edit whose
//!   finite-domain arguments may be left fresh (the string `"?"`); the engine
//!   enumerates concrete edits whose resulting states satisfy all constraints.
//!   Generate-and-narrow, not generate-then-filter.
//!
//! [`solve`] is the seam where a neural proposer plugs in: the proposer
//! supplies intent, identifiers and geometry; the kernel supplies — or
//! refuses — everything the closed worlds and the proofs govern.

use std::collections::BTreeMap;

use serde_json::{Map, Value, json};

use crate::microkanren::{Goal, Subst, Term, Var, conj, eq, membero, run};
use crate::vocab::{self, VerbSpec};
use crate::{COMPATIBILITY_PROFILE, FRESH, GUARANTEES, constraints, verbs};

// ---------------------------------------------------------------------------
// JSON <-> Term
// ---------------------------------------------------------------------------

/// Convert a JSON value into a ground term.
pub fn from_json(value: &Value) -> Term {
    match value {
        Value::Null => Term::Null,
        Value::Bool(b) => Term::Bool(*b),
        Value::Number(n) => match n.as_i64() {
            Some(i) => Term::Int(i),
            None => Term::Num(n.as_f64().unwrap_or(f64::NAN)),
        },
        Value::String(s) => Term::Str(s.clone()),
        Value::Array(items) => Term::Seq(items.iter().map(from_json).collect()),
        Value::Object(map) => Term::Map(
            map.iter()
                .map(|(k, v)| (k.clone(), from_json(v)))
                .collect::<BTreeMap<_, _>>(),
        ),
    }
}

/// Convert a ground term back into JSON. Unbound variables reify to their
/// `_0`, `_1`, … names, which surface as strings.
pub fn to_json(term: &Term) -> Value {
    match term {
        Term::Null => Value::Null,
        Term::Bool(b) => json!(b),
        Term::Int(i) => json!(i),
        Term::Num(n) => json!(n),
        Term::Str(s) => json!(s),
        Term::Var(v) => json!(v.to_string()),
        Term::Seq(items) => Value::Array(items.iter().map(to_json).collect()),
        Term::Map(m) => {
            // Serialise in the map's own (sorted) order; the wire schema does
            // not depend on object key order, only on array order.
            let mut obj = Map::new();
            for (k, v) in m {
                obj.insert(k.clone(), to_json(v));
            }
            Value::Object(obj)
        }
    }
}

// ---------------------------------------------------------------------------
// Satisfiability
// ---------------------------------------------------------------------------

/// True when the validity proofs have a model for `state`.
pub fn satisfiable(state: &Term) -> bool {
    !run(Some(1), |q| {
        conj(vec![
            constraints::all_constraints(state.clone()),
            eq(q, Term::Bool(true)),
        ])
    })
    .is_empty()
}

// ---------------------------------------------------------------------------
// The checking direction
// ---------------------------------------------------------------------------

/// The outcome of replaying an edit script.
#[derive(Debug, Clone)]
pub struct Report {
    pub ok: bool,
    pub applied: usize,
    pub total: usize,
    pub steps: Vec<Step>,
    pub reason: Option<String>,
}

/// One verb's outcome within a report.
#[derive(Debug, Clone)]
pub struct Step {
    pub index: usize,
    pub verb: String,
    pub ok: bool,
    pub reason: Option<String>,
}

impl Report {
    pub fn to_json(&self) -> Value {
        let mut obj = Map::new();
        obj.insert("ok".into(), json!(self.ok));
        obj.insert("applied".into(), json!(self.applied));
        obj.insert("total".into(), json!(self.total));
        obj.insert(
            "steps".into(),
            Value::Array(
                self.steps
                    .iter()
                    .map(|s| {
                        let mut o = Map::new();
                        o.insert("index".into(), json!(s.index));
                        o.insert("verb".into(), json!(s.verb));
                        o.insert("ok".into(), json!(s.ok));
                        if let Some(r) = &s.reason {
                            o.insert("reason".into(), json!(r));
                        }
                        Value::Object(o)
                    })
                    .collect(),
            ),
        );
        if let Some(r) = &self.reason {
            obj.insert("reason".into(), json!(r));
        }
        obj.insert("guarantees".into(), json!(GUARANTEES));
        Value::Object(obj)
    }
}

const NO_MODEL: &str = "no satisfying model: the edit violates the validity proofs \
(guards-in-zones, defence-targets, zones-ordered, pbx-consistent, devices-exist, \
items-in-zones) or its vocabulary";

/// Apply `script` to `state`, returning the last good state and a report.
///
/// The input state is checked first; then each verb must leave a state for
/// which all constraint goals have a satisfying model, or the script is
/// rejected at that verb.
pub fn apply_edit_script(state: &Term, script: &Value) -> (Term, Report) {
    let edits: Vec<Value> = match script {
        Value::Object(o) => o
            .get("edits")
            .and_then(|e| e.as_array())
            .cloned()
            .unwrap_or_default(),
        Value::Array(a) => a.clone(),
        _ => Vec::new(),
    };

    let mut report = Report {
        ok: false,
        applied: 0,
        total: edits.len(),
        steps: Vec::new(),
        reason: None,
    };

    if !satisfiable(state) {
        report.reason = Some("initial state violates the validity proofs".into());
        return (state.clone(), report);
    }

    let mut current = state.clone();
    for (index, edit) in edits.iter().enumerate() {
        let verb_name = edit
            .get("verb")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let mut step = Step {
            index,
            verb: verb_name.clone(),
            ok: false,
            reason: None,
        };

        let Some(spec) = vocab::verb(&verb_name) else {
            step.reason = Some(format!("unknown verb {verb_name:?}"));
            report.steps.push(step);
            return (current, report);
        };

        let missing: Vec<&str> = spec
            .required
            .iter()
            .copied()
            .filter(|a| edit.get(*a).is_none())
            .collect();
        if !missing.is_empty() {
            step.reason = Some(format!("missing arguments {missing:?}"));
            report.steps.push(step);
            return (current, report);
        }

        // Positional arguments, in the registry's declared order. An absent
        // optional argument becomes Null and is dropped when the record is
        // built.
        let args: Vec<Term> = spec
            .args
            .iter()
            .map(|a| edit.get(*a).map(from_json).unwrap_or(Term::Null))
            .collect();

        if args.iter().any(|t| t.as_str() == Some(FRESH)) {
            step.reason = Some("apply requires ground arguments; use solve()".into());
            report.steps.push(step);
            return (current, report);
        }

        let s_out = Term::Var(Var::new("state"));
        let goal = conj(vec![
            verbs::apply(spec, current.clone(), &args, s_out.clone()),
            constraints::all_constraints(s_out.clone()),
        ]);
        let models = run(Some(1), move |q| {
            conj(vec![goal.clone(), eq(q, s_out.clone())])
        });

        if models.is_empty() {
            step.reason = Some(NO_MODEL.into());
            report.steps.push(step);
            return (current, report);
        }

        current = models[0].clone();
        step.ok = true;
        report.steps.push(step);
        report.applied = index + 1;
    }

    report.ok = true;
    (current, report)
}

/// Dispatch an edit script through a named profile.
///
/// The staged implementation has one executable backend: IDApTIK. Other
/// registered profiles are reflective and validatable but are refused here
/// until they provide a real edit backend. The legacy [`apply_edit_script`]
/// function remains an IDApTIK compatibility facade.
pub fn apply_profile_edit_script(profile_id: &str, state: &Term, script: &Value) -> (Term, Report) {
    let registry = ums_profile_sdk::ProfileRegistry::with_builtins();
    let Some(profile) = registry.get(profile_id) else {
        return (
            state.clone(),
            Report {
                ok: false,
                applied: 0,
                total: 0,
                steps: Vec::new(),
                reason: Some(format!("unknown profile {profile_id:?}")),
            },
        );
    };

    let edits = script
        .get("edits")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    if let Some(verb) = edits
        .iter()
        .filter_map(|edit| edit.get("verb").and_then(Value::as_str))
        .find(|verb| profile.edit_verb(verb).is_none())
    {
        return (
            state.clone(),
            Report {
                ok: false,
                applied: 0,
                total: edits.len(),
                steps: Vec::new(),
                reason: Some(format!(
                    "verb {verb:?} is not declared by profile {profile_id:?}"
                )),
            },
        );
    }

    if profile_id != COMPATIBILITY_PROFILE {
        return (
            state.clone(),
            Report {
                ok: false,
                applied: 0,
                total: edits.len(),
                steps: Vec::new(),
                reason: Some(format!(
                    "profile {profile_id:?} has no executable edit backend yet"
                )),
            },
        );
    }

    apply_edit_script(state, script)
}

// ---------------------------------------------------------------------------
// The generative direction
// ---------------------------------------------------------------------------

/// One concrete edit the kernel found, plus the state it produces.
#[derive(Debug, Clone)]
pub struct Proposal {
    pub edit: Value,
    pub state: Term,
}

/// Why a goal spec could not be turned into a search.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SolveError {
    UnknownVerb(String),
    MissingArgument { verb: String, arg: String },
    NoFiniteDomain { verb: String, arg: String },
}

impl std::fmt::Display for SolveError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SolveError::UnknownVerb(v) => write!(f, "unknown verb {v:?}"),
            SolveError::MissingArgument { verb, arg } => {
                write!(
                    f,
                    "{verb} requires argument {arg:?} (use '?' to solve for it)"
                )
            }
            SolveError::NoFiniteDomain { verb, arg } => write!(
                f,
                "cannot solve for {verb}.{arg}: no finite domain to enumerate"
            ),
        }
    }
}

impl std::error::Error for SolveError {}

/// The zone domain is derived from the state, not from a vocabulary: which
/// zones exist is a fact about this level.
fn zone_domain(state: &Term) -> Vec<Term> {
    state
        .get("zones")
        .and_then(|z| z.as_seq())
        .map(|zs| zs.iter().filter_map(|z| z.get("id").cloned()).collect())
        .unwrap_or_default()
}

/// Enumerate up to `n` concrete edits satisfying a partial `goal_spec`.
///
/// `goal_spec` is an edit object where finite-domain arguments may carry the
/// placeholder `"?"`. Ids and geometry must be supplied by the caller — today,
/// the neural proposer's job.
pub fn solve(state: &Term, goal_spec: &Value, n: usize) -> Result<Vec<Proposal>, SolveError> {
    let verb_name = goal_spec
        .get("verb")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let Some(spec) = vocab::verb(&verb_name) else {
        return Err(SolveError::UnknownVerb(verb_name));
    };

    let mut domain_goals: Vec<Goal> = Vec::new();
    let mut arg_terms: Vec<Term> = Vec::new();

    for name in spec.args.iter() {
        let required = spec.required.contains(name);
        let Some(value) = goal_spec.get(*name) else {
            if required {
                return Err(SolveError::MissingArgument {
                    verb: verb_name,
                    arg: (*name).into(),
                });
            }
            arg_terms.push(Term::Null);
            continue;
        };

        if value.as_str() == Some(FRESH) {
            let domain: Vec<Term> = if *name == "zone" {
                zone_domain(state)
            } else {
                match spec.domain(name) {
                    Some(d) => d.iter().map(|s| Term::str(*s)).collect(),
                    None => {
                        return Err(SolveError::NoFiniteDomain {
                            verb: verb_name,
                            arg: (*name).into(),
                        });
                    }
                }
            };
            let v = Term::Var(Var::new("arg"));
            domain_goals.push(membero(v.clone(), &domain));
            arg_terms.push(v);
        } else {
            arg_terms.push(from_json(value));
        }
    }

    let s_out = Term::Var(Var::new("state"));
    let mut goals = domain_goals;
    goals.push(verbs::apply(spec, state.clone(), &arg_terms, s_out.clone()));
    goals.push(constraints::all_constraints(s_out.clone()));
    let goal = conj(goals);

    let query = Term::Seq(vec![Term::Seq(arg_terms.clone()), s_out.clone()]);
    let answers = run(Some(n), move |q| {
        conj(vec![goal.clone(), eq(q, query.clone())])
    });

    Ok(answers
        .iter()
        .filter_map(|answer| {
            let pair = answer.as_seq()?;
            let bound = pair.first()?.as_seq()?;
            let new_state = pair.get(1)?.clone();
            let mut edit = Map::new();
            edit.insert("verb".into(), json!(spec.name));
            for (name, value) in spec.args.iter().zip(bound.iter()) {
                if matches!(value, Term::Null) && !spec.required.contains(name) {
                    continue;
                }
                edit.insert((*name).to_string(), to_json(value));
            }
            Some(Proposal {
                edit: Value::Object(edit),
                state: new_state,
            })
        })
        .collect())
}

/// Re-exported so integration tests can build a substitution without
/// depending on the kernel's internals.
pub fn empty_subst() -> Subst {
    Subst::new()
}

/// Convenience: the verb registry entry for `name`.
pub fn verb_spec(name: &str) -> Option<&'static VerbSpec> {
    vocab::verb(name)
}
