-- provides the interface between a master IP core and a router
-- builds a packet based on the signals from the master device
-- decodes a packet coming from the router
-- x/y counter are calculated here
--
-- incomplete : NA should probably have buffers

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity na_master is
generic (
	node_ID		 		: std_logic_vector(3 downto 0)
);

port (
	clk					: in std_logic;
	nreset				: in std_logic;
	
	--With Router
	busy					: in std_logic;											-- busy signal from the router
	packet_data_in		: in std_logic_vector(48 downto 0);					-- packet received from router
	packet_data_out 	: out std_logic_vector(48 downto 0);				-- packet sent to router
	
	--With Master
	address 				: in std_logic_vector(31 downto 0);
	write_en				: in std_logic;
	write_data		 	: in std_logic_vector(7 downto 0);
	read_request 		: in std_logic;
	not_ready			: out std_logic;
	read_return			: out std_logic;
	read_data			: out std_logic_vector(7 downto 0)
	
	
);
end na_master;



architecture rtl of na_master is

signal y_count, x_count			: std_logic_vector(1 downto 0);
signal y_diff, x_diff			: integer;
signal y_neg, x_neg				: std_logic;
signal navigation					: std_logic_vector(5 downto 0);

begin

y_diff <= TO_INTEGER(unsigned(address(31 downto 30))) - TO_INTEGER(unsigned(node_ID(3 downto 2)));
x_diff <= TO_INTEGER(unsigned(address(29 downto 28))) - TO_INTEGER(unsigned(node_ID(1 downto 0)));
y_neg <= '1' when TO_INTEGER(unsigned(address(31 downto 30))) < TO_INTEGER(unsigned(node_ID(3 downto 2))) else '0'; --check direction
y_count <= std_logic_vector(TO_UNSIGNED((-y_diff), 2)) when y_neg = '1' else std_logic_vector(TO_UNSIGNED((y_diff), 2));
x_neg <= '1' when TO_INTEGER(unsigned(address(29 downto 28))) < TO_INTEGER(unsigned(node_ID(1 downto 0))) else '0';
x_count <= std_logic_vector(TO_UNSIGNED((-x_diff), 2)) when x_neg = '1' else std_logic_vector(TO_UNSIGNED((x_diff), 2));
 
	process(clk)
	begin
		if rising_edge(clk) then 
			if (busy = '1') then
				not_ready <= '1';
			else
				not_ready <= '0';
				if (write_en = '1') then
					-- write from master
					packet_data_out(48 downto 43) 	<= (y_neg & y_count & x_neg & x_count); 				-- x/y router map position
					packet_data_out(42)					<= '0';
					packet_data_out(41)					<= '1';
					packet_data_out(40)					<= '0';
					packet_data_out(39 downto 8)		<= address;
					packet_data_out(7 downto 0)		<= write_data;
				elsif (read_request = '1') then
					-- read_request from master
					packet_data_out(48 downto 43) 	<= (y_neg & y_count & x_neg & x_count); 				-- x/y router map position
					packet_data_out(42)					<= '1';
					packet_data_out(41)					<= '0';
					packet_data_out(40)					<= '0';
					packet_data_out(39 downto 8)		<= address;
					packet_data_out(7 downto 4)		<= node_ID;
					packet_data_out(3 downto 0)		<= (others => '0');
				else
					--idle
					packet_data_out(42 downto 40) 	<= (others => '0');
				end if;
				
				if (packet_data_in(40) = '1') then
					--read return from router
					read_data						<= packet_data_in(35 downto 28);
					read_return						<= '1';
				else 
					--idle
					read_return 					<= '0';
				end if;
			end if;
		end if;
	end process;
	
	
	
	
end rtl;
