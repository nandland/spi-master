------------------------------------------------------------------------------/
-- Description:       Simple test bench for SPI Master module
------------------------------------------------------------------------------/
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SPI_Master_TB is
end entity SPI_Master_TB;

architecture TB of SPI_Master_TB is

  constant SPI_MODE : integer := 3; -- CPOL = 1, CPHA = 1
  constant CLKS_PER_HALF_BIT : integer := 4;  -- 6.25 MHz
  
  signal r_Rst_L    : std_logic := '0';
  signal w_SPI_Clk  : std_logic;
  signal r_Clk      : std_logic := '0';
  signal w_SPI_MOSI : std_logic;
  
  -- Master Specific
  signal r_Master_TX_Byte  : std_logic_vector(7 downto 0) := X"00";
  signal r_Master_TX_DV    : std_logic := '0';
  signal r_Master_CS_n     : std_logic := '1';
  signal w_Master_TX_Ready : std_logic;
  signal r_Master_RX_DV    : std_logic := '0';
  signal r_Master_RX_Byte  : std_logic_vector(7 downto 0) := X"00";
  
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

  -- Instantiate Master
  UUT : entity work.SPI_Master
    generic map (
      SPI_MODE          => SPI_MODE,
      CLKS_PER_HALF_BIT => CLKS_PER_HALF_BIT)
    port map (
      -- Control/Data Signals,
      i_Rst_L    => r_Rst_L,            -- FPGA Reset
      i_Clk      => r_Clk,              -- FPGA Clock
      -- TX (MOSI) Signals
      i_TX_Byte  => r_Master_TX_Byte,          -- Byte to transmit
      i_TX_DV    => r_Master_TX_DV,            -- Data Valid pulse
      o_TX_Ready => w_Master_TX_Ready,         -- Transmit Ready for Byte
      -- RX (MISO) Signals
      o_RX_DV    => r_Master_RX_DV,            -- Data Valid pulse
      o_RX_Byte  => r_Master_RX_Byte,          -- Byte received on MISO
      -- SPI Interface
      o_SPI_Clk  => w_SPI_Clk, 
      i_SPI_MISO => w_SPI_MOSI,
      o_SPI_MOSI => w_SPI_MOSI
      );
      
  Testing : process is
  begin
    wait for 100 ns;
    r_Rst_L <= '0';
    wait for 100 ns;
    r_Rst_L <= '1';
    
    -- Test single byte
    SendSingleByte(X"C1", r_Master_TX_Byte, r_Master_TX_DV);
    report "Sent out 0xC1, Received 0x" & to_hstring(unsigned(r_Master_RX_Byte));
      
    -- Test double byte
    SendSingleByte(X"BE", r_Master_TX_Byte, r_Master_TX_DV);
    report "Sent out 0xBE, Received 0x" & to_hstring(unsigned(r_Master_RX_Byte));

    SendSingleByte(X"EF", r_Master_TX_Byte, r_Master_TX_DV);
    report "Sent out 0xEF, Received 0x" & to_hstring(unsigned(r_Master_RX_Byte));
    wait for 50 ns;
    assert false report "Test Complete" severity failure;
  end process Testing;

end architecture TB;
