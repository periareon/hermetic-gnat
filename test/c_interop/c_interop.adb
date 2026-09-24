--  Calls into C compiled by the same toolchain and into the C library.
with Ada.Text_IO; use Ada.Text_IO;
with Interfaces.C; use Interfaces.C;
with Interfaces.C.Strings; use Interfaces.C.Strings;
procedure C_Interop is
   function PA_Add (A, B : int) return int
     with Import, Convention => C, External_Name => "pa_add";
   function PA_Greeting return chars_ptr
     with Import, Convention => C, External_Name => "pa_greeting";
   function PA_Length (S : chars_ptr) return size_t
     with Import, Convention => C, External_Name => "pa_length";
   function C_Strlen (S : chars_ptr) return size_t
     with Import, Convention => C, External_Name => "strlen";

   Msg : chars_ptr := New_String ("portable");
begin
   Put_Line ("add =" & int'Image (PA_Add (40, 2)));
   Put_Line ("greeting = " & Value (PA_Greeting));
   Put_Line ("length =" & size_t'Image (PA_Length (Msg)) & size_t'Image (C_Strlen (Msg)));
   Free (Msg);
end C_Interop;
