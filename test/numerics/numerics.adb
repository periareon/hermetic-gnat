--  Elementary functions and Float_IO: libm linkage and the numerics runtime.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Numerics;
with Ada.Numerics.Generic_Elementary_Functions;
procedure Numerics is
   package F   is new Ada.Numerics.Generic_Elementary_Functions (Long_Float);
   package LIO is new Ada.Text_IO.Float_IO (Long_Float);
begin
   LIO.Put (F.Sqrt (2.0), Fore => 1, Aft => 6, Exp => 0);
   New_Line;
   LIO.Put (F.Exp (1.0), Fore => 1, Aft => 6, Exp => 0);
   New_Line;
   LIO.Put (F.Log (F.Exp (2.0)), Fore => 1, Aft => 6, Exp => 0);
   New_Line;
   Put_Line ("pi =" & Integer'Image (Integer (Ada.Numerics.Pi * 1000.0)));
end Numerics;
