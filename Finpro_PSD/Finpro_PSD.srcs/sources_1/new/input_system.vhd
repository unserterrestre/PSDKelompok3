library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity password_2btn is
    generic (
        CLK_FREQ_HZ : integer := 100_000_000; -- 100 MHz (Basys 3) or 50 MHz (DE10-Lite)
        DEBOUNCE_MS : integer := 20;
        SECRET_CODE : std_logic_vector(15 downto 0) := x"1234"
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        btn_inc   : in  std_logic;                    -- Cycles current digit 0..9
        btn_next  : in  std_logic;                    -- Locks current digit & advances
        cur_digit : out integer range 0 to 9;         -- Live digit for 7-segment display
        digit_pos : out integer range 0 to 3;         -- Active digit index (0=1st .. 3=4th)
        unlocked  : out std_logic;
        alarm     : out std_logic
    );
end entity;

architecture rtl of password_2btn is
    constant DB_MAX : integer := (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

    type state_t is (S_ENTRY, S_UNLOCKED, S_LOCKED);
    signal state : state_t := S_ENTRY;

    -- Synchronizer, debouncer, and edge signals for btn_inc
    signal inc_sync  : std_logic_vector(1 downto 0) := (others => '0');
    signal inc_cnt   : integer range 0 to DB_MAX := 0;
    signal inc_clean : std_logic := '0';
    signal inc_prev  : std_logic := '0';
    signal inc_pulse : std_logic;

    -- Synchronizer, debouncer, and edge signals for btn_next
    signal nxt_sync  : std_logic_vector(1 downto 0) := (others => '0');
    signal nxt_cnt   : integer range 0 to DB_MAX := 0;
    signal nxt_clean : std_logic := '0';
    signal nxt_prev  : std_logic := '0';
    signal nxt_pulse : std_logic;

    -- Password datapath signals
    signal digit_val : integer range 0 to 9 := 0;
    signal pos_idx   : integer range 0 to 3 := 0;
    signal entered   : std_logic_vector(15 downto 0) := (others => '0');

    function int_to_bcd(val : integer range 0 to 9) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(val, 4));
    end function;
begin

    -- Single-clock rising-edge pulses from debounced buttons
    inc_pulse <= '1' when (inc_clean = '1' and inc_prev = '0') else '0';
    nxt_pulse <= '1' when (nxt_clean = '1' and nxt_prev = '0') else '0';

    cur_digit <= digit_val;
    digit_pos <= pos_idx;

    process(clk, rst)
        variable next_code : std_logic_vector(15 downto 0);
    begin
        if rst = '1' then
            state     <= S_ENTRY;
            inc_sync  <= (others => '0');
            inc_cnt   <= 0;
            inc_clean <= '0';
            inc_prev  <= '0';
            nxt_sync  <= (others => '0');
            nxt_cnt   <= 0;
            nxt_clean <= '0';
            nxt_prev  <= '0';
            digit_val <= 0;
            pos_idx   <= 0;
            entered   <= (others => '0');
            unlocked  <= '0';
            alarm     <= '0';
        elsif rising_edge(clk) then
            -- 1. Debounce btn_inc
            inc_sync <= inc_sync(0) & btn_inc;
            if inc_sync(1) /= inc_clean then
                if inc_cnt < DB_MAX then
                    inc_cnt <= inc_cnt + 1;
                else
                    inc_clean <= inc_sync(1);
                    inc_cnt   <= 0;
                end if;
            else
                inc_cnt <= 0;
            end if;
            inc_prev <= inc_clean;

            -- 2. Debounce btn_next
            nxt_sync <= nxt_sync(0) & btn_next;
            if nxt_sync(1) /= nxt_clean then
                if nxt_cnt < DB_MAX then
                    nxt_cnt <= nxt_cnt + 1;
                else
                    nxt_clean <= nxt_sync(1);
                    nxt_cnt   <= 0;
                end if;
            else
                nxt_cnt <= 0;
            end if;
            nxt_prev <= nxt_clean;

            -- 3. Password entry and verification state logic
            case state is
                when S_ENTRY =>
                    unlocked <= '0';
                    alarm    <= '0';

                    if inc_pulse = '1' then
                        if digit_val = 9 then
                            digit_val <= 0;
                        else
                            digit_val <= digit_val + 1;
                        end if;
                    end if;

                    if nxt_pulse = '1' then
                        next_code := entered;
                        case pos_idx is
                            when 0 => next_code(15 downto 12) := int_to_bcd(digit_val);
                            when 1 => next_code(11 downto 8)  := int_to_bcd(digit_val);
                            when 2 => next_code(7 downto 4)   := int_to_bcd(digit_val);
                            when 3 => next_code(3 downto 0)    := int_to_bcd(digit_val);
                        end case;
                        entered <= next_code;

                        if pos_idx < 3 then
                            pos_idx   <= pos_idx + 1;
                            digit_val <= 0; -- Start next digit at 0
                        else
                            if next_code = SECRET_CODE then
                                state    <= S_UNLOCKED;
                                unlocked <= '1';
                            else
                                state <= S_LOCKED;
                                alarm <= '1';
                            end if;
                        end if;
                    end if;

                when S_UNLOCKED =>
                    unlocked <= '1';
                    alarm    <= '0';

                when S_LOCKED =>
                    unlocked <= '0';
                    alarm    <= '1';
            end case;
        end if;
    end process;

end architecture;