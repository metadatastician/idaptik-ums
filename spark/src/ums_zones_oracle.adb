--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
--
--  ums_zones_oracle — evaluates UMS_Zones.Zones_Ordered over a vector table.
--
--  Deliberately NOT SPARK_Mode: it does I/O, and its job is to expose the
--  proved function to the parity harness. The proved surface is UMS_Zones;
--  this is a thin driver so `just spark-parity` can drive the SAME vectors
--  through the Ada model and through crates/ums-ai-edit's Rust mirror and
--  diff the verdicts.
--
--  Input: one case per line, on stdin.
--     empty                       -- the zero-zone case
--     start,end,tier;start,end,tier;...
--  Blank lines and lines beginning '#' are ignored.
--  Output: "true" or "false" per case, one per line.

with Ada.Text_IO;         use Ada.Text_IO;
with Ada.Strings.Fixed;   use Ada.Strings.Fixed;
with UMS_Zones;           use UMS_Zones;

procedure UMS_Zones_Oracle is

   function Field (S : String; N : Positive) return String is
      Start : Natural := S'First;
      Count : Positive := 1;
   begin
      for I in S'Range loop
         if S (I) = ',' then
            if Count = N then
               return S (Start .. I - 1);
            end if;
            Count := Count + 1;
            Start := I + 1;
         end if;
      end loop;
      if Count = N then
         return S (Start .. S'Last);
      end if;
      return "";
   end Field;

   --  Sort by Start_X, because Zones_Ordered's precondition requires it and
   --  the engine sorts too.
   procedure Sort (Zs : in out Zone_Array) is
      Tmp : Zone;
   begin
      for I in Zs'Range loop
         for J in Zs'Range loop
            if J < Zs'Last and then Zs (J).Start_X > Zs (J + 1).Start_X then
               Tmp := Zs (J);
               Zs (J) := Zs (J + 1);
               Zs (J + 1) := Tmp;
            end if;
         end loop;
      end loop;
   end Sort;

begin
   while not End_Of_File loop
      declare
         Line_In : constant String := Trim (Get_Line, Ada.Strings.Both);
      begin
         if Line_In'Length = 0 or else Line_In (Line_In'First) = '#' then
            null;
         elsif Line_In = "empty" then
            declare
               Empty : Zone_Array (1 .. 0);
            begin
               Put_Line (Boolean'Image (Zones_Ordered (Empty)));
            end;
         else
            declare
               N : Natural := 1;
            begin
               for C of Line_In loop
                  if C = ';' then
                     N := N + 1;
                  end if;
               end loop;

               declare
                  Zs    : Zone_Array (1 .. Zone_Index (N));
                  Start : Natural := Line_In'First;
                  Idx   : Positive := 1;
               begin
                  for I in Line_In'First .. Line_In'Last + 1 loop
                     if I > Line_In'Last or else Line_In (I) = ';' then
                        declare
                           Part : constant String := Line_In (Start .. I - 1);
                        begin
                           Zs (Zone_Index (Idx)) :=
                             (Start_X => World_Coord'Value (Field (Part, 1)),
                              End_X   => World_Coord'Value (Field (Part, 2)),
                              Tier    => Security_Tier'Value (Field (Part, 3)));
                        end;
                        Idx := Idx + 1;
                        Start := I + 1;
                     end if;
                  end loop;

                  Sort (Zs);
                  Put_Line (Boolean'Image (Zones_Ordered (Zs)));
               end;
            end;
         end if;
      end;
   end loop;
end UMS_Zones_Oracle;
