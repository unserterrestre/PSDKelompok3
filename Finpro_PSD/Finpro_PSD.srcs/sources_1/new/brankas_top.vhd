--------------------------------------------------------------------------------
-- Module      : brankas_top
-- Target      : Digilent Zybo Z7-10 (xc7z010clg400-1), 125 MHz clock (K17)
-- Standard    : IEEE VHDL-93 (synthesizable)
-- Description : Top-level structural integration of the Digital Safe (Brankas):
--                 1. input_system         : 2-FF sync, debounced 2-btn + relock input
--                 2. xor_crypto           : 4-digit BCD XOR encryption & match check
--                 3. lockout_controller   : Retry counter & escalating lockout timer
--                 4. seven_seg_decoder    : 2-digit multiplexed 7-segment display (JD)
--                 5. fourteen_seg_decoder : 14-segment alphanumeric display (JC + JE)
--               Single-source-of-truth state: locked_out (from lockout_controller)
--               combined with 1-bit unlocked_r register to avoid FSM desync.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity brankas_top is
    generic (
        CLK_FREQ_HZ      : positive := 125_000_000;
        DEBOUNCE_MS      : natural  := 20;
        MAX_RETRIES      : positive := 3;
        BASE_LOCKOUT_SEC : positive := 5;
        DEFAULT_PASSWORD : std_logic_vector(15 downto 0) := x"1234";
        DEFAULT_KEY      : std_logic_vector(3 downto 0)  := x"5";
        SEG7_ACTIVE_LOW  : boolean := false;
        SEG14_ACTIVE_LOW : boolean := false
    );
    port (
        clk          : in  std_logic;                      -- 125 MHz clock (K17)
        rst          : in  std_logic;                      -- Active-high reset (BTN3)
        btn_inc      : in  std_logic;                      -- Increment digit 0..9 (BTN0)
        btn_next     : in  std_logic;                      -- Lock digit & next pos (BTN1)
        btn_relock   : in  std_logic;                      -- Clear entry / Relock (BTN2)
        sw_key       : in  std_logic_vector(3 downto 0);   -- 1-digit BCD XOR key (SW0..SW3)
        led_pos      : out std_logic_vector(3 downto 0);   -- Position / Tier indicator (LD0..LD3)
        led_unlocked : out std_logic;                      -- RGB LED6 Green: Safe unlocked
        led_alarm    : out std_logic;                      -- RGB LED6 Red: Lockout alarm active
        led_entry    : out std_logic;                      -- RGB LED6 Blue: Input entry active
        seg7_out     : out std_logic_vector(6 downto 0);   -- 7-seg gfedcba (Pmod JD[0..6])
        seg7_sel     : out std_logic;                      -- 7-seg digit mux select (Pmod JD[7])
        seg14_out    : out std_logic_vector(13 downto 0);  -- 14-seg n..a (Pmod JC + JE[0..5])
        seg14_en     : out std_logic;                      -- 14-seg common enable (Pmod JE[6])
        buzzer_out   : out std_logic                       -- Alarm actuator output (Pmod JE[7])
    );
end entity brankas_top;

