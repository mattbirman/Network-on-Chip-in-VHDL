-- top level design entity
-- contains all the nodes - node types are selected in the instantiations
-- connects all of the nodes in a grid using generate loop statements
-- also contains statistics counting and the UART module connection to MATLAB program

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity noc is

port (
	clk     : in std_logic;
	nreset	: in std_logic;
	
	--leds
	led     : out std_logic_vector(7 downto 0);
	ledg	: out std_logic_vector(7 downto 0);
	
	-- uart
	uart_txd 	: out std_logic;
	uart_rxd 	: in std_logic;
	
	test_ledr			: out std_logic_vector(7 downto 0);
	
	switches	: in std_logic_vector(7 downto 0)
	
);
end noc;

architecture rtl of noc is

	component node is
	generic (
		node_type : integer;
		node_ID : std_logic_vector(3 downto 0);
		proc_type : integer
	);

	port (
		clk     : in std_logic;
		nreset	: in std_logic;
		
		--busy signals 		- 0 = local, 1 = north, 2 = east, 3 = south, 4 = west
		busy_in 			: in std_logic_vector(4 downto 1);
		busy_out 		: out std_logic_vector(4 downto 1);
		
		local_busy_in	: out std_logic; --output used for traffic counters - only needed internally otherwise
		local_busy_out	: out std_logic; --output used for traffic counters - only needed internally otherwise
		
		--router packet connections
		north_pkt_in 	: in std_logic_vector(48 downto 0);
		north_pkt_out 	: out std_logic_vector(48 downto 0);
		
		east_pkt_in 	: in std_logic_vector(48 downto 0);
		east_pkt_out 	: out std_logic_vector(48 downto 0);
		
		south_pkt_in 	: in std_logic_vector(48 downto 0);
		south_pkt_out 	: out std_logic_vector(48 downto 0);
		
		west_pkt_in 	: in std_logic_vector(48 downto 0);
		west_pkt_out 	: out std_logic_vector(48 downto 0);
		
		
		led_output	: out std_logic_vector(7 downto 0);
		
		uart_txd 	: out std_logic;
		uart_rxd 	: in std_logic;
		
		test_leds			: out std_logic_vector(7 downto 0);
		
		switches_in		: in std_logic_vector(7 downto 0)
	);
	end component;
	
	component sc_uart is
	generic (addr_bits : integer;
			 clk_freq : integer;
			 baud_rate : integer;
			 txf_depth : integer; txf_thres : integer;
			 rxf_depth : integer; rxf_thres : integer);
	port (
		clk		: in std_logic;
		reset	: in std_logic;
		address		: in std_logic_vector(addr_bits-1 downto 0);
		wr_data		: in std_logic_vector(31 downto 0);
		rd, wr		: in std_logic;
		rd_data		: out std_logic_vector(31 downto 0);
		rdy_cnt		: out unsigned(1 downto 0);

		txd		: out std_logic;
		rxd		: in std_logic;
		ncts	: in std_logic;
		nrts	: out std_logic
		);
	end component;
	
	
	--busy signals
	type busy_array_type is array(integer range 3 downto 0, integer range 3 downto 0) of std_logic_vector(4 downto 1);
	signal busy_in		 	: busy_array_type;
	signal busy_out		 	: busy_array_type;
	
	type local_busy_array_type is array(integer range 3 downto 0, integer range 3 downto 0) of std_logic;
	signal local_busy_in	: local_busy_array_type;
	signal local_busy_out	: local_busy_array_type;
	
	--packet signals
	type packet_array_type is array(integer range 3 downto 0, integer range 3 downto 0) of std_logic_vector(48 downto 0);
	signal north_pkt_in 	: packet_array_type;
	signal north_pkt_out 	: packet_array_type;
	signal east_pkt_in 		: packet_array_type;
	signal east_pkt_out 	: packet_array_type;
	signal south_pkt_in 	: packet_array_type;
	signal south_pkt_out 	: packet_array_type;
	signal west_pkt_in 		: packet_array_type;
	signal west_pkt_out 	: packet_array_type;
	
	signal toggle : std_logic; --debugging
	
	
	--statistics
	signal clock_counter : unsigned(24 downto 0) := (others => '0'); --count clock cycles
	--constant COUNTER_MAX : integer := 126;
	constant COUNTER_MAX : integer := 500;
	type array_counters is array(integer range 1 downto 0, integer range 127 downto 0) of unsigned(7 downto 0); --alternate between the two counter arrays
	signal traffic_counter : array_counters;
	signal current_counter : unsigned(0 downto 0) := "0"; --says which array is currently counter (the other is being sent to uart)
	
	signal write_buffer : unsigned(15 downto 0) := (others => '0'); --current array_counter index being writen to uart
	signal write_buffer_reg : unsigned(15 downto 0) := (others => '0'); --current array_counter index being writen to uart
	
	--uart (statistics)
	signal rdy_cnt		: unsigned(1 downto 0);
	signal wr_data : std_logic_vector(31 downto 0);
	signal rd_data		: std_logic_vector(31 downto 0);
	signal rd : std_logic;
	signal wr : std_logic;
	signal number, numberreg: unsigned(31 downto 0);
	signal addr: std_logic_vector(0 downto 0);
	signal wr_data_reg: std_logic_vector(7 downto 0);

	--write state machine
	type state_type is (POLL_STATE, WRITE_STATE, DELAY_STATE);
	signal state_reg: state_type;
	signal next_state: state_type;

