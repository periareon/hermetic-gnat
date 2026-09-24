--  Tasks, a protected object, rendezvous and delays: libgnarl and the
--  platform thread library.
with Ada.Text_IO; use Ada.Text_IO;
procedure Tasking is
   protected Counter is
      procedure Increment;
      function Value return Natural;
   private
      Count : Natural := 0;
   end Counter;

   protected body Counter is
      procedure Increment is
      begin
         Count := Count + 1;
      end Increment;
      function Value return Natural is
      begin
         return Count;
      end Value;
   end Counter;

   task type Worker is
      entry Start (Iterations : Positive);
   end Worker;

   task body Worker is
      N : Positive;
   begin
      accept Start (Iterations : Positive) do
         N := Iterations;
      end Start;
      for I in 1 .. N loop
         Counter.Increment;
         if I mod 250 = 0 then
            delay 0.001;
         end if;
      end loop;
   end Worker;
begin
   declare
      Workers : array (1 .. 4) of Worker;
   begin
      for W of Workers loop
         W.Start (1000);
      end loop;
   end;  --  block completion waits for all workers
   Put_Line ("Counter =" & Natural'Image (Counter.Value));
   Put_Line ("tasking ok");
end Tasking;
