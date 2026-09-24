package body Greeter is
   function Greeting (Name : String) return String is
   begin
      return "Hello, " & Name & "!";
   end Greeting;
end Greeter;
