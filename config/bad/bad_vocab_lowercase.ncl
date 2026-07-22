# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# NEGATIVE FIXTURE — must be REJECTED by `nickel export`.
# A vocabulary member that is not PascalCase.
let vocab = import "../vocab.ncl" in
vocab & { device_kinds = vocab.device_kinds @ ["laptop"] }
