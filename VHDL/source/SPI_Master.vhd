------------------------------------------------------------------------------/
-- Description: SPI (Serial Peripheral Interface) Master
--              Creates master based on input configuration.
--              Sends a byte one bit at a time on MOSI
--              Will also receive byte data one bit at a time on MISO.
--              Any data on input byte will be shipped out on MOSI.
--
--              To kick-off transaction, user must pulse i_TX_DV.
--              This module supports multi-byte transmissions by pulsing
--              i_TX_DV and loading up i_TX_Byte when o_TX_Ready is high.
--
--              This module is only responsible for controlling Clk, MOSI, 
--              and MISO.  If the SPI peripheral requires a chip-select, 
--              this must be done at a higher level.
--
-- Note:        i_Clk must be at least 2x faster than i_SPI_Clk
--
-- Generics:    SPI_MODE, can be 0, 1, 2, or 3.  See above.
--              Can be configured in one of 4 modes:
--              Mode | Clock Polarity (CPOL/CKP) | Clock Phase (CPHA)
--               0   |             0             |        0
--               1   |             0             |        1
--               2   |             1             |        0
--               3   |             1             |        1
--              More: https:--en.wikipedia.org/wiki/Serial_Peripheral_Interface_Bus#Mode_numbers
--              CLKS_PER_HALF_BIT - Sets frequency of o_SPI_Clk.  o_SPI_Clk is
--              derived from i_Clk.  Set to integer number of clocks for each
--              half-bit of SPI data.  E.g. 100 MHz i_Clk, CLKS_PER_HALF_BIT = 2
--              would create o_SPI_CLK of 25 MHz.  Must be >= 2
--
------------------------------------------------------------------------------/

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SPI_Master is
  generic (
    SPI_MODE          : integer := 0;
    CLKS_PER_HALF_BIT : integer := 2
    );
  port (
   -- Control/Data Signals,
   i_Rst_L : in std_logic;        -- FPGA Reset
   i_Clk   : in std_logic;        -- FPGA Clock
   
   -- TX (MOSI) Signals
   i_TX_Byte   : in std_logic_vector(7 downto 0);   -- Byte to transmit on MOSI
   i_TX_DV     : in std_logic;          -- Data Valid Pulse with i_TX_Byte
   o_TX_Ready  : out std_logic;         -- Transmit Ready for next byte
   
   -- RX (MISO) Signals
   o_RX_DV   : out std_logic;    -- Data Valid pulse (1 clock cycle)
   o_RX_Byte : out std_logic_vector(7 downto 0);   -- Byte received on MISO

   -- SPI Interface
   o_SPI_Clk  : out std_logic;
   i_SPI_MISO : in  std_logic;
   o_SPI_MOSI : out std_logic
   );
end entity SPI_Master;

architecture RTL of SPI_Master is

  -- SPI Interface (All Runs at SPI Clock Domain)
  signal w_CPOL : std_logic;     -- Clock polarity
  signal w_CPHA : std_logic;     -- Clock phase

  signal r_SPI_Clk_Count : integer range 0 to CLKS_PER_HALF_BIT*2-1;
  signal r_SPI_Clk       : std_logic;
  signal r_SPI_Clk_Edges : integer range 0 to 16;
  signal r_Leading_Edge  : std_logic;
  signal r_Trailing_Edge : std_logic;
  signal r_TX_DV         : std_logic;
  signal r_TX_Byte       : std_logic_vector(7 downto 0);

  signal r_RX_Bit_Count : unsigned(2 downto 0);
  signal r_TX_Bit_Count : unsigned(2 downto 0);

