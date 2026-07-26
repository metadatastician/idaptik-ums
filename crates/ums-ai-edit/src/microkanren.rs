// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
//! A minimal, dependency-free miniKanren (microKanren) core.
//!
//! This is the relational kernel of the UMS AI-edit engine
//! (`docs/adr/0001-ai-edit-kautz6-nesy.adoc`). It follows Hemann & Friedman's
//! microKanren, ported from the reference Python kernel it replaces.
//!
//! # Terms
//!
//! A [`Term`] is a logic variable, a sequence or map whose values are terms,
//! or a ground atom compared structurally.
//!
//! # Substitutions
//!
//! A [`Subst`] maps variables to terms. It is a persistent `Rc`-linked
//! association list: extending it is O(1) and shares structure with its
//! parent, so the search can branch without copying. (The Python original
//! wrote `{**subst, u: v}`, copying the whole map at every binding.)
//!
//! # Goals and streams
//!
//! A *goal* is a function from a substitution to a [`Stream`] of
//! substitutions. A stream is empty, *immature* (a thunk — which is what
//! makes recursion and fair interleaving possible), or *mature* (one answer
//! plus the rest). [`mplus`] interleaves, so [`disj`] stays complete even
//! over infinite relations; [`bind`] sequences a goal over a stream.

use std::collections::BTreeMap;
use std::fmt;
use std::rc::Rc;
use std::sync::atomic::{AtomicU64, Ordering};

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

static NEXT_VAR: AtomicU64 = AtomicU64::new(0);

/// A logic variable. Identity-based; the name is only for debugging.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Var {
    pub id: u64,
    pub name: Option<&'static str>,
}

impl Var {
    pub fn new(name: &'static str) -> Self {
        Var {
            id: NEXT_VAR.fetch_add(1, Ordering::Relaxed),
            name: Some(name),
        }
    }

    pub fn anonymous() -> Self {
        Var {
            id: NEXT_VAR.fetch_add(1, Ordering::Relaxed),
            name: None,
        }
    }
}

impl fmt::Display for Var {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.name {
            Some(n) => write!(f, "_{n}"),
            None => write!(f, "_{}", self.id),
        }
    }
}

// ---------------------------------------------------------------------------
// Terms
// ---------------------------------------------------------------------------

/// A term: a logic variable, a compound, or a ground atom.
///
/// `Num` holds the JSON number tower. Integers and floats compare across the
/// boundary (`Int(1) == Num(1.0)`) because the wire format is JSON, where
/// `1` and `1.0` denote the same value and the Python original compared them
/// with `==`.
#[derive(Clone, Debug)]
pub enum Term {
    Var(Var),
    Str(String),
    Int(i64),
    Num(f64),
    Bool(bool),
    Null,
    Seq(Vec<Term>),
    Map(BTreeMap<String, Term>),
}

impl Term {
    pub fn str(s: impl Into<String>) -> Term {
        Term::Str(s.into())
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Term::Str(s) => Some(s),
            _ => None,
        }
    }

    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Term::Int(i) => Some(*i as f64),
            Term::Num(n) => Some(*n),
            _ => None,
        }
    }

    pub fn as_seq(&self) -> Option<&Vec<Term>> {
        match self {
            Term::Seq(v) => Some(v),
            _ => None,
        }
    }

    pub fn as_map(&self) -> Option<&BTreeMap<String, Term>> {
        match self {
            Term::Map(m) => Some(m),
            _ => None,
        }
    }

    /// Field of a map term, or `None` if absent or not a map.
    pub fn get(&self, key: &str) -> Option<&Term> {
        self.as_map().and_then(|m| m.get(key))
    }

    pub fn is_truthy(&self) -> bool {
        match self {
            Term::Bool(b) => *b,
            Term::Null => false,
            _ => true,
        }
    }
}

impl PartialEq for Term {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Term::Var(a), Term::Var(b)) => a == b,
            (Term::Str(a), Term::Str(b)) => a == b,
            (Term::Bool(a), Term::Bool(b)) => a == b,
            (Term::Null, Term::Null) => true,
            // Cross-compare the number tower: JSON has one number type.
            (Term::Int(a), Term::Int(b)) => a == b,
            (Term::Int(a), Term::Num(b)) => (*a as f64) == *b,
            (Term::Num(a), Term::Int(b)) => *a == (*b as f64),
            (Term::Num(a), Term::Num(b)) => a == b,
            (Term::Seq(a), Term::Seq(b)) => a == b,
            (Term::Map(a), Term::Map(b)) => a == b,
            _ => false,
        }
    }
}

// ---------------------------------------------------------------------------
// Substitutions
// ---------------------------------------------------------------------------

/// A persistent substitution: a shared-structure association list.
#[derive(Clone, Debug, Default)]
pub enum Subst {
    #[default]
    Empty,
    Bind(Var, Term, Rc<Subst>),
}

impl Subst {
    pub fn new() -> Self {
        Subst::Empty
    }