begin


	
	--master
	node_master_inst : node
	generic map(
		node_type 	=> 0, --dummy_proc
		node_ID 	=> "0000",
		proc_type	=> 1
	)

	port map (
		clk     	=> clk,
		nreset		=> nreset,
		
		busy_in 		=> busy_in(0,0),
		busy_out 		=> busy_out(0,0),
		
		local_busy_in	=> local_busy_in(0,0), --output used for traffic counters - only needed internally otherwise
		local_busy_out	=> local_busy_out(0,0), --output used for traffic counters - only needed internally otherwise
		
		north_pkt_in 	=> north_pkt_in(0,0),
		north_pkt_out 	=> north_pkt_out(0,0),
		
		east_pkt_in 	=> east_pkt_in(0,0),
		east_pkt_out 	=> east_pkt_out(0,0),
		
		south_pkt_in 	=> south_pkt_in(0,0),
		south_pkt_out 	=> south_pkt_out(0,0),
		
		west_pkt_in 	=> west_pkt_in(0,0),
		west_pkt_out 	=> west_pkt_out(0,0),
		
		uart_rxd 	=> '0',
		
		
		test_leds			=> open,
		
		switches_in => (others => '0')
	);
	
	--uart slave
	uart_slave_inst : node
	generic map(
		node_type 	=> 1, --slave
		node_ID 	=> "0001",
		proc_type	=> 0 --not used
	)

	port map (
		clk     	=> clk,
		nreset		=> nreset,
		
		busy_in 		=> busy_in(1,0),
		busy_out 		=> busy_out(1,0),
		
		local_busy_in	=> local_busy_in(1,0), --output used for traffic counters - only needed internally otherwise
		local_busy_out	=> local_busy_out(1,0), --output used for traffic counters - only needed internally otherwise
		
		north_pkt_in 	=> north_pkt_in(1,0),
		north_pkt_out 	=> north_pkt_out(1,0),
		
		east_pkt_in 	=> east_pkt_in(1,0),
		east_pkt_out 	=> east_pkt_out(1,0),
		
		south_pkt_in 	=> south_pkt_in(1,0),
		south_pkt_out 	=> south_pkt_out(1,0),
		
		west_pkt_in 	=> west_pkt_in(1,0),
		west_pkt_out 	=> west_pkt_out(1,0),
		
		--uart_txd 	=> uart_txd,
		--uart_rxd 	=> uart_rxd,
		uart_rxd 	=> '0',
		--led_output	=> ledg
		led_output	=> open,
		
		switches_in => (others => '0')
	);
	
	--proc
	router_slave_inst : node
	generic map(
		node_type 	=> 0, --proc
		node_ID 	=> "0101",
		proc_type	=> 0
	)

	port map (
		clk     	=> clk,
		nreset		=> nreset,	
		
		local_busy_in	=> local_busy_in(1,1), --output used for traffic counters - only needed internally otherwise
		local_busy_out	=> local_busy_out(1,1), --output used for traffic counters - only needed internally otherwise
		
		busy_in 		=> busy_in(1,1),
		busy_out 		=> busy_out(1,1),
		
		north_pkt_in 	=> north_pkt_in(1,1),
		north_pkt_out 	=> north_pkt_out(1,1),
		
		east_pkt_in 	=> east_pkt_in(1,1),
		east_pkt_out 	=> east_pkt_out(1,1),
		
		south_pkt_in 	=> south_pkt_in(1,1),
		south_pkt_out 	=> south_pkt_out(1,1),
		
		west_pkt_in 	=> west_pkt_in(1,1),
		west_pkt_out 	=> west_pkt_out(1,1),
		
		uart_rxd 	=> '0',
		
--		test_leds(6 downto 0)			=> test_ledr(6 downto 0),
--		test_leds(7) => open,
		test_leds => open,
		
		switches_in => (others => '0')
	);
	
	--test_ledr(7) <= toggle; 
	
	process(clk,south_pkt_out(1,0))
	begin
		if rising_edge(clk) then
			-- proc_uart is sending a read_request to uart
			if(south_pkt_out(1,0)(40) = '1') then
				toggle <= not toggle;
			end if;
		end if;
	
	end process;
	
	
	--dummy_slave
	mem2_slave_inst : node
	generic map(
		node_type 	=> 1, --dummy_slave
		node_ID 	=> "0100",
		proc_type	=> 0 --not used
	)

	port map (
		clk     	=> clk,
		nreset		=> nreset,	
		
		busy_in 		=> busy_in(0,1),
		busy_out 		=> busy_out(0,1),
		
		local_busy_in	=> local_busy_in(0,1), --output used for traffic counters - only needed internally otherwise
		local_busy_out	=> local_busy_out(0,1), --output used for traffic counters - only needed internally otherwise
		
		north_pkt_in 	=> north_pkt_in(0,1),
		north_pkt_out 	=> north_pkt_out(0,1),
		
		east_pkt_in 	=> east_pkt_in(0,1),
		east_pkt_out 	=> east_pkt_out(0,1),
		
		south_pkt_in 	=> south_pkt_in(0,1),
		south_pkt_out 	=> south_pkt_out(0,1),
		
		west_pkt_in 	=> west_pkt_in(0,1),
		west_pkt_out 	=> west_pkt_out(0,1),
		
		uart_rxd 	=> '0',
		
		led_output	=> led,
		
		switches_in => (others => '0')
	);
	
	
