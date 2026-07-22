-- SPDX-License-Identifier: AGPL-3.0-or-later
-- SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-- Guards.idr — Guard placement in level layouts
module Guards

import Primitives
import Types

%default total

||| A guard placed in the game world.
public export
record GuardPlacement where
  constructor MkGuardPlacement
  worldX       : WorldX
  zone         : String
  rank         : GuardRank
  patrolRadius : Double
