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
            --  enough for disjointness against ALL predecessors.
            if not Disjoint (Zs (I - 1), Zs (I)) then
               return False;
            end if;

            if Zs (I - 1).Tier > Zs (I).Tier then
               return False;
            end if;
         end if;

         pragma Loop_Invariant
           (for all K in Zs'First .. I => Well_Formed (Zs (K)));
         pragma Loop_Invariant
           (for all K in Zs'First .. I =>
              (for all L in Zs'First .. I =>
                 (if K < L then Disjoint (Zs (K), Zs (L)))));
         pragma Loop_Invariant
           (for all K in Zs'First .. I =>
              (for all L in Zs'First .. I =>
                 (if K < L then Zs (K).Tier <= Zs (L).Tier)));
      end loop;

      return True;
   end Zones_Ordered;

end UMS_Zones;
