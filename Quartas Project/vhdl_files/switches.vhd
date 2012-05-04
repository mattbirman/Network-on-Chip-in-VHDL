-- example slave module
-- writes to this module are ignored
-- read requests are replied to with a read return
-- read return data is based on the switches[7 downto 0] on the DE2 board
-- allows the user to change the behaviour of the network from the outside world

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity switches is
generic(
		node_ID : std_logic_vector(3 downto 0)
		);
port (
	clk     : in std_logic;
	nreset	: in std_logic;
		
	led_output     : out std_logic_vector(7 downto 0);
	
	address			: in std_logic_vector(31 downto 0); -- TODO - currently not implemented
	
	-- write signals (and dest_addr)
	wr_data			: in std_logic_vector(7 downto 0);
	wr				: in std_logic;
	
	-- read request signals (and dest_addr)
	read_request	: in std_logic;	
	
	-- read return signals
	rd_data 		: out std_logic_vector(7 downto 0);
	read_return			: out std_logic;
	
	switches		: in std_logic_vector(7 downto 0)
	
);
end switches;

architecture rtl of switches is
	

begin
	process(clk, wr,switches)
	begin
		if rising_edge(clk) then
			if nreset = '0' then

			else
				-- incoming read request
				if read_request = '1' then

					rd_data <= switches;
					read_return <= '1';
					
				else
					read_return <= '0';
				end if;
			end if;
		end if;
		
	end process;

	led_output <= switches;
	
end rtl;