    fn lookup(&self, v: &Var) -> Option<&Term> {
        let mut cur = self;
        loop {
            match cur {
                Subst::Empty => return None,
                Subst::Bind(k, t, rest) => {
                    if k == v {
                        return Some(t);
                    }
                    cur = rest;
                }
            }
        }
    }

    fn extend(&self, v: Var, t: Term) -> Subst {
        Subst::Bind(v, t, Rc::new(self.clone()))
    }
}

/// Resolve `term` through `subst` until it is a non-variable or unbound.
pub fn walk(term: &Term, subst: &Subst) -> Term {
    let mut cur = term.clone();
    while let Term::Var(ref v) = cur {
        match subst.lookup(v) {
            Some(next) => cur = next.clone(),
            None => break,
        }
    }
    cur
}

/// [`walk`] applied recursively through sequences and maps.
pub fn walk_all(term: &Term, subst: &Subst) -> Term {
    let t = walk(term, subst);
    match t {
        Term::Seq(items) => Term::Seq(items.iter().map(|i| walk_all(i, subst)).collect()),
        Term::Map(m) => Term::Map(
            m.iter()
                .map(|(k, v)| (k.clone(), walk_all(v, subst)))
                .collect(),
        ),
        other => other,
    }
}

/// True when `term` contains no unbound logic variables.
pub fn is_ground(term: &Term) -> bool {
    match term {
        Term::Var(_) => false,
        Term::Seq(items) => items.iter().all(is_ground),
        Term::Map(m) => m.values().all(is_ground),
        _ => true,
    }
}

