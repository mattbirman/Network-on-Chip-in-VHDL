-- provides the interface between a slave device and a router
-- builds a packet based on the signals from the master device
-- decodes a packet coming from the router
-- x/y counter are calculated here
--
-- incomplete : NA should probably have buffers

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity na_slave is
generic (
	node_ID		 		: std_logic_vector(3 downto 0)
);

port (
	clk					: in std_logic;
	nreset				: in std_logic;
	
	--With Router
	packet_data_in		: in std_logic_vector(48 downto 0);
	router_not_rdy		: in std_logic; 								-- router is busy
	packet_data_out 	: out std_logic_vector(48 downto 0);	-- packet sent to router
	na_not_rdy			: out std_logic;								-- network adapter is busy

	--With Slave
	slave_not_rdy		: in std_logic;								-- memory is busy
	read_return			: in std_logic;
	read_data			: in std_logic_vector(7 downto 0);
	address 				: out std_logic_vector(31 downto 0);
	write_en				: out std_logic;
	write_data		 	: out std_logic_vector(7 downto 0);
	read_request 		: out std_logic
);
end na_slave;



architecture rtl of na_slave is
	signal y_count, x_count			: std_logic_vector(1 downto 0);
	signal y_diff, x_diff			: integer;
	signal y_neg, x_neg				: std_logic;
	signal read_dest : std_logic_vector(3 downto 0);

begin

	y_diff <= TO_INTEGER(unsigned(read_dest(3 downto 2))) - TO_INTEGER(unsigned(node_ID(3 downto 2)));
	x_diff <= TO_INTEGER(unsigned(read_dest(1 downto 0))) - TO_INTEGER(unsigned(node_ID(1 downto 0)));
	y_neg <= '1' when TO_INTEGER(unsigned((read_dest(3 downto 2)))) < TO_INTEGER(unsigned(node_ID(3 downto 2))) else '0'; --check direction
	y_count <= std_logic_vector(TO_UNSIGNED((-y_diff), 2)) when y_neg = '1' else std_logic_vector(TO_UNSIGNED((y_diff), 2));
	x_neg <= '1' when TO_INTEGER(unsigned(read_dest(1 downto 0))) < TO_INTEGER(unsigned(node_ID(1 downto 0))) else '0';
	x_count <= std_logic_vector(TO_UNSIGNED((-x_diff), 2)) when x_neg = '1' else std_logic_vector(TO_UNSIGNED((x_diff), 2));

	process(clk)
	begin
		
		if rising_edge(clk) then 
			
			if (slave_not_rdy = '1') then
				na_not_rdy <= '1';
			else
				na_not_rdy <= '0';
				
				if (packet_data_in(42) = '1') then								-- receive read request packet
					address 			<= packet_data_in(39 downto 8);
					read_request 	<= '1';
					write_en 		<= '0';
					write_data 		<=	(others => '0');
					
					read_dest 		<= packet_data_in(7 downto 4);
				elsif (packet_data_in(41) = '1') then							-- receive write packet
					address 			<= packet_data_in(39 downto 8);
					read_request 	<= '0';
					write_en 		<= '1';
					write_data 		<= packet_data_in(7 downto 0);
				-- elsif (packet_data_out(42 downto 40) = "000") then		-- receive zero packet
				else	
					address 			<= (others => '0');
					read_request 	<= '0';
					write_en 		<= '0';
					write_data 		<= (others => '0');
				end if;
				
				if (read_return = '1') then
					packet_data_out(48 downto 43) 	<= (y_neg & y_count & x_neg & x_count); 	-- x/y router map position
					packet_data_out(42)					<= '0';
					packet_data_out(41)					<= '0';
					packet_data_out(40)					<= '1';
					packet_data_out(39 downto 36)		<= read_dest;
					packet_data_out(35 downto 28)		<= read_data;
				else
					packet_data_out(48 downto 0) <= (others => '0');
				end if;
			
			end if;
		
		end if;
	end process;
end rtl;
	