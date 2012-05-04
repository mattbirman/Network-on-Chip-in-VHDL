
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity led_output is

port (
	clk     : in std_logic;
	led     : out std_logic_vector(7 downto 0);
	nreset	: in std_logic;
	
	led_input : in std_logic_vector(7 downto 0)
	
);
end led_output;

architecture rtl of led_output is



begin
	
	led <= led_input;
	
end rtl;





