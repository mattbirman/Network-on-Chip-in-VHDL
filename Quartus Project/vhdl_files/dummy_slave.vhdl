-- simulates an example slave device
-- contains 8 registers which can be written to and read
-- address bits 27 to 25 indicate which register

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dummy_slave is
generic(
		node_ID : std_logic_vector(3 downto 0)
		);
port (
	clk     : in std_logic;
	nreset	: in std_logic;
		
	led_output     : out std_logic_vector(7 downto 0);
	
	address			: in std_logic_vector(31 downto 0);
	
	-- write signals (and dest_addr)
	wr_data			: in std_logic_vector(7 downto 0);
	wr				: in std_logic;
	
	-- read request signals (and dest_addr)
	read_request	: in std_logic;	
	
	-- read return signals
	rd_data 		: out std_logic_vector(7 downto 0);
	read_return			: out std_logic	

);
end dummy_slave;

architecture rtl of dummy_slave is

	subtype register_led is std_logic_vector(7 downto 0);
	type memory_array is array(integer range 0 to 7) of register_led;
	
	signal register_array: memory_array;	

begin
	process(clk, wr)
	begin
		if rising_edge(clk) then
			if nreset = '0' then
				--register_led <= "00000000";
			else
				if wr = '1' then	
					-- incoming write data			
					register_array(to_integer(unsigned(address(27 downto 25)))) <= wr_data(7 downto 0);
					--register_array(0) <= wr_data(7 downto 0);
					read_return <= '0';
				elsif read_request = '1' then
					-- incoming read request
					rd_data <= register_array(to_integer(unsigned(address(27 downto 25))));
					--rd_data <= register_array(0);
					register_array <= register_array;
					read_return <= '1';
					
				else
					register_array <= register_array;
					read_return <= '0';
				end if;
			end if;
		end if;
		
	end process;

	led_output <= register_array(0);
	--led_output <= reg0;
	--led_output(2 downto 0) <= address(27 downto 25); 
	
end rtl;