--=======================================================================================
	--fill with routers
		
	--router only
	router1_inst : node
	generic map(
		node_type 	=> 3, --dummy_slave
		node_ID 	=> "0010",
		proc_type => 1 --ignored
	)

	port map (
		clk     	=> clk,
		nreset		=> nreset,	
		
		busy_in 		=> busy_in(2,0),
		busy_out 		=> busy_out(2,0),
		
		local_busy_in	=> local_busy_in(2,0), --output used for traffic counters - only needed internally otherwise
		local_busy_out	=> local_busy_out(2,0), --output used for traffic counters - only needed internally otherwise
		
		north_pkt_in 	=> north_pkt_in(2,0),
		north_pkt_out 	=> north_pkt_out(2,0),
		
		east_pkt_in 	=> east_pkt_in(2,0),
		east_pkt_out 	=> east_pkt_out(2,0),
		
		south_pkt_in 	=> south_pkt_in(2,0),
		south_pkt_out 	=> south_pkt_out(2,0),
		
		west_pkt_in 	=> west_pkt_in(2,0),
		west_pkt_out 	=> west_pkt_out(2,0),
		
		uart_rxd 	=> '0',
		
		led_output	=> open,
		
		switches_in => (others => '0')
	);
	
	--router only
	router2_inst : node
	generic map(
		node_type 	=> 1, --mem
		node_ID 	=> "0011",
		proc_type => 1 --ignored
	)

	port map (
		clk     	=> clk,
		nreset		=> nreset,	
		
		busy_in 		=> busy_in(3,0),
		busy_out 		=> busy_out(3,0),
		
		local_busy_in	=> local_busy_in(3,0), --output used for traffic counters - only needed internally otherwise
		local_busy_out	=> local_busy_out(3,0), --output used for traffic counters - only needed internally otherwise
		
		north_pkt_in 	=> north_pkt_in(3,0),
		north_pkt_out 	=> north_pkt_out(3,0),
		
		east_pkt_in 	=> east_pkt_in(3,0),
		east_pkt_out 	=> east_pkt_out(3,0),
		
		south_pkt_in 	=> south_pkt_in(3,0),
		south_pkt_out 	=> south_pkt_out(3,0),
		
		west_pkt_in 	=> west_pkt_in(3,0),
		west_pkt_out 	=> west_pkt_out(3,0),
		
		uart_rxd 	=> '0',
		
		led_output	=> open,
		
		switches_in => (others => '0')
	);
	--router only
	router3_inst : node
	generic map(
		node_type 	=> 3, --dummy_slave
		node_ID 	=> "0110",
		proc_type => 1 --ignored
	)

	port map (
		clk     	=> clk,
		nreset		=> nreset,	
		
		busy_in 		=> busy_in(2,1),
		busy_out 		=> busy_out(2,1),
		
		local_busy_in	=> local_busy_in(2,1), --output used for traffic counters - only needed internally otherwise
		local_busy_out	=> local_busy_out(2,1), --output used for traffic counters - only needed internally otherwise
		
		north_pkt_in 	=> north_pkt_in(2,1),
		north_pkt_out 	=> north_pkt_out(2,1),
		
		east_pkt_in 	=> east_pkt_in(2,1),
		east_pkt_out 	=> east_pkt_out(2,1),
		
		south_pkt_in 	=> south_pkt_in(2,1),
		south_pkt_out 	=> south_pkt_out(2,1),
		
		west_pkt_in 	=> west_pkt_in(2,1),
		west_pkt_out 	=> west_pkt_out(2,1),
		
		uart_rxd 	=> '0',
		
		led_output	=> open,
		
		switches_in => (others => '0')
	);
	
	--router only
	router4_inst : node
	generic map(
		node_type 	=> 3, --dummy_slave
		node_ID 	=> "0111",
		proc_type => 1 --ignored
	)

	port map (
		clk     	=> clk,
		nreset		=> nreset,	
		
		busy_in 		=> busy_in(3,1),
		busy_out 		=> busy_out(3,1),
		
		local_busy_in	=> local_busy_in(3,1), --output used for traffic counters - only needed internally otherwise
		local_busy_out	=> local_busy_out(3,1), --output used for traffic counters - only needed internally otherwise
		
		north_pkt_in 	=> north_pkt_in(3,1),
		north_pkt_out 	=> north_pkt_out(3,1),
		
		east_pkt_in 	=> east_pkt_in(3,1),
		east_pkt_out 	=> east_pkt_out(3,1),
		
		south_pkt_in 	=> south_pkt_in(3,1),
		south_pkt_out 	=> south_pkt_out(3,1),
		
		west_pkt_in 	=> west_pkt_in(3,1),
		west_pkt_out 	=> west_pkt_out(3,1),
		
		uart_rxd 	=> '0',
		
		led_output	=> open,
		
		switches_in => (others => '0')
	);
	
	--proc
	router5_inst : node
	generic map(
		node_type 	=> 0, --proc
		node_ID 	=> "1000",
		proc_type => 3
	)

	port map (
		clk     	=> clk,
		nreset		=> nreset,	
		
		busy_in 		=> busy_in(0,2),
		busy_out 		=> busy_out(0,2),
		
		local_busy_in	=> local_busy_in(0,2), --output used for traffic counters - only needed internally otherwise
		local_busy_out	=> local_busy_out(0,2), --output used for traffic counters - only needed internally otherwise
		
		north_pkt_in 	=> north_pkt_in(0,2),
		north_pkt_out 	=> north_pkt_out(0,2),
		
		east_pkt_in 	=> east_pkt_in(0,2),
		east_pkt_out 	=> east_pkt_out(0,2),
		
		south_pkt_in 	=> south_pkt_in(0,2),
		south_pkt_out 	=> south_pkt_out(0,2),
		
		west_pkt_in 	=> west_pkt_in(0,2),
		west_pkt_out 	=> west_pkt_out(0,2),
		
		uart_rxd 	=> '0',
		
		--led_output	=> test_ledr(7 downto 0),
		led_output	=> open,
		
		switches_in => (others => '0')
	);
	
	--PROC
	router6_inst : node
	generic map(
		node_type 	=> 0, --dummy_slave
		node_ID 	=> "1001",
		proc_type => 2 --ignored
	)

	port map (
		clk     	=> clk,
		nreset		=> nreset,	
		
		busy_in 		=> busy_in(1,2),
		busy_out 		=> busy_out(1,2),
		
		local_busy_in	=> local_busy_in(1,2), --output used for traffic counters - only needed internally otherwise
		local_busy_out	=> local_busy_out(1,2), --output used for traffic counters - only needed internally otherwise
		
		north_pkt_in 	=> north_pkt_in(1,2),
		north_pkt_out 	=> north_pkt_out(1,2),
		
		east_pkt_in 	=> east_pkt_in(1,2),
		east_pkt_out 	=> east_pkt_out(1,2),
		
		south_pkt_in 	=> south_pkt_in(1,2),
		south_pkt_out 	=> south_pkt_out(1,2),
		
		west_pkt_in 	=> west_pkt_in(1,2),
		west_pkt_out 	=> west_pkt_out(1,2),
		
		uart_rxd 	=> '0',
		
		led_output	=> open,
		
		switches_in => (others => '0')
	);
	
		--router only
	router7_inst : node
	generic map(
		node_type 	=> 3, --dummy_slave
		node_ID 	=> "1010",
		proc_type => 1 --ignored
	)

	port map (
		clk     	=> clk,
		nreset		=> nreset,	
		
		busy_in 		=> busy_in(2,2),
		busy_out 		=> busy_out(2,2),
		
		local_busy_in	=> local_busy_in(2,2), --output used for traffic counters - only needed internally otherwise
		local_busy_out	=> local_busy_out(2,2), --output used for traffic counters - only needed internally otherwise
		
		north_pkt_in 	=> north_pkt_in(2,2),
		north_pkt_out 	=> north_pkt_out(2,2),
		
		east_pkt_in 	=> east_pkt_in(2,2),
		east_pkt_out 	=> east_pkt_out(2,2),
		
		south_pkt_in 	=> south_pkt_in(2,2),
		south_pkt_out 	=> south_pkt_out(2,2),
		
		west_pkt_in 	=> west_pkt_in(2,2),
		west_pkt_out 	=> west_pkt_out(2,2),
		
		uart_rxd 	=> '0',
		
		led_output	=> open,
		
		switches_in => (others => '0')
	);
	
	--router only
	router8_inst : node
	generic map(
		node_type 	=> 3, --dummy_slave
		node_ID 	=> "1011",
		proc_type => 1 --ignored
	)

	port map (
		clk     	=> clk,
		nreset		=> nreset,	
		
		busy_in 		=> busy_in(3,2),
		busy_out 		=> busy_out(3,2),
		
		local_busy_in	=> local_busy_in(3,2), --output used for traffic counters - only needed internally otherwise
		local_busy_out	=> local_busy_out(3,2), --output used for traffic counters - only needed internally otherwise
		
		north_pkt_in 	=> north_pkt_in(3,2),
		north_pkt_out 	=> north_pkt_out(3,2),
		
		east_pkt_in 	=> east_pkt_in(3,2),
		east_pkt_out 	=> east_pkt_out(3,2),
		
		south_pkt_in 	=> south_pkt_in(3,2),
		south_pkt_out 	=> south_pkt_out(3,2),
		
		west_pkt_in 	=> west_pkt_in(3,2),
		west_pkt_out 	=> west_pkt_out(3,2),
		
		uart_rxd 	=> '0',
		
		led_output	=> open,
		
		switches_in => (others => '0')
	);
	
		--switches
	router9_inst : node
	generic map(
		node_type 	=> 4, --switches
		node_ID 	=> "1100",
		proc_type => 1 --ignored
	)

	port map (
		clk     	=> clk,
		nreset		=> nreset,	
		
		busy_in 		=> busy_in(0,3),
		busy_out 		=> busy_out(0,3),
		
		local_busy_in	=> local_busy_in(0,3), --output used for traffic counters - only needed internally otherwise
		local_busy_out	=> local_busy_out(0,3), --output used for traffic counters - only needed internally otherwise
		
		north_pkt_in 	=> north_pkt_in(0,3),
		north_pkt_out 	=> north_pkt_out(0,3),
		
		east_pkt_in 	=> east_pkt_in(0,3),
		east_pkt_out 	=> east_pkt_out(0,3),
		
		south_pkt_in 	=> south_pkt_in(0,3),
		south_pkt_out 	=> south_pkt_out(0,3),
		
		west_pkt_in 	=> west_pkt_in(0,3),
		west_pkt_out 	=> west_pkt_out(0,3),
		
		uart_rxd 	=> '0',
		
		led_output	=> test_ledr,
		
		switches_in => switches
	);
	
	--router only
	router10_inst : node
	generic map(
		node_type 	=> 3, --dummy_slave
		node_ID 	=> "1101",
		proc_type => 1 --ignored
	)

	port map (
		clk     	=> clk,
		nreset		=> nreset,	
		
		busy_in 		=> busy_in(1,3),
		busy_out 		=> busy_out(1,3),
		
		local_busy_in	=> local_busy_in(1,3), --output used for traffic counters - only needed internally otherwise
		local_busy_out	=> local_busy_out(1,3), --output used for traffic counters - only needed internally otherwise
		
		north_pkt_in 	=> north_pkt_in(1,3),
		north_pkt_out 	=> north_pkt_out(1,3),
		
		east_pkt_in 	=> east_pkt_in(1,3),
		east_pkt_out 	=> east_pkt_out(1,3),
		
		south_pkt_in 	=> south_pkt_in(1,3),
		south_pkt_out 	=> south_pkt_out(1,3),
		
		west_pkt_in 	=> west_pkt_in(1,3),
		west_pkt_out 	=> west_pkt_out(1,3),
		
		uart_rxd 	=> '0',
		
		led_output	=> open,
		
		switches_in => (others => '0')
	);
	
		--router only
	router11_inst : node
	generic map(
		node_type 	=> 3, --dummy_slave
		node_ID 	=> "1110",
		proc_type => 1 --ignored
	)

	port map (
		clk     	=> clk,
		nreset		=> nreset,	
		
		busy_in 		=> busy_in(2,3),
		busy_out 		=> busy_out(2,3),
		
		local_busy_in	=> local_busy_in(2,3), --output used for traffic counters - only needed internally otherwise
		local_busy_out	=> local_busy_out(2,3), --output used for traffic counters - only needed internally otherwise
		
		north_pkt_in 	=> north_pkt_in(2,3),
		north_pkt_out 	=> north_pkt_out(2,3),
		
		east_pkt_in 	=> east_pkt_in(2,3),
		east_pkt_out 	=> east_pkt_out(2,3),
		
		south_pkt_in 	=> south_pkt_in(2,3),
		south_pkt_out 	=> south_pkt_out(2,3),
		
		west_pkt_in 	=> west_pkt_in(2,3),
		west_pkt_out 	=> west_pkt_out(2,3),
		
		uart_rxd 	=> '0',
		
		led_output	=> open,
		
		switches_in => (others => '0')
	);
	
	--mem
	router12_inst : node
	generic map(
		node_type 	=> 1, --mem
		node_ID 	=> "1111",
		proc_type => 1 --ignored
	)

	port map (
		clk     	=> clk,
		nreset		=> nreset,	
		
		busy_in 		=> busy_in(3,3),
		busy_out 		=> busy_out(3,3),
		
		local_busy_in	=> local_busy_in(3,3), --output used for traffic counters - only needed internally otherwise
		local_busy_out	=> local_busy_out(3,3), --output used for traffic counters - only needed internally otherwise
		
		north_pkt_in 	=> north_pkt_in(3,3),
		north_pkt_out 	=> north_pkt_out(3,3),
		
		east_pkt_in 	=> east_pkt_in(3,3),
		east_pkt_out 	=> east_pkt_out(3,3),
		
		south_pkt_in 	=> south_pkt_in(3,3),
		south_pkt_out 	=> south_pkt_out(3,3),
		
		west_pkt_in 	=> west_pkt_in(3,3),
		west_pkt_out 	=> west_pkt_out(3,3),
		
		uart_rxd 	=> '0',
		
		led_output	=> open,
		
		switches_in => (others => '0')
	);
