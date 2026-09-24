--  Smallest possible program with a separately compiled unit: exercises the
--  spec/body/ALI flow that rules_ada drives.
with Ada.Text_IO; use Ada.Text_IO;
with Greeter;
procedure Hello is
begin
   Put_Line (Greeter.Greeting ("portable-ada"));
end Hello;