/// Extend `subst` so that `u == v`, or return `None` if impossible.
pub fn unify(u: &Term, v: &Term, subst: &Subst) -> Option<Subst> {
    let u = walk(u, subst);
    let v = walk(v, subst);
    match (&u, &v) {
        (Term::Var(a), Term::Var(b)) if a == b => Some(subst.clone()),
        (Term::Var(a), _) => Some(subst.extend(a.clone(), v.clone())),
        (_, Term::Var(b)) => Some(subst.extend(b.clone(), u.clone())),
        (Term::Seq(a), Term::Seq(b)) => {
            if a.len() != b.len() {
                return None;
            }
            let mut s = subst.clone();
            for (x, y) in a.iter().zip(b.iter()) {
                s = unify(x, y, &s)?;
            }
            Some(s)
        }
        (Term::Map(a), Term::Map(b)) => {
            // Python compared `u.keys() == v.keys()` before unifying values.
            if a.len() != b.len() || !a.keys().eq(b.keys()) {
                return None;
            }
            let mut s = subst.clone();
            for (k, x) in a.iter() {
                s = unify(x, &b[k], &s)?;
            }
            Some(s)
        }
        _ => {
            if u == v {
                Some(subst.clone())
            } else {
                None
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Streams
// ---------------------------------------------------------------------------

/// A stream of answers: empty, immature (a thunk), or mature.
pub enum Stream {
    Empty,
    Immature(Box<dyn FnOnce() -> Stream>),
    Mature(Subst, Box<Stream>),
}

/// Merge two streams, interleaving at every immature point (fairness).
pub fn mplus(s1: Stream, s2: Stream) -> Stream {
    match s1 {
        Stream::Empty => s2,
        // Swapping the arguments here is what makes `disj` fair: neither
        // branch can starve the other, so search stays complete even over
        // infinite relations.
        Stream::Immature(t) => Stream::Immature(Box::new(move || mplus(s2, t()))),
        Stream::Mature(head, tail) => Stream::Mature(head, Box::new(mplus(*tail, s2))),
    }
}

/// Apply `goal` to every answer in `stream`, merging the results.
pub fn bind(stream: Stream, goal: Goal) -> Stream {
    match stream {
        Stream::Empty => Stream::Empty,
        Stream::Immature(t) => Stream::Immature(Box::new(move || bind(t(), goal))),
        Stream::Mature(head, tail) => {
            let g = goal.clone();
            mplus(goal(head), bind(*tail, g))
        }
    }
}

/// Force up to `n` answers out of `stream` (all answers when `n` is `None`).
pub fn take(n: Option<usize>, stream: Stream) -> Vec<Subst> {
    let mut answers = Vec::new();
    let mut cur = stream;
    loop {
        if let Some(limit) = n {
            if answers.len() >= limit {
                break;
            }
        }
        // Force through immature points without growing the Rust stack.
        loop {
            match cur {
                Stream::Immature(t) => cur = t(),
                other => {
                    cur = other;
                    break;
                }
            }
        }
        match cur {
            Stream::Empty => break,
            Stream::Mature(head, tail) => {
                answers.push(head);
                cur = *tail;
            }
            Stream::Immature(_) => unreachable!("forced above"),
        }
    }
    answers
}

// ---------------------------------------------------------------------------
// Goals
// ---------------------------------------------------------------------------

/// A goal: a substitution in, a stream of substitutions out.
pub type Goal = Rc<dyn Fn(Subst) -> Stream>;

/// The goal that always succeeds, once.
pub fn succeed() -> Goal {
    Rc::new(|s| Stream::Mature(s, Box::new(Stream::Empty)))
}

/// The goal that never succeeds.
pub fn fail() -> Goal {
    Rc::new(|_| Stream::Empty)
}

/// Goal: `u` unifies with `v`.
pub fn eq(u: Term, v: Term) -> Goal {
    Rc::new(move |s| match unify(&u, &v, &s) {
        Some(extended) => Stream::Mature(extended, Box::new(Stream::Empty)),
        None => Stream::Empty,
    })
}

/// Goal: at least one of `goals` holds (logical or, interleaved).
pub fn disj(goals: Vec<Goal>) -> Goal {
    if goals.is_empty() {
        return fail();
    }
    Rc::new(move |s: Subst| {
        let mut stream = Stream::Empty;
        for g in goals.iter().rev() {
            stream = mplus(g(s.clone()), stream);
        }
        stream
    })
}

/// Goal: all of `goals` hold (logical and, left to right).
pub fn conj(goals: Vec<Goal>) -> Goal {
    if goals.is_empty() {
        return succeed();
    }
    Rc::new(move |s: Subst| {
        let mut stream = Stream::Mature(s, Box::new(Stream::Empty));
        for g in goals.iter() {
            stream = bind(stream, g.clone());
        }
        stream
    })
}

/// miniKanren's `conde`: clauses are disjuncts, goals within a clause are
/// conjuncts.
pub fn conde(clauses: Vec<Vec<Goal>>) -> Goal {
    disj(clauses.into_iter().map(conj).collect())
}

/// Wrap a goal-producing thunk so a recursive relation builds an immature
/// stream instead of recursing eagerly.
pub fn delay(thunk: impl Fn() -> Goal + 'static) -> Goal {
    Rc::new(move |s| {
        let g = thunk();
        Stream::Immature(Box::new(move || g(s)))
    })
}

/// Goal: call `f` with `terms` resolved against the current substitution;
/// `f` returns the goal to continue with.
///
/// The standard escape hatch from pure relations into computation. Use it
/// only once the relevant terms are ground (e.g. via [`membero`] over a
/// finite domain), and have `f` return [`fail`] when they are not.
pub fn project(terms: Vec<Term>, f: impl Fn(&[Term]) -> Goal + 'static) -> Goal {
    Rc::new(move |s: Subst| {
        let resolved: Vec<Term> = terms.iter().map(|t| walk_all(t, &s)).collect();
        f(&resolved)(s)
    })
}

/// Goal: `x` is a member of the ground list `items`.
///
/// Doubles as a generator: with `x` fresh it enumerates `items`. This is the
/// generate-and-narrow primitive behind `engine::solve` — the reason an
/// out-of-vocabulary value is never generated rather than generated and then
/// filtered out.
pub fn membero(x: Term, items: &[Term]) -> Goal {
    disj(items.iter().map(|i| eq(x.clone(), i.clone())).collect())
}

/// Introduce fresh logic variables.
///
/// The Python original read the lambda's arity by runtime introspection
/// (`inspect.signature`). Rust has no equivalent, and does not need one: the
/// arity is written down and checked by the compiler.
///
/// ```ignore
/// fresh!(x, y => conj(vec![eq(x.clone(), Term::Int(1)), eq(y, x)]))
/// ```
#[macro_export]
macro_rules! fresh {
    ($($v:ident),+ => $body:expr) => {{
        $( let $v = $crate::microkanren::Term::Var($crate::microkanren::Var::new(stringify!($v))); )+
        $body
    }};
}

// ---------------------------------------------------------------------------
// Reification and the run interface
// ---------------------------------------------------------------------------

/// Resolve `term` and replace unbound variables with `_0`, `_1`, ...
pub fn reify(term: &Term, subst: &Subst) -> Term {
    fn name(t: &Term, names: &mut BTreeMap<Var, String>) -> Term {
        match t {
            Term::Var(v) => {
                let next = names.len();
                let n = names.entry(v.clone()).or_insert_with(|| format!("_{next}"));
                Term::Str(n.clone())
            }
            Term::Seq(items) => Term::Seq(items.iter().map(|i| name(i, names)).collect()),
            Term::Map(m) => Term::Map(m.iter().map(|(k, v)| (k.clone(), name(v, names))).collect()),
            other => other.clone(),
        }
    }
    let walked = walk_all(term, subst);
    let mut names = BTreeMap::new();
    name(&walked, &mut names)
}

/// Run `goal_fn(q)` for a fresh query variable `q` and return up to `n`
/// reified values of `q` (all values when `n` is `None`).
pub fn run(n: Option<usize>, goal_fn: impl Fn(Term) -> Goal) -> Vec<Term> {
    let q = Term::Var(Var::new("q"));
    let stream = goal_fn(q.clone())(Subst::new());
    take(n, stream).iter().map(|s| reify(&q, s)).collect()
}
