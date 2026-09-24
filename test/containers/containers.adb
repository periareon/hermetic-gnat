--  Generic instantiation of standard containers and unbounded strings: the
--  adainclude/adalib pair must be complete and consistent.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Containers.Vectors;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
procedure Containers is
   package Int_Vectors is new Ada.Containers.Vectors (Positive, Integer);
   package Sorting is new Int_Vectors.Generic_Sorting;
   package Word_Maps is new Ada.Containers.Indefinite_Ordered_Maps (String, Natural);

   V   : Int_Vectors.Vector;
   M   : Word_Maps.Map;
   S   : Unbounded_String;
   Sum : Integer := 0;
begin
   for I in reverse 1 .. 10 loop
      V.Append (I * I);
   end loop;
   Sorting.Sort (V);
   for X of V loop
      Sum := Sum + X;
   end loop;
   Put_Line ("sum =" & Integer'Image (Sum)
             & ", first =" & Integer'Image (V.First_Element)
             & ", last =" & Integer'Image (V.Last_Element));

   declare
      Text  : constant String := "the quick brown fox jumps over the lazy dog the end";
      Start : Positive := Text'First;
   begin
      for I in Text'Range loop
         if Text (I) = ' ' or else I = Text'Last then
            declare
               Stop : constant Natural := (if Text (I) = ' ' then I - 1 else I);
               Word : constant String := Text (Start .. Stop);
            begin
               if M.Contains (Word) then
                  M.Replace (Word, M.Element (Word) + 1);
               else
                  M.Insert (Word, 1);
               end if;
            end;
            Start := I + 1;
         end if;
      end loop;
   end;
   Put_Line ("words =" & Ada.Containers.Count_Type'Image (M.Length)
             & ", the =" & Natural'Image (M.Element ("the")));
   for C in M.Iterate loop
      Append (S, Word_Maps.Key (C));
      Append (S, ' ');
   end loop;
   Put_Line (To_String (S));
end Containers;
