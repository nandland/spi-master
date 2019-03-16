------------------------------------------------------------------------------/
-- Description:       Simple test bench for SPI Master with CS module
------------------------------------------------------------------------------/

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SPI_Master_With_Single_CS_TB is
end entity SPI_Master_With_Single_CS_TB;

architecture TB of SPI_Master_With_Single_CS_TB is

  constant SPI_MODE : integer := 3;           -- CPOL = 1, CPHA = 1
  constant CLKS_PER_HALF_BIT : integer := 5;  -- 6.25 MHz
  constant MAX_BYTES_PER_CS : integer := 2;   -- 2 bytes per chip select
  constant CS_INACTIVE_CLKS : integer := 10;  -- Adds delay between bytes
  
  signal  r_Rst_L    : std_logic := '0';
  signal  w_SPI_Clk  : std_logic;
  signal  r_Clk      : std_logic := '0';
  signal  w_SPI_CS_n : std_logic;
  signal  w_SPI_MOSI : std_logic;
  
  -- Master Specific
  signal r_Master_TX_Byte  : std_logic_vector(7 downto 0) := X"00";
  signal r_Master_TX_DV    : std_logic := '0';
  signal w_Master_TX_Ready : std_logic;
  signal w_Master_RX_DV    : std_logic;
  signal w_Master_RX_Byte  : std_logic_vector(7 downto 0);
  signal w_Master_RX_Count : std_logic_vector(1 downto 0);
  signal r_Master_TX_Count : std_logic_vector(1 downto 0) := "10";

  -- Sends a single byte from master. 
  procedure SendSingleByte (
    data          : in  std_logic_vector(7 downto 0);
    signal o_data : out std_logic_vector(7 downto 0);
    signal o_dv   : out std_logic) is
  begin
    wait until rising_edge(r_Clk);
    o_data <= data;
    o_dv   <= '1';
    wait until rising_edge(r_Clk);
    o_dv   <= '0';
    wait until rising_edge(w_Master_TX_Ready);
  end procedure SendSingleByte;

begin  -- architecture TB

  -- Clock Generators:
  r_Clk <= not r_Clk after 2 ns;

  -- Instantiate UUT
  UUT : entity work.SPI_Master_With_Single_CS
    generic map (
      SPI_MODE          => SPI_MODE,
      CLKS_PER_HALF_BIT => CLKS_PER_HALF_BIT,
      MAX_BYTES_PER_CS  => MAX_BYTES_PER_CS,
      CS_INACTIVE_CLKS  => CS_INACTIVE_CLKS)
    port map (
      i_Rst_L    => r_Rst_L,
      i_Clk      => r_Clk,
      -- TX (MOSI) Signals
      i_TX_Count => r_Master_TX_Count,  -- Number of bytes per CS         
      i_TX_Byte  => r_Master_TX_Byte,   -- Byte to transmit on MOSI       
      i_TX_DV    => r_Master_TX_DV,     -- Data Valid Pulse with i_TX_Byte
      o_TX_Ready => w_Master_TX_Ready,  -- Transmit Ready for Byte        
      -- RX (MISO) Signals
      o_RX_Count => w_Master_RX_Count,  -- Index of RX'd byte              
      o_RX_DV    => w_Master_RX_DV,     -- Data Valid pulse (1 clock cycle)
      o_RX_Byte  => w_Master_RX_Byte,   -- Byte received on MISO           
      -- SPI Interface
      o_SPI_Clk  => w_SPI_Clk,
      i_SPI_MISO => w_SPI_MOSI,
      o_SPI_MOSI => w_SPI_MOSI,
      o_SPI_CS_n => w_SPI_CS_n
      );

  Testing : process is
  begin
    wait for 100 ns;
    r_Rst_L <= '0';
    wait for 100 ns;
    r_Rst_L <= '1';

    -- Test sending 2 bytes
    SendSingleByte(X"C1", r_Master_TX_Byte, r_Master_TX_DV);
    report "Sent out 0xC1, Received 0x" & to_hstring(unsigned(w_Master_RX_Byte));
    SendSingleByte(X"C2", r_Master_TX_Byte, r_Master_TX_DV);
    report "Sent out 0xC2, Received 0x" & to_hstring(unsigned(w_Master_RX_Byte)); 
    wait for 100 ns;
    assert false report "Test Complete" severity failure;
  end process Testing;

end architecture TB;  
