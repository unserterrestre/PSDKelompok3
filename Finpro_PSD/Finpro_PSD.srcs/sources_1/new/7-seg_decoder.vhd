--------------------------------------------------------------------------------
-- Module      : seven_seg_decoder
-- File        : 7-seg_decoder.vhd
-- Target      : Digilent Zybo Z7-10 / Digilent Pmod SSD (or discrete 7-seg)
-- Standard    : IEEE VHDL-93 (synthesizable)
-- Description : 4-bit hex/BCD + status character decoder to 7-segment display.
--               Segment bit order: seg_out(6 downto 0) = g, f, e, d, c, b, a
--                 seg_out(0) = a (top)
--                 seg_out(1) = b (upper-right)
--                 seg_out(2) = c (lower-right)
--                 seg_out(3) = d (bottom)
--                 seg_out(4) = e (lower-left)
--                 seg_out(5) = f (upper-left)
--                 seg_out(6) = g (middle)
--               Generic ACTIVE_LOW:
--                 false = Common Cathode / Active-High (default for Pmod SSD)
--                 true  = Common Anode   / Active-Low
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity seven_seg_decoder is
    generic (
        ACTIVE_LOW : boolean := false
    );
    port (
        code_in : in  std_logic_vector(3 downto 0); -- 0..9 + A,U,C,d,E,L
        blank   : in  std_logic;                    -- '1' blanks all segments
        seg_out : out std_logic_vector(6 downto 0)  -- g, f, e, d, c, b, a
    );
end entity seven_seg_decoder;

architecture rtl of seven_seg_decoder is
    signal seg_ah : std_logic_vector(6 downto 0);
begin

    -- Active-high lookup table (gfedcba)
    process(code_in, blank)
    begin
        if blank = '1' then
            seg_ah <= "0000000";
        else
            case code_in is
                when "0000" => seg_ah <= "0111111"; -- 0
                when "0001" => seg_ah <= "0000110"; -- 1
                when "0010" => seg_ah <= "1011011"; -- 2
                when "0011" => seg_ah <= "1001111"; -- 3
                when "0100" => seg_ah <= "1100110"; -- 4
                when "0101" => seg_ah <= "1101101"; -- 5
                when "0110" => seg_ah <= "1111101"; -- 6
                when "0111" => seg_ah <= "0000111"; -- 7
                when "1000" => seg_ah <= "1111111"; -- 8
                when "1001" => seg_ah <= "1101111"; -- 9
                when "1010" => seg_ah <= "1110111"; -- A (Alarm / Attempt)
                when "1011" => seg_ah <= "0111110"; -- U (Unlocked)
                when "1100" => seg_ah <= "0111001"; -- C (Code / Crypto)
                when "1101" => seg_ah <= "1011110"; -- d (Digit)
                when "1110" => seg_ah <= "1111001"; -- E (Error / Entry)
                when "1111" => seg_ah <= "0111000"; -- L (Locked out)
                when others => seg_ah <= "0000000";
            end case;
        end if;
    end process;

    -- Configurable output polarity for Common Cathode (false) vs Common Anode (true)
    seg_out <= not seg_ah when ACTIVE_LOW else seg_ah;

end architecture rtl;
