--------------------------------------------------------------------------------
-- Module      : fourteen_seg_decoder
-- File        : 14-seg_decoder.vhd
-- Target      : Digilent Zybo Z7-10 (Pmod JC + Pmod JE 14-segment starburst)
-- Standard    : IEEE VHDL-93 (synthesizable)
-- Description : 5-bit character decoder to 14-segment alphanumeric display.
--               Supports digits 0..9, status letters (A, U, C, D, E, L, O, P,
--               N, K, R, S, X, '-'), and blanking.
--
-- Physical 14-Segment Starburst Layout & Bit Mapping:
--
--           aaaaaaaaa
--         f i   j   k b
--         f  i  j  k  b
--         f   i j k   b
--          gggg hhhh      (g = g1 left middle, h = g2 right middle)
--         e   l m n   c
--         e  l  m  n  c
--         e l   m   n c
--           ddddddddd
--
--   seg_out(13 downto 0) = n, m, l, k, j, i, h, g, f, e, d, c, b, a
--     bit  0 (a) : top horizontal           bit  7 (h) : middle-right (g2)
--     bit  1 (b) : upper-right vertical     bit  8 (i) : upper-left diag (\)
--     bit  2 (c) : lower-right vertical     bit  9 (j) : upper-center vert (|)
--     bit  3 (d) : bottom horizontal        bit 10 (k) : upper-right diag (/)
--     bit  4 (e) : lower-left vertical      bit 11 (l) : lower-left diag (/)
--     bit  5 (f) : upper-left vertical      bit 12 (m) : lower-center vert (|)
--     bit  6 (g) : middle-left (g1)         bit 13 (n) : lower-right diag (\)
--
-- Generic ACTIVE_LOW:
--   false = Active-High / Common Cathode (seg_out='1' lights segment)
--   true  = Active-Low  / Common Anode   (seg_out='0' lights segment)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity fourteen_seg_decoder is
    generic (
        ACTIVE_LOW : boolean := false
    );
    port (
        char_code : in  std_logic_vector(4 downto 0);  -- 00000..01001=0..9, 01010..10111=status
        blank     : in  std_logic;                     -- '1' blanks display
        seg_out   : out std_logic_vector(13 downto 0)  -- nmlkjihgfedcba
    );
end entity fourteen_seg_decoder;

architecture rtl of fourteen_seg_decoder is
    signal seg_ah : std_logic_vector(13 downto 0);
begin

    -- Active-high truth table: bit order (13 downto 0) = n m l k j i h g f e d c b a
    process(char_code, blank)
    begin
        if blank = '1' then
            seg_ah <= "00000000000000";
        else
            case char_code is
                -- Digits 0..9
                when "00000" => seg_ah <= "00110000111111"; -- '0' (slashed: a,b,c,d,e,f,k,l)
                when "00001" => seg_ah <= "00010000000110"; -- '1' (with serif: b,c,k)
                when "00010" => seg_ah <= "00000011011011"; -- '2' (a,b,d,e,g,h)
                when "00011" => seg_ah <= "00000011001111"; -- '3' (a,b,c,d,g,h)
                when "00100" => seg_ah <= "00000011100110"; -- '4' (b,c,f,g,h)
                when "00101" => seg_ah <= "00000011101101"; -- '5' (a,c,d,f,g,h)
                when "00110" => seg_ah <= "00000011111101"; -- '6' (a,c,d,e,f,g,h)
                when "00111" => seg_ah <= "00000000000111"; -- '7' (a,b,c)
                when "01000" => seg_ah <= "00000011111111"; -- '8' (a,b,c,d,e,f,g,h)
                when "01001" => seg_ah <= "00000011101111"; -- '9' (a,b,c,d,f,g,h)

                -- Status / Alphanumeric Characters
                when "01010" => seg_ah <= "00000011110111"; -- 'A' (a,b,c,e,f,g,h)
                when "01011" => seg_ah <= "00000000111110"; -- 'U' (b,c,d,e,f)
                when "01100" => seg_ah <= "00000000111001"; -- 'C' (a,d,e,f)
                when "01101" => seg_ah <= "01001000001111"; -- 'D' (a,b,c,d,j,m)
                when "01110" => seg_ah <= "00000011111001"; -- 'E' (a,d,e,f,g,h)
                when "01111" => seg_ah <= "00000000111000"; -- 'L' (d,e,f)
                when "10000" => seg_ah <= "00000000111111"; -- 'O' (a,b,c,d,e,f)
                when "10001" => seg_ah <= "00000011110011"; -- 'P' (a,b,e,f,g,h)
                when "10010" => seg_ah <= "10000100110110"; -- 'N' (b,c,e,f,i,n)
                when "10011" => seg_ah <= "10010001110000"; -- 'K' (e,f,g,k,n)
                when "10100" => seg_ah <= "10000011110011"; -- 'R' (a,b,e,f,g,h,n)
                when "10101" => seg_ah <= "00000011101101"; -- 'S' (a,c,d,f,g,h)
                when "10110" => seg_ah <= "10110100000000"; -- 'X' (i,k,l,n)
                when "10111" => seg_ah <= "00000011000000"; -- '-' (g,h)

                -- Blank / unused codes
                when others  => seg_ah <= "00000000000000";
            end case;
        end if;
    end process;

    -- Configurable polarity: Common Cathode (false) vs Common Anode (true)
    seg_out <= not seg_ah when ACTIVE_LOW else seg_ah;

end architecture rtl;