architecture structural of brankas_top is

    -- Safe 1 kHz refresh counter threshold for 2-digit 7-segment mux
    function calc_mux_max(clk_hz : positive) return natural is
    begin
        if clk_hz >= 1000 then
            return (clk_hz / 1000) - 1;
        else
            return 3; -- Fast toggle in scaled simulation
        end if;
    end function calc_mux_max;

    constant MUX_MAX : natural := calc_mux_max(CLK_FREQ_HZ);

    -- Synchronized slide switches for XOR key
    signal sw_key_sync1 : std_logic_vector(3 downto 0) := (others => '0');
    signal sw_key_sync2 : std_logic_vector(3 downto 0) := (others => '0');

    -- Input system interconnects
    signal input_enable_s : std_logic;
    signal clear_entry_s  : std_logic;
    signal cur_digit_s    : std_logic_vector(3 downto 0);
    signal digit_pos_s    : std_logic_vector(1 downto 0);
    signal entered_code_s : std_logic_vector(15 downto 0);
    signal code_entered_s : std_logic;
    signal relock_pulse_s : std_logic;
    signal entry_active_s : std_logic;

    -- Crypto interconnects
    signal cipher_out_s       : std_logic_vector(15 downto 0);
    signal stored_cipher_s    : std_logic_vector(15 downto 0);
    signal decrypted_stored_s : std_logic_vector(15 downto 0);
    signal key_valid_s        : std_logic;
    signal pwd_valid_bcd_s    : std_logic;
    signal pwd_match_s        : std_logic;

    -- Auth & state registers
    signal unlocked_r     : std_logic := '0';
    signal auth_success_s : std_logic;
    signal auth_fail_s    : std_logic;

    -- Lockout controller interconnects
    signal locked_out_s      : std_logic;
    signal alarm_s           : std_logic;
    signal lockout_done_s    : std_logic;
    signal fail_count_s      : std_logic_vector(2 downto 0);
    signal lockout_tier_s    : std_logic_vector(2 downto 0);
    signal lockout_rem_sec_s : std_logic_vector(7 downto 0);
    signal sec_tick_s        : std_logic;

    -- 7-segment mux & BCD conversion signals
    signal mux_cnt      : integer range 0 to MUX_MAX := 0;
    signal seg7_sel_r   : std_logic := '0';
    signal seg7_code_s  : std_logic_vector(3 downto 0);
    signal seg7_blank_s : std_logic;
    signal rem_sec_int  : integer range 0 to 255;
    signal rem_tens     : std_logic_vector(3 downto 0);
    signal rem_ones     : std_logic_vector(3 downto 0);

    -- 14-segment decoder signals
    signal seg14_char_s  : std_logic_vector(4 downto 0);
    signal seg14_blank_s : std_logic;

