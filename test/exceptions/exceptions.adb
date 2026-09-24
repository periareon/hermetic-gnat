--  Zero-cost exception propagation through nested frames, a run-time check
--  failure, and re-raising: the unwinder and libgcc_eh.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Exceptions; use Ada.Exceptions;
with Ada.Command_Line;
procedure Exceptions is
   Custom_Error : exception;

   procedure Deep (Level : Natural) is
   begin
      if Level = 0 then
         raise Custom_Error with "raised at depth zero";
      end if;
      Deep (Level - 1);
   end Deep;

   type Small is array (1 .. 3) of Integer;
   Data    : Small := (1, 2, 3);
   --  Not static, so the index check happens at run time.
   Idx     : constant Integer := 5 + Ada.Command_Line.Argument_Count;
   Handled : Natural := 0;
begin
   begin
      Deep (10);
   exception
      when E : Custom_Error =>
         Put_Line ("caught " & Exception_Name (E) & ": " & Exception_Message (E));
         Handled := Handled + 1;
   end;

   begin
      Data (Idx) := 0;
      Put_Line ("index check missing" & Integer'Image (Data (1)));
   exception
      when Constraint_Error =>
         Put_Line ("caught Constraint_Error");
         Handled := Handled + 1;
   end;

   begin
      begin
         raise Program_Error with "inner";
      exception
         when E : others =>
            Raise_Exception (Exception_Identity (E), "re-raised: " & Exception_Message (E));
      end;
   exception
      when E : Program_Error =>
         Put_Line ("caught " & Exception_Message (E));
         Handled := Handled + 1;
   end;

   Put_Line ("handled" & Natural'Image (Handled));
end Exceptions;
