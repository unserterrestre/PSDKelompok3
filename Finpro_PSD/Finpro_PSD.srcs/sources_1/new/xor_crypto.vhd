--------------------------------------------------------------------------------
-- Module      : xor_crypto
-- Target      : Digilent Zybo Z7-10 (xc7z010clg400-1)
-- Standard    : IEEE VHDL-93 (synthesizable)
-- Description : Deterministic per-digit 4-bit BCD XOR encryption & verification.
--               Uses a 1-digit BCD key (key_in, bits [3:0]) repeated across
--               each 4-bit BCD digit nibble ([15:12], [11:8], [7:4], [3:0]):
--                 cipher[i]    = plain[i] XOR key_in
--                 decrypted[i] = stored_cipher[i] XOR key_in
--               Stores only ciphertext in stored_cipher_r (never plaintext).
--               Default: DEFAULT_PASSWORD = x"1234", DEFAULT_KEY = x"5"
--                        -> INIT_CIPHER = x"4761".
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity xor_crypto is
    generic (
        DEFAULT_PASSWORD : std_logic_vector(15 downto 0) := x"1234";
        DEFAULT_KEY      : std_logic_vector(3 downto 0)  := x"5"
    );
    port (
        clk              : in  std_logic;
        rst              : in  std_logic;
        store_en         : in  std_logic; -- '1' encrypts & stores plain_in with key_in
        plain_in         : in  std_logic_vector(15 downto 0); -- 4-digit BCD input
        key_in           : in  std_logic_vector(3 downto 0);  -- 1-digit BCD key (0..9)
        cipher_out       : out std_logic_vector(15 downto 0); -- Combinational XOR(plain_in, key)
        stored_cipher    : out std_logic_vector(15 downto 0); -- Registered ciphertext
        decrypted_stored : out std_logic_vector(15 downto 0); -- Combinational XOR(stored, key)
        key_valid        : out std_logic;                     -- '1' when key_in in 0..9
        pwd_valid_bcd    : out std_logic;                     -- '1' when all 4 nibbles in 0..9
        match            : out std_logic                      -- '1' on valid BCD & cipher match
    );
end entity xor_crypto;

architecture rtl of xor_crypto is

    -- Deterministic nibble-by-nibble XOR across 4 BCD digits
    function xor_4digit(
        data16 : std_logic_vector(15 downto 0);
        key4   : std_logic_vector(3 downto 0)
    ) return std_logic_vector is
        variable res : std_logic_vector(15 downto 0);
    begin
        res(15 downto 12) := data16(15 downto 12) xor key4; -- Digit 0 (pos 0)
        res(11 downto 8)  := data16(11 downto 8)  xor key4; -- Digit 1 (pos 1)
        res(7 downto 4)   := data16(7 downto 4)   xor key4; -- Digit 2 (pos 2)
        res(3 downto 0)   := data16(3 downto 0)   xor key4; -- Digit 3 (pos 3)
        return res;
    end function xor_4digit;

    -- Validate single 4-bit nibble is a legal decimal BCD digit (0..9)
    function is_bcd_digit(d4 : std_logic_vector(3 downto 0)) return std_logic is
    begin
        if unsigned(d4) <= 9 then
            return '1';
        else
            return '0';
        end if;
    end function is_bcd_digit;

    -- Pre-encrypted ciphertext constant (for x"1234" XOR x"5", INIT_CIPHER = x"4761")
    constant INIT_CIPHER : std_logic_vector(15 downto 0) :=
        xor_4digit(DEFAULT_PASSWORD, DEFAULT_KEY);

    signal stored_cipher_r : std_logic_vector(15 downto 0) := INIT_CIPHER;
    signal cipher_comb     : std_logic_vector(15 downto 0);
    signal decrypted_comb  : std_logic_vector(15 downto 0);
    signal key_valid_s     : std_logic;
    signal pwd_valid_s     : std_logic;

begin

    -- Combinational encryption & decryption paths (0-cycle deterministic latency)
    cipher_comb    <= xor_4digit(plain_in, key_in);
    decrypted_comb <= xor_4digit(stored_cipher_r, key_in);

    -- BCD range checks for key and all 4 password nibbles
    key_valid_s <= is_bcd_digit(key_in);
    pwd_valid_s <= is_bcd_digit(plain_in(15 downto 12)) and
                   is_bcd_digit(plain_in(11 downto 8))  and
                   is_bcd_digit(plain_in(7 downto 4))   and
                   is_bcd_digit(plain_in(3 downto 0));

    -- Output assignments
    cipher_out       <= cipher_comb;
    stored_cipher    <= stored_cipher_r;
    decrypted_stored <= decrypted_comb;
    key_valid        <= key_valid_s;
    pwd_valid_bcd    <= pwd_valid_s;

    -- Verification succeeds only when key & password are valid BCD and ciphertext matches
    match <= '1' when (key_valid_s = '1' and pwd_valid_s = '1' and cipher_comb = stored_cipher_r)
             else '0';

    -- Registered ciphertext storage (reset directly to pre-encrypted constant)
    process(clk, rst)
    begin
        if rst = '1' then
            stored_cipher_r <= INIT_CIPHER;
        elsif rising_edge(clk) then
            if store_en = '1' and key_valid_s = '1' and pwd_valid_s = '1' then
                stored_cipher_r <= cipher_comb;
            end if;
        end if;
    end process;

end architecture rtl;
