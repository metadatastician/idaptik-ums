# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
"""A minimal, dependency-free miniKanren (microKanren) core.

This is the reference relational kernel for the UMS AI-edit engine
(docs/adr/0001-ai-edit-kautz6-nesy.adoc). It follows Hemann & Friedman's
microKanren closely and is intended to be small enough to port to other
languages verbatim.

Terms
    A *term* is a logic variable (`Var`), a tuple/list/dict whose values are
    terms, or any other Python value treated as a ground atom (compared
    with ``==``).

Substitutions
    A *substitution* is an immutable-by-convention dict mapping `Var` to
    term. `walk` resolves a variable through the substitution; `unify`
    extends a substitution so two terms become equal, or returns ``None``.

Goals and streams
    A *goal* is a function from a substitution to a *stream* of
    substitutions. A stream is one of:

    * ``()``            — the empty stream (no answers);
    * a callable        — an immature stream (a thunk; forcing it yields a
                          stream), which is what makes recursion and fair
                          interleaving possible;
    * ``(head, tail)``  — a mature stream: one answer plus the rest.

    `mplus` interleaves streams (so `disj` is complete even over infinite
    relations) and `bind` sequences a goal over a stream (`conj`).
"""

from __future__ import annotations

import inspect
import itertools


class Var:
    """A logic variable. Identity-based; `name` is only for debugging."""

    __slots__ = ("id", "name")
    _ids = itertools.count()

    def __init__(self, name=None):
        self.id = next(Var._ids)
        self.name = name

    def __repr__(self):
        return f"_{self.name or self.id}"


# --------------------------------------------------------------------------
# Substitutions
# --------------------------------------------------------------------------

def walk(term, subst):
    """Resolve `term` through `subst` until it is a non-variable or unbound."""
    while isinstance(term, Var) and term in subst:
        term = subst[term]
    return term


def walk_all(term, subst):
    """`walk` applied recursively through tuples, lists and dicts."""
    term = walk(term, subst)
    if isinstance(term, tuple):
        return tuple(walk_all(item, subst) for item in term)
    if isinstance(term, list):
        return [walk_all(item, subst) for item in term]
    if isinstance(term, dict):
        return {key: walk_all(value, subst) for key, value in term.items()}
    return term


def is_ground(term):
    """True when `term` contains no unbound logic variables."""
    if isinstance(term, Var):
        return False
    if isinstance(term, (tuple, list)):
        return all(is_ground(item) for item in term)
    if isinstance(term, dict):
        return all(is_ground(value) for value in term.values())
    return True


def unify(u, v, subst):
    """Extend `subst` so that u == v, or return None if impossible."""
    u, v = walk(u, subst), walk(v, subst)
    if u is v:
        return subst
    if isinstance(u, Var):
        return {**subst, u: v}
    if isinstance(v, Var):
        return {**subst, v: u}
    if isinstance(u, (tuple, list)) and type(u) is type(v) and len(u) == len(v):
        for a, b in zip(u, v):
            subst = unify(a, b, subst)
            if subst is None:
                return None
        return subst
    if isinstance(u, dict) and isinstance(v, dict) and u.keys() == v.keys():
        for key in u:
            subst = unify(u[key], v[key], subst)
            if subst is None:
                return None
        return subst
    return subst if u == v else None


# --------------------------------------------------------------------------
# Streams
# --------------------------------------------------------------------------

def mplus(s1, s2):
    """Merge two streams, interleaving at every immature point (fairness)."""
    if s1 == ():
        return s2
    if callable(s1):
        return lambda: mplus(s2, s1())
    return (s1[0], mplus(s1[1], s2))


def bind(stream, goal):
    """Apply `goal` to every answer in `stream`, merging the results."""
    if stream == ():
        return ()
    if callable(stream):
        return lambda: bind(stream(), goal)
    return mplus(goal(stream[0]), bind(stream[1], goal))


def take(n, stream):
    """Force up to `n` answers out of `stream` (all answers if n is None)."""
    answers = []
    while n is None or len(answers) < n:
        while callable(stream):
            stream = stream()
        if stream == ():
            break
        answers.append(stream[0])
        stream = stream[1]
    return answers


# --------------------------------------------------------------------------
# Goal constructors
# --------------------------------------------------------------------------

def succeed(subst):
    """The goal that always succeeds once."""
    return (subst, ())


def fail(subst):
    """The goal that never succeeds."""
    return ()


def eq(u, v):
    """Goal: u unifies with v."""
    def goal(subst):
        extended = unify(u, v, subst)
        return (extended, ()) if extended is not None else ()
    return goal


def disj(*goals):
    """Goal: at least one of `goals` holds (logical or, interleaved)."""
    if not goals:
        return fail
    def goal(subst):
        stream = ()
        for g in reversed(goals):
            stream = mplus(g(subst), stream)
        return stream
    return goal


def conj(*goals):
    """Goal: all of `goals` hold (logical and, left to right)."""
    if not goals:
        return succeed
    def goal(subst):
        stream = (subst, ())
        for g in goals:
            stream = bind(stream, g)
        return stream
    return goal


def fresh(fn):
    """Goal: `fn` holds for some values of its parameters.

    `fn` takes one logic variable per parameter and returns a goal, e.g.
    ``fresh(lambda x, y: conj(eq(x, 1), eq(y, x)))``.
    """
    arity = len(inspect.signature(fn).parameters)
    def goal(subst):
        return fn(*(Var() for _ in range(arity)))(subst)
    return goal


def conde(*clauses):
    """miniKanren's conde: each clause is a sequence of goals; clauses are
    disjuncts, goals within a clause are conjuncts."""
    return disj(*(conj(*clause) for clause in clauses))


def delay(thunk):
    """Wrap a goal-producing `thunk` so recursive relations build an
    immature stream instead of recursing eagerly, e.g.
    ``delay(lambda: nats(x, n + 1))``."""
    def goal(subst):
        return lambda: thunk()(subst)
    return goal


def project(terms, fn):
    """Goal: call `fn` with `terms` resolved against the current
    substitution; `fn` returns the goal to continue with.

    The standard escape hatch from pure relations into computation: use it
    only after the relevant terms have been grounded (e.g. by `membero`
    over a finite domain), and have `fn` return `fail` when they have not.
    """
    def goal(subst):
        return fn(*(walk_all(term, subst) for term in terms))(subst)
    return goal


def membero(x, items):
    """Goal: x is a member of the ground iterable `items`.

    Doubles as a generator: with x fresh, it enumerates `items` — the
    generate-and-narrow primitive behind `ai_edit.engine.solve`.
    """
    return disj(*(eq(x, item) for item in items))


# --------------------------------------------------------------------------
# Reification and the run interface
# --------------------------------------------------------------------------

def reify(term, subst):
    """Resolve `term` and replace unbound variables with '_0', '_1', ..."""
    term = walk_all(term, subst)
    names = {}
    def name(t):
        if isinstance(t, Var):
            return names.setdefault(t, f"_{len(names)}")
        if isinstance(t, tuple):
            return tuple(name(item) for item in t)
        if isinstance(t, list):
            return [name(item) for item in t]
        if isinstance(t, dict):
            return {key: name(value) for key, value in t.items()}
        return t
    return name(term)


def run(n, goal_fn):
    """Run the goal `goal_fn(q)` for a fresh query variable q and return up
    to `n` reified values of q (all values if n is None)."""
    q = Var("q")
    stream = goal_fn(q)({})
    return [reify(q, subst) for subst in take(n, stream)]
