# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# NEGATIVE FIXTURE — must be REJECTED by `nickel export`.
# An empty vocabulary would make its domain relation unsatisfiable.
let vocab = import "../vocab.ncl" in
vocab & { item_categories = [] }