--==================================================================================

	--connect packet signals
	EW_y_generate : for j in 0 to 3 generate
		EW_x_generate : for i in 1 to 3 generate
			west_pkt_in(i,j)	<= east_pkt_out(i-1,j);
			busy_in(i,j)(4)		<= busy_out(i-1,j)(2);
			east_pkt_in(i-1,j)	<= west_pkt_out(i,j);
			busy_in(i-1,j)(2)		<= busy_out(i,j)(4);
		end generate;
	end generate;
	
	NS_x_generate : for j in 0 to 3 generate
		NS_y_generate : for i in 1 to 3 generate
			north_pkt_in(j,i)	<= south_pkt_out(j,i-1);
			busy_in(j,i)(1)		<= busy_out(j,i-1)(3);
			south_pkt_in(j,i-1)	<= north_pkt_out(j,i);
			busy_in(j,i-1)(3)		<= busy_out(j,i)(1);
		end generate;
	end generate;



	--statistics
	
	process(clk, current_counter, traffic_counter, north_pkt_out,south_pkt_out,east_pkt_out,west_pkt_out)
	begin
		if rising_edge(clk) then
			if(clock_counter = COUNTER_MAX) then
				clock_counter <= (others => '0');
				
				--clear other counter
				for i in 0 to 127 loop
					traffic_counter(to_integer(1-current_counter),i) <= (others => '0');
				end loop;
				
				--swap counter array
				current_counter <= 1-current_counter;
			else
				--default values
				for i in 0 to 127 loop
					traffic_counter(to_integer(1-current_counter),i) <= traffic_counter(to_integer(1-current_counter),i);
				end loop;
				
				--increment clock_counter
				clock_counter <= clock_counter + 1;
				
				--increment stats counters
				--NS
				for i in 0 to 3 loop         --x
					for j in 0 to 2 loop    --y
						if(north_pkt_out(i,j+1)(42) = '1' or north_pkt_out(i,j+1)(41) = '1' or north_pkt_out(i,j+1)(40) = '1') then
							traffic_counter(to_integer(current_counter),2*(j+3*i)) <= traffic_counter(to_integer(current_counter),2*(j+3*i)) + 1;
						end if;
						if(south_pkt_out(i,j)(42) = '1' or south_pkt_out(i,j)(41) = '1' or south_pkt_out(i,j)(40) = '1') then
							traffic_counter(to_integer(current_counter),2*(j+3*i)+1) <= traffic_counter(to_integer(current_counter),2*(j+3*i)+1) + 1;
						end if;
					end loop;
				end loop;

				--EW
				for i in 0 to 2 loop--x
					for j in 0 to 3 loop    --y
						if(east_pkt_out(i,j)(42) = '1' or east_pkt_out(i,j)(41) = '1' or east_pkt_out(i,j)(40) = '1') then
							traffic_counter(to_integer(current_counter),2*(j+4*i)+24) <= traffic_counter(to_integer(current_counter),2*(j+4*i)+24) + 1;
						end if;
						if(west_pkt_out(i+1,j)(42) = '1' or west_pkt_out(i+1,j)(41) = '1' or west_pkt_out(i+1,j)(40) = '1') then
							traffic_counter(to_integer(current_counter),2*(j+4*i)+25) <= traffic_counter(to_integer(current_counter),2*(j+4*i)+25) + 1;
						end if;
					end loop;
				end loop;
				
				
				--increment busy counters
				--NS busy
				for i in 0 to 3 loop         --x
					for j in 0 to 2 loop    --y
						if(busy_out(i,j+1)(1) = '1') then
							traffic_counter(to_integer(current_counter),2*(j+3*i)+48) <= traffic_counter(to_integer(current_counter),2*(j+3*i)+48) + 1;
						end if;
						if(busy_out(i,j)(3) = '1') then
							traffic_counter(to_integer(current_counter),2*(j+3*i)+49) <= traffic_counter(to_integer(current_counter),2*(j+3*i)+49) + 1;
						end if;
					end loop;
				end loop;

				--EW busy
				for i in 0 to 2 loop--x
					for j in 0 to 3 loop    --y
						if(busy_out(i,j)(2) = '1') then
							traffic_counter(to_integer(current_counter),2*(j+4*i)+72) <= traffic_counter(to_integer(current_counter),2*(j+4*i)+72) + 1;
						end if;
						if(busy_out(i+1,j)(4) = '1') then
							traffic_counter(to_integer(current_counter),2*(j+4*i)+73) <= traffic_counter(to_integer(current_counter),2*(j+4*i)+73) + 1;
						end if;
					end loop;
				end loop;
				
				--local busy 
				for i in 0 to 3 loop--x
					for j in 0 to 3 loop    --y
						if(local_busy_in(i,j) = '1') then
							traffic_counter(to_integer(current_counter),2*(j+4*i)+96) <= traffic_counter(to_integer(current_counter),2*(j+4*i)+96) + 1;
						end if;
						if(local_busy_out(i,j) = '1') then
							traffic_counter(to_integer(current_counter),2*(j+4*i)+97) <= traffic_counter(to_integer(current_counter),2*(j+4*i)+97) + 1;
						end if;
					end loop;
				end loop;
				
			end if;
			
		end if;
	
	end process;
	
	
	-- write to uart
	
	uart2: sc_uart 
	generic map(
		 addr_bits => 1,--addr_bits : integer;
		 clk_freq => 50000000,--clk_freq : integer;
		 baud_rate => 115200, --baud_rate : integer;
		 --baud_rate => 56000, --baud_rate : integer;
		 txf_depth => 128, --txf_depth : integer; txf_thres : integer;
		 rxf_depth => 128, --rxf_depth : integer; rxf_thres : integer);
		 txf_thres => 64, -- : integer;
		 rxf_thres  => 64 --: integer);
	)
	port map (
		clk => clk, 									-- clock
		reset => '0', 									-- reset
		address => addr, 									-- address
		wr_data => wr_data, 									-- wr data
		rd =>rd, 									-- rd
		wr => wr,									--wr
		rd_data => rd_data, 									-- rd data
		rdy_cnt => rdy_cnt, 									--rdy_cnt		: out unsigned(1 downto 0);
		txd => uart_txd,									--txd		: out std_logic;
		rxd =>  uart_rxd,									--rxd		: in std_logic;
		ncts =>'0',									--ncts	: in std_logic;
		nrts =>open										--nrts	: out std_logic
	);
	
	--state register
	process(clk, nreset,next_state,number,write_buffer)
	begin
		if nreset = '0' then
			state_reg<= POLL_STATE;
			numberreg <= "00000000000000000000000000000000";
		elsif rising_edge(clk) then
			state_reg<= next_state;
			numberreg <= number;
			write_buffer_reg <= write_buffer;
		end if;
	end process;
	
	
	ledg <= wr_data(7 downto 0);
	
	--output of state machine
	process(clk, write_buffer_reg, numberreg, state_reg,traffic_counter) 
	begin
		write_buffer <= write_buffer_reg;
		number <= numberreg;
		wr_data <= std_logic_vector(numberreg);
		case state_reg is
			when WRITE_STATE =>

				
				if write_buffer_reg = 150 then
					-- set control bits
					addr <= "1";
					wr <= '1';
					rd <= '0';
					
					
					--reset index
					write_buffer <= (others => '0');
					--terminator character
					number(7 downto 0) <= "00000000";
				else
					if write_buffer_reg < 128 then
						-- set control bits
						addr <= "1";
						wr <= '1';
						rd <= '0';
					
						if traffic_counter(to_integer(1-current_counter),to_integer(write_buffer_reg))>120 then
							--truncate
							number(7 downto 0) <= to_unsigned(121,8);
						else
							number(7 downto 0) <= traffic_counter(to_integer(1-current_counter),to_integer(write_buffer_reg))+to_unsigned(1,8);
						end if;
						--increment index
						write_buffer <= write_buffer_reg + 1;
					else
						--DELAY
						--don't write anything
					
						-- set control bits
						addr <= "1";
						wr <= '0';
						rd <= '0';						
						--increment index
						write_buffer <= write_buffer_reg + 1;
					end if;

				end if;				
				
				-- next state
				next_state <= DELAY_STATE;		
											
			when DELAY_STATE =>
				-- set control bits
				addr <= "0";
				wr <= '0';
				rd <= '1';
				next_state <= POLL_STATE;			
			when POLL_STATE =>
				-- set control bits
				addr <= "0";
				wr <= '0';
				rd <= '1';
				if rd_data(0) = '1' then
					next_state <= WRITE_STATE;
				else
					next_state <= POLL_STATE;
				end if;	
				
		end case;
	end process;
	
end rtl;





