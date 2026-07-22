--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
--
--  UMS_Zones — the decidable half of the ZonesOrdered validity proof.
--
--  ADR-0003 §3. miniKanren cannot live under SPARK: dynamic terms, heap
--  substitutions and lazily interleaved streams sit badly with SPARK's
--  pointer and recursion restrictions. But one of the six validity proofs IS
--  decidable and pointer-free — zone geometry — and that half is stated here
--  as contracts and discharged by gnatprove.
--
--  This is a PROVED REFERENCE MODEL. It is not linked into the engine at
--  runtime; `crates/ums-ai-edit/src/constraints.rs` mirrors it, and
--  `just spark-parity` drives the same vector table through both so they
--  cannot diverge silently. Runtime linkage was considered and rejected for
--  now: it would add a second FFI lane beside the Zig one and split the
--  unified constraints-as-goals search into in-process and out-of-process
--  halves.
--
--  FIDELITY GAP, stated rather than hidden: the engine's worldX coordinates
--  are JSON numbers, so they may be fractional. This model is over INTEGER
--  coordinates. The arithmetic being proved — ordering, disjointness,
--  monotonicity — is the same, and the parity harness therefore drives
--  integer vectors only. A fractional counterexample would not be caught by
--  this model. Widening to fixed-point is possible and is not done here.

package UMS_Zones with
  SPARK_Mode => On
is

   --  Bounded so every arithmetic comparison is provably overflow-free.
   --  The game's worldX values are level-scale, far inside this range.
   type World_Coord is range -1_000_000 .. 1_000_000;

   --  The archive ABI's securityTier is a non-negative integer.
   type Security_Tier is range 0 .. 255;

   type Zone is record
      Start_X : World_Coord;
      End_X   : World_Coord;
      Tier    : Security_Tier;
   end record;

   Max_Zones : constant := 256;

   type Zone_Count is range 0 .. Max_Zones;
   subtype Zone_Index is Zone_Count range 1 .. Max_Zones;

   type Zone_Array is array (Zone_Index range <>) of Zone;

   ---------------------------------------------------------------------------
   --  The three properties, each expressible and each checkable
   ---------------------------------------------------------------------------

   --  An interval is well formed when it does not run backwards. The engine
   --  admits a degenerate zone (Start = End); so does this.
   function Well_Formed (Z : Zone) return Boolean is
     (Z.Start_X <= Z.End_X);

   --  Symmetric disjointness, under half-open [Start, End) semantics.
   --  Touching at an endpoint is allowed: zones abut.
   --
   --  NOT what the engine decides, and the difference is real. Take
   --  [0, 10] followed by the degenerate [0, 0]: under half-open semantics
   --  [0, 0) is empty, so this predicate calls them disjoint. The engine
   --  rejects it — a start-sorted sweep asks whether each zone starts at or
   --  after the previous one ENDED, and 0 < 10. Kept as a documented
   --  contrast, because writing the specification with this symmetric form
   --  is what made the loop invariant unprovable: it was false.
   function Disjoint (A, B : Zone) return Boolean is
     (A.End_X <= B.Start_X or else B.End_X <= A.Start_X);

   --  The engine sorts by Start_X before checking. The model requires the
   --  caller to have done so, which is what makes the pairwise check
   --  sufficient: for a start-sorted array, checking each adjacent pair
   --  implies pairwise disjointness across the whole array.
   function Sorted_By_Start (Zs : Zone_Array) return Boolean is
     (for all I in Zs'Range =>
        (for all J in Zs'Range =>
           (if I < J then Zs (I).Start_X <= Zs (J).Start_X)));

   --  Deeper into the building is at least as hardened.
   function Tiers_Non_Decreasing (Zs : Zone_Array) return Boolean is
     (for all I in Zs'Range =>
        (for all J in Zs'Range =>
           (if I < J then Zs (I).Tier <= Zs (J).Tier)));

   function All_Well_Formed (Zs : Zone_Array) return Boolean is
     (for all I in Zs'Range => Well_Formed (Zs (I)));

   --  What a start-sorted sweep actually decides: every earlier interval
   --  ends at or before every later one starts. Directional, so it is a
   --  chain of integer <= rather than a case split on each pair, and it
   --  matches the engine exactly, degenerate intervals included.
   function Ordered_Non_Overlapping (Zs : Zone_Array) return Boolean is
     (for all I in Zs'Range =>
        (for all J in Zs'Range =>
           (if I < J then Zs (I).End_X <= Zs (J).Start_X)));

   ---------------------------------------------------------------------------
   --  The decision procedure
   ---------------------------------------------------------------------------

   --  ZonesOrdered: every interval is well formed, no two overlap, and
   --  security tiers do not decrease with depth.
   --
   --  The postcondition is the specification. gnatprove discharges that the
   --  implementation below — a single adjacent-pair sweep — decides exactly
   --  this predicate, which is the whole point of the model: the cheap sweep
   --  the engine runs is proved equivalent to the quadratic statement of what
   --  it is supposed to mean.
   function Zones_Ordered (Zs : Zone_Array) return Boolean with
     Pre  => Sorted_By_Start (Zs),
     Post => Zones_Ordered'Result =
               (All_Well_Formed (Zs)
                and then Ordered_Non_Overlapping (Zs)
                and then Tiers_Non_Decreasing (Zs));

end UMS_Zones;
