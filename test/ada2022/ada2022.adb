--  A few Ada 2022 features, to make sure the front end really is the version
--  advertised and the Put_Image support in the runtime works.
pragma Ada_2022;
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Fixed;
procedure Ada2022 is
   type Point is record
      X, Y : Integer;
   end record;
   P       : constant Point := (X => 3, Y => 4);
   Img     : constant String := P'Image;
   Squares : constant array (1 .. 5) of Integer := [for I in 1 .. 5 => I * I];
   Total   : Integer := 0;
begin
   for S of Squares loop
      Total := @ + S;
   end loop;
   Put_Line ("total =" & Total'Image);
   Put_Line ((if Ada.Strings.Fixed.Index (Img, "X =>") > 0
              then "record image ok"
              else "record image unexpected: " & Img));
   Put_Line ((declare
                 Fifth : constant Integer := Total / 5;
              begin
                 "declare expression =" & Fifth'Image));
end Ada2022;
