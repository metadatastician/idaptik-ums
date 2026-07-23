-- SPDX-License-Identifier: AGPL-3.0-or-later
-- SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-- Dogs.idr — Security dog placement
module Dogs

import Primitives
import Types

%default total

||| A security dog placed in the game world.
public export
record DogPlacement where
  constructor MkDogPlacement
  worldX       : WorldX
  breed        : DogBreed
  patrolRadius : Double
