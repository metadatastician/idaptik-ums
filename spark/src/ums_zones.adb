--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
--
--  The adjacent-pair sweep, and the loop invariants that make it provably
--  equivalent to the quadratic specification in the spec file.

package body UMS_Zones with
  SPARK_Mode => On
is

   function Zones_Ordered (Zs : Zone_Array) return Boolean is
   begin
      if Zs'Length = 0 then
         --  Vacuously ordered: all three universally-quantified properties
         --  hold over an empty range.
         return True;
      end if;

      for I in Zs'Range loop
         if not Well_Formed (Zs (I)) then
            return False;
         end if;

         if I > Zs'First then
            --  The array is start-sorted (precondition), so the only way an
            --  interval can meet an earlier one is by starting before that
            --  one ended. Checking the immediate predecessor is therefore
            --  enough against ALL predecessors.
            --
            --  Directional, not symmetric Disjoint: see the note on Disjoint
            --  in the spec. This is the comparison the engine makes.
            if Zs (I - 1).End_X > Zs (I).Start_X then
               return False;
            end if;

            if Zs (I - 1).Tier > Zs (I).Tier then
               return False;
            end if;
         end if;

         pragma Loop_Invariant
           (for all K in Zs'First .. I => Well_Formed (Zs (K)));

         --  The chain that makes the linear sweep sufficient.
         --
         --  Stated as `<=` on coordinates rather than as Disjoint: the array
         --  is start-sorted, so an interval ending before the current one
         --  starts also ends before every LATER one starts. That is plain
         --  integer transitivity. Phrased as Disjoint it would instead be a
         --  case split through an `or else` on every pair, which is what the
         --  prover could not discharge (medium: "loop invariant might not be
         --  preserved by an arbitrary iteration").
         pragma Loop_Invariant
           (for all K in Zs'First .. I - 1 => Zs (K).End_X <= Zs (I).Start_X);
         pragma Loop_Invariant
           (for all K in Zs'First .. I =>
              (for all L in Zs'First .. I =>
                 (if K < L then Zs (K).End_X <= Zs (L).Start_X)));
         pragma Loop_Invariant
           (for all K in Zs'First .. I =>
              (for all L in Zs'First .. I =>
                 (if K < L then Zs (K).Tier <= Zs (L).Tier)));
      end loop;

      return True;
   end Zones_Ordered;

end UMS_Zones;
