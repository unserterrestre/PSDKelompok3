--------------------------------------------------------------------------------
-- Module      : input_system
-- Target      : Digilent Zybo Z7-10 (xc7z010clg400-1), 125 MHz system clock
-- Standard    : IEEE VHDL-93 (synthesizable)
-- Description : 2-FF synchronizer, saturating debouncer, and single-clock
--               rising-edge detector for btn_inc, btn_next, and btn_relock.
--               Handles 4-digit BCD entry (0..9 per digit, pos 0..3) and
--               emits a 1-clock code_entered strobe upon latching digit 3.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity input_system is
    generic (
        CLK_FREQ_HZ : positive := 125_000_000; -- Zybo Z7-10 default 125 MHz
        DEBOUNCE_MS : natural  := 20           -- Debounce window in milliseconds
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;          -- Active-high asynchronous reset
        btn_inc      : in  std_logic;          -- Cycle active digit 0..9
        btn_next     : in  std_logic;          -- Lock digit & advance pos 0..3
        btn_relock   : in  std_logic;          -- Clear entry / relock request
        input_enable : in  std_logic;          -- '1' allows digit entry; '0' blocks
        clear_entry  : in  std_logic;          -- Sync clear of current entry buffer
        cur_digit    : out std_logic_vector(3 downto 0);  -- Live BCD digit (0..9)
        digit_pos    : out std_logic_vector(1 downto 0);  -- Active position ("00".."11")
        entered_code : out std_logic_vector(15 downto 0); -- [15:12]=d0 .. [3:0]=d3
        code_entered : out std_logic;          -- 1-clock strobe on 4th digit lock
        relock_pulse : out std_logic;          -- 1-clock debounced rising-edge pulse
        entry_active : out std_logic           -- Status mirror of input_enable
    );
end entity input_system;

architecture rtl of input_system is

    -- Safe debounce threshold calculation preventing 32-bit signed integer overflow
    -- (avoids CLK_FREQ_HZ * DEBOUNCE_MS when CLK_FREQ_HZ = 125_000_000)
    function calc_db_max(clk_hz : positive; db_ms : natural) return natural is
    begin
        if db_ms = 0 then
            return 0;
        elsif clk_hz >= 1000 then
            return (clk_hz / 1000) * db_ms;
        else
            return 1;
        end if;
    end function calc_db_max;

    constant DB_MAX : natural := calc_db_max(CLK_FREQ_HZ, DEBOUNCE_MS);

    -- Channel indices: 0 = btn_inc, 1 = btn_next, 2 = btn_relock
    type sync_arr_t   is array (0 to 2) of std_logic_vector(1 downto 0);
    type db_cnt_arr_t is array (0 to 2) of integer range 0 to DB_MAX;

    signal btn_raw   : std_logic_vector(2 downto 0);
    signal btn_sync  : sync_arr_t   := (others => (others => '0'));
    signal btn_cnt   : db_cnt_arr_t := (others => 0);
    signal btn_clean : std_logic_vector(2 downto 0) := (others => '0');
    signal btn_prev  : std_logic_vector(2 downto 0) := (others => '0');
    signal btn_pulse : std_logic_vector(2 downto 0);

    signal inc_pulse : std_logic;
    signal nxt_pulse : std_logic;
    signal rlk_pulse : std_logic;

    -- Entry datapath registers
    signal digit_val      : integer range 0 to 9 := 0;
    signal pos_idx        : integer range 0 to 3 := 0;
    signal entered_reg    : std_logic_vector(15 downto 0) := (others => '0');
    signal code_entered_r : std_logic := '0';

begin

    -- Map input buttons into uniform 3-channel vector
    btn_raw <= btn_relock & btn_next & btn_inc;

    -- Single-clock rising-edge pulses from debounced button states
    btn_pulse <= btn_clean and (not btn_prev);
    inc_pulse <= btn_pulse(0);
    nxt_pulse <= btn_pulse(1);
    rlk_pulse <= btn_pulse(2);

    -- Output assignments (read back via internal registers for VHDL-93 compatibility)
    cur_digit    <= std_logic_vector(to_unsigned(digit_val, 4));
    digit_pos    <= std_logic_vector(to_unsigned(pos_idx, 2));
    entered_code <= entered_reg;
    code_entered <= code_entered_r;
    relock_pulse <= rlk_pulse;
    entry_active <= input_enable;

    process(clk, rst)
        variable next_code : std_logic_vector(15 downto 0);
        variable digit_bcd : std_logic_vector(3 downto 0);
    begin
        if rst = '1' then
            btn_sync       <= (others => (others => '0'));
            btn_cnt        <= (others => 0);
            btn_clean      <= (others => '0');
            btn_prev       <= (others => '0');
            digit_val      <= 0;
            pos_idx        <= 0;
            entered_reg    <= (others => '0');
            code_entered_r <= '0';

        elsif rising_edge(clk) then
            -- 1. Always update 2-FF synchronizers, debouncers, and edge memories
            --    regardless of input_enable so button releases never cause glitches
            for i in 0 to 2 loop
                btn_sync(i) <= btn_sync(i)(0) & btn_raw(i);
                if btn_sync(i)(1) /= btn_clean(i) then
                    if btn_cnt(i) < DB_MAX then
                        btn_cnt(i) <= btn_cnt(i) + 1;
                    else
                        btn_clean(i) <= btn_sync(i)(1);
                        btn_cnt(i)   <= 0;
                    end if;
                else
                    btn_cnt(i) <= 0;
                end if;
                btn_prev(i) <= btn_clean(i);
            end loop;

            -- Default single-cycle strobe
            code_entered_r <= '0';

            -- 2. Digit entry & position FSM
            if clear_entry = '1' then
                digit_val      <= 0;
                pos_idx        <= 0;
                entered_reg    <= (others => '0');
                code_entered_r <= '0';

            elsif input_enable = '1' then
                if nxt_pulse = '1' then
                    digit_bcd := std_logic_vector(to_unsigned(digit_val, 4));
                    next_code := entered_reg;
                    case pos_idx is
                        when 0 => next_code(15 downto 12) := digit_bcd;
                        when 1 => next_code(11 downto 8)  := digit_bcd;
                        when 2 => next_code(7 downto 4)   := digit_bcd;
                        when 3 => next_code(3 downto 0)   := digit_bcd;
                    end case;
                    entered_reg <= next_code;

                    if pos_idx < 3 then
                        pos_idx   <= pos_idx + 1;
                        digit_val <= 0;
                    else
                        pos_idx        <= 0;
                        digit_val      <= 0;
                        code_entered_r <= '1';
                    end if;

                elsif inc_pulse = '1' then
                    if digit_val = 9 then
                        digit_val <= 0;
                    else
                        digit_val <= digit_val + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
