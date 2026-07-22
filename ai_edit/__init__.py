# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
"""UMS AI-edit engine: a miniKanren relational kernel over the IDApTIK
level object graph.

Edits are data (idaptik-edit/1 payloads); verbs are state-in/state-out
relations; the archive editor's validity proofs (extended with a UMS items
rule) are constraint goals,
so an edit is only emitted when a satisfying model exists. Architecture:
docs/adr/0001-ai-edit-kautz6-nesy.adoc.
"""

from .engine import (  # noqa: F401
    FRESH,
    GUARANTEES,
    VERB_SPECS,
    apply_edit_script,
    solve,
)
from .verbs import initial_state  # noqa: F401

__all__ = [
    "FRESH",
    "GUARANTEES",
    "VERB_SPECS",
    "apply_edit_script",
    "initial_state",
    "solve",
]
