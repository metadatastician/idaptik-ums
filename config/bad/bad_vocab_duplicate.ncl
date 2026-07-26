# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# NEGATIVE FIXTURE — must be REJECTED by `nickel export`.
# A duplicated vocabulary member: closed worlds must be sets.
let vocab = import "../vocab.ncl" in
vocab & { dog_breeds = ["Patrol", "Bloodhound", "RoboDog", "Patrol"] }