begin

  -- CPOL: Clock Polarity
  -- CPOL=0 means clock idles at 0, leading edge is rising edge.
  -- CPOL=1 means clock idles at 1, leading edge is falling edge.
  w_CPOL <= '1' when (SPI_MODE = 2) or (SPI_MODE = 3) else '0';

  -- CPHA: Clock Phase
  -- CPHA=0 means the "out" side changes the data on trailing edge of clock
  --              the "in" side captures data on leading edge of clock
  -- CPHA=1 means the "out" side changes the data on leading edge of clock
  --              the "in" side captures data on the trailing edge of clock
  w_CPHA <= '1' when (SPI_MODE = 1) or (SPI_MODE = 3) else '0';

  -- Purpose: Generate SPI Clock correct number of times when DV pulse comes
  Edge_Indicator : process (i_Clk, i_Rst_L)
  begin
    if i_Rst_L = '0' then
      o_TX_Ready      <= '0';
      r_SPI_Clk_Edges <= 0;
      r_Leading_Edge  <= '0';
      r_Trailing_Edge <= '0';
      r_SPI_Clk       <= w_CPOL; -- assign default state to idle state
      r_SPI_Clk_Count <= 0;
    elsif rising_edge(i_Clk) then

      -- Default assignments
      r_Leading_Edge  <= '0';
      r_Trailing_Edge <= '0';
      
      if i_TX_DV = '1' then
        o_TX_Ready      <= '0';
        r_SPI_Clk_Edges <= 16;  -- Total # edges in one byte ALWAYS 16
      elsif r_SPI_Clk_Edges > 0 then
        o_TX_Ready <= '0';
        
        if r_SPI_Clk_Count = CLKS_PER_HALF_BIT*2-1 then
          r_SPI_Clk_Edges <= r_SPI_Clk_Edges - 1;
          r_Trailing_Edge <= '1';
          r_SPI_Clk_Count <= 0;
          r_SPI_Clk       <= not r_SPI_Clk;
        elsif r_SPI_Clk_Count = CLKS_PER_HALF_BIT-1 then
          r_SPI_Clk_Edges <= r_SPI_Clk_Edges - 1;
          r_Leading_Edge  <= '1';
          r_SPI_Clk_Count <= r_SPI_Clk_Count + 1;
          r_SPI_Clk       <= not r_SPI_Clk;
        else
          r_SPI_Clk_Count <= r_SPI_Clk_Count + 1;
        end if;
      else
        o_TX_Ready <= '1';
      end if;
    end if;
  end process Edge_Indicator;

         
  -- Purpose: Register i_TX_Byte when Data Valid is pulsed.
  -- Keeps local storage of byte in case higher level module changes the data
  Byte_Reg : process (i_Clk, i_Rst_L)
  begin
    if i_Rst_L = '0' then
      r_TX_Byte <= X"00";
      r_TX_DV   <= '0';
    elsif rising_edge(i_clk) then
      r_TX_DV <= i_TX_DV; -- 1 clock cycle delay
      if i_TX_DV = '1' then
        r_TX_Byte <= i_TX_Byte;
      end if;
    end if;
  end process Byte_Reg;


  -- Purpose: Generate MOSI data
  -- Works with both CPHA=0 and CPHA=1
  MOSI_Data : process (i_Clk, i_Rst_L)
  begin
    if i_Rst_L = '0' then
      o_SPI_MOSI     <= '0';
      r_TX_Bit_Count <= "111";          -- Send MSB first
    elsif rising_edge(i_Clk) then
      -- If ready is high, reset bit counts to default
      if o_TX_Ready = '1' then
        r_TX_Bit_Count <= "111";

      -- Catch the case where we start transaction and CPHA = 0
      elsif (r_TX_DV = '1' and w_CPHA = '0') then
        o_SPI_MOSI     <= r_TX_Byte(7);
        r_TX_Bit_Count <= "110";        -- 6
      elsif (r_Leading_Edge = '1' and w_CPHA = '1') or (r_Trailing_Edge = '1' and w_CPHA = '0') then
        r_TX_Bit_Count <= r_TX_Bit_Count - 1;
        o_SPI_MOSI     <= r_TX_Byte(to_integer(r_TX_Bit_Count));
      end if;
    end if;
  end process MOSI_Data;


  -- Purpose: Read in MISO data.
  MISO_Data : process (i_Clk, i_Rst_L)
  begin
    if i_Rst_L = '0' then
      o_RX_Byte      <= X"00";
      o_RX_DV        <= '0';
      r_RX_Bit_Count <= "111";          -- Starts at 7
    elsif rising_edge(i_Clk) then
      -- Default Assignments
      o_RX_DV <= '0';

      if o_TX_Ready = '1' then -- Check if ready, if so reset count to default
        r_RX_Bit_Count <= "111";        -- Starts at 7
      elsif (r_Leading_Edge = '1' and w_CPHA = '0') or (r_Trailing_Edge = '1' and w_CPHA = '1') then
        o_RX_Byte(to_integer(r_RX_Bit_Count)) <= i_SPI_MISO;  -- Sample data
        r_RX_Bit_Count <= r_RX_Bit_Count - 1;
        if r_RX_Bit_Count = "000" then
          o_RX_DV <= '1';   -- Byte done, pulse Data Valid
        end if;
      end if;
    end if;
  end process MISO_Data;
  
  
  -- Purpose: Add clock delay to signals for alignment.
  SPI_Clock : process (i_Clk, i_Rst_L)
  begin
    if i_Rst_L = '0' then
      o_SPI_Clk  <= w_CPOL;
    elsif rising_edge(i_Clk) then
      o_SPI_Clk <= r_SPI_Clk;
    end if;
  end process SPI_Clock;
  
end architecture RTL;