begin

    ----------------------------------------------------------------------------
    -- 1. 2-FF Synchronizer for Slide Switch XOR Key
    ----------------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            sw_key_sync1 <= (others => '0');
            sw_key_sync2 <= (others => '0');
        elsif rising_edge(clk) then
            sw_key_sync1 <= sw_key;
            sw_key_sync2 <= sw_key_sync1;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- 2. Single-Source-of-Truth Safe Control & Auth Strobe Generation
    ----------------------------------------------------------------------------
    input_enable_s <= (not locked_out_s) and (not unlocked_r);

    auth_success_s <= '1' when (locked_out_s = '0' and unlocked_r = '0' and
                                code_entered_s = '1' and pwd_match_s = '1')
                      else '0';

    auth_fail_s <= '1' when (locked_out_s = '0' and unlocked_r = '0' and
                             code_entered_s = '1' and pwd_match_s = '0')
                   else '0';

    clear_entry_s <= lockout_done_s or (relock_pulse_s and (not locked_out_s));

    process(clk, rst)
    begin
        if rst = '1' then
            unlocked_r <= '0';
        elsif rising_edge(clk) then
            if locked_out_s = '1' then
                unlocked_r <= '0';
            elsif unlocked_r = '1' and relock_pulse_s = '1' then
                unlocked_r <= '0';
            elsif auth_success_s = '1' then
                unlocked_r <= '1';
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- 3. Submodule Instantiations
    ----------------------------------------------------------------------------
    u_input : entity work.input_system
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ,
            DEBOUNCE_MS => DEBOUNCE_MS
        )
        port map (
            clk          => clk,
            rst          => rst,
            btn_inc      => btn_inc,
            btn_next     => btn_next,
            btn_relock   => btn_relock,
            input_enable => input_enable_s,
            clear_entry  => clear_entry_s,
            cur_digit    => cur_digit_s,
            digit_pos    => digit_pos_s,
            entered_code => entered_code_s,
            code_entered => code_entered_s,
            relock_pulse => relock_pulse_s,
            entry_active => entry_active_s
        );

    u_crypto : entity work.xor_crypto
        generic map (
            DEFAULT_PASSWORD => DEFAULT_PASSWORD,
            DEFAULT_KEY      => DEFAULT_KEY
        )
        port map (
            clk              => clk,
            rst              => rst,
            store_en         => '0',
            plain_in         => entered_code_s,
            key_in           => sw_key_sync2,
            cipher_out       => cipher_out_s,
            stored_cipher    => stored_cipher_s,
            decrypted_stored => decrypted_stored_s,
            key_valid        => key_valid_s,
            pwd_valid_bcd    => pwd_valid_bcd_s,
            match            => pwd_match_s
        );

    u_lockout : entity work.lockout_controller
        generic map (
            CLK_FREQ_HZ      => CLK_FREQ_HZ,
            MAX_RETRIES      => MAX_RETRIES,
            BASE_LOCKOUT_SEC => BASE_LOCKOUT_SEC
        )
        port map (
            clk             => clk,
            rst             => rst,
            auth_fail       => auth_fail_s,
            auth_success    => auth_success_s,
            locked_out      => locked_out_s,
            alarm           => alarm_s,
            lockout_done    => lockout_done_s,
            fail_count      => fail_count_s,
            lockout_tier    => lockout_tier_s,
            lockout_rem_sec => lockout_rem_sec_s,
            sec_tick_out    => sec_tick_s
        );

    u_seg7 : entity work.seven_seg_decoder
        generic map (
            ACTIVE_LOW => SEG7_ACTIVE_LOW
        )
        port map (
            code_in => seg7_code_s,
            blank   => seg7_blank_s,
            seg_out => seg7_out
        );

    u_seg14 : entity work.fourteen_seg_decoder
        generic map (
            ACTIVE_LOW => SEG14_ACTIVE_LOW
        )
        port map (
            char_code => seg14_char_s,
            blank     => seg14_blank_s,
            seg_out   => seg14_out
        );

    ----------------------------------------------------------------------------
    -- 4. 2-Digit 7-Segment Multiplexer & Lockout Countdown BCD Conversion
    ----------------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            mux_cnt    <= 0;
            seg7_sel_r <= '0';
        elsif rising_edge(clk) then
            if mux_cnt < MUX_MAX then
                mux_cnt <= mux_cnt + 1;
            else
                mux_cnt    <= 0;
                seg7_sel_r <= not seg7_sel_r;
            end if;
        end if;
    end process;

    seg7_sel <= seg7_sel_r;

    rem_sec_int <= to_integer(unsigned(lockout_rem_sec_s));

    -- Pure combinational 0..99 BCD split (avoids hardware divider inference)
    process(rem_sec_int)
        variable rem_clamped : integer range 0 to 99;
    begin
        if rem_sec_int > 99 then
            rem_clamped := 99;
        else
            rem_clamped := rem_sec_int;
        end if;

        if rem_clamped >= 90 then
            rem_tens <= x"9";
            rem_ones <= std_logic_vector(to_unsigned(rem_clamped - 90, 4));
        elsif rem_clamped >= 80 then
            rem_tens <= x"8";
            rem_ones <= std_logic_vector(to_unsigned(rem_clamped - 80, 4));
        elsif rem_clamped >= 70 then
            rem_tens <= x"7";
            rem_ones <= std_logic_vector(to_unsigned(rem_clamped - 70, 4));
        elsif rem_clamped >= 60 then
            rem_tens <= x"6";
            rem_ones <= std_logic_vector(to_unsigned(rem_clamped - 60, 4));
        elsif rem_clamped >= 50 then
            rem_tens <= x"5";
            rem_ones <= std_logic_vector(to_unsigned(rem_clamped - 50, 4));
        elsif rem_clamped >= 40 then
            rem_tens <= x"4";
            rem_ones <= std_logic_vector(to_unsigned(rem_clamped - 40, 4));
        elsif rem_clamped >= 30 then
            rem_tens <= x"3";
            rem_ones <= std_logic_vector(to_unsigned(rem_clamped - 30, 4));
        elsif rem_clamped >= 20 then
            rem_tens <= x"2";
            rem_ones <= std_logic_vector(to_unsigned(rem_clamped - 20, 4));
        elsif rem_clamped >= 10 then
            rem_tens <= x"1";
            rem_ones <= std_logic_vector(to_unsigned(rem_clamped - 10, 4));
        else
            rem_tens <= x"0";
            rem_ones <= std_logic_vector(to_unsigned(rem_clamped, 4));
        end if;
    end process;

    process(locked_out_s, unlocked_r, seg7_sel_r, cur_digit_s, digit_pos_s, rem_tens, rem_ones)
    begin
        if locked_out_s = '1' then
            seg7_blank_s <= '0';
            if seg7_sel_r = '0' then
                seg7_code_s <= rem_ones;
            else
                if rem_tens /= x"0" then
                    seg7_code_s <= rem_tens;
                else
                    seg7_code_s <= x"F"; -- 'L' indicator alongside single-digit countdown
                end if;
            end if;
        elsif unlocked_r = '1' then
            if seg7_sel_r = '0' then
                seg7_code_s  <= x"B"; -- 'U'
                seg7_blank_s <= '0';
            else
                seg7_code_s  <= x"0";
                seg7_blank_s <= '1';
            end if;
        else
            seg7_blank_s <= '0';
            if seg7_sel_r = '0' then
                seg7_code_s <= cur_digit_s;
            else
                seg7_code_s <= "00" & digit_pos_s;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- 5. 14-Segment Alphanumeric Display Selection
    ----------------------------------------------------------------------------
    process(locked_out_s, unlocked_r, key_valid_s, cur_digit_s)
    begin
        seg14_blank_s <= '0';
        if locked_out_s = '1' then
            seg14_char_s <= "01111"; -- 'L' (Locked out)
        elsif unlocked_r = '1' then
            seg14_char_s <= "01011"; -- 'U' (Unlocked)
        elsif key_valid_s = '0' then
            seg14_char_s <= "01110"; -- 'E' (Error: sw_key > 9)
        else
            seg14_char_s <= '0' & cur_digit_s; -- Digits '0'..'9'
        end if;
    end process;

    -- Physical common pin: '1' for Common Anode (ACTIVE_LOW=true), '0' for Common Cathode
    seg14_en <= '1' when SEG14_ACTIVE_LOW else '0';

    ----------------------------------------------------------------------------
    -- 6. Status LEDs & Actuator Outputs
    ----------------------------------------------------------------------------
    led_unlocked <= unlocked_r and (not locked_out_s);
    led_alarm    <= locked_out_s;
    led_entry    <= entry_active_s;
    buzzer_out   <= alarm_s;

    process(locked_out_s, unlocked_r, lockout_tier_s, digit_pos_s)
    begin
        if locked_out_s = '1' then
            -- Bar-graph of active lockout escalation tier (1..4)
            case lockout_tier_s is
                when "000"  => led_pos <= "0000";
                when "001"  => led_pos <= "0001"; -- Tier 1
                when "010"  => led_pos <= "0011"; -- Tier 2
                when "011"  => led_pos <= "0111"; -- Tier 3
                when others => led_pos <= "1111"; -- Tier 4+
            end case;
        elsif unlocked_r = '1' then
            led_pos <= "1111";
        else
            -- One-hot digit entry position (0..3)
            case digit_pos_s is
                when "00"   => led_pos <= "0001"; -- Digit 0
                when "01"   => led_pos <= "0010"; -- Digit 1
                when "10"   => led_pos <= "0100"; -- Digit 2
                when others => led_pos <= "1000"; -- Digit 3
            end case;
        end if;
    end process;

end architecture structural;
