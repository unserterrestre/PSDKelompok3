--------------------------------------------------------------------------------
-- Testbench   : tb_brankas_top
-- Target      : brankas_top (Digilent Zybo Z7-10 Digital Safe)
-- Standard    : IEEE VHDL-93 (pure VHDL-93; avoids VHDL-2008 std.env/process(all))
-- Description : Self-checking behavioral & timing testbench covering:
--                 1. Global reset & initial state verification
--                 2. Debounce glitch rejection + 0..9->0 wrap + 7-seg/14-seg checks
--                 3. Position advance 0..3 & partial entry clear via btn_relock
--                 4. Invalid BCD XOR key (sw_key > 9) display warning ('E')
--                 5. Valid unlock (password 1234, key 5) & relock back to entry
--                 6. Wrong XOR key & wrong passwords triggering Lockout Tier 1 (2 s)
--                 7. Auto-release after Tier 1 & escalation to Lockout Tier 2 (4 s)
--                 8. Unlock after Tier 2 release + final global reset check
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_brankas_top is
end entity tb_brankas_top;

architecture sim of tb_brankas_top is

    constant CLK_PERIOD       : time     := 8 ns;  -- 125 MHz clock period
    constant TB_CLK_FREQ_HZ   : positive := 100;   -- Scaled clock for fast simulation
    constant TB_DEBOUNCE_MS   : natural  := 1;     -- DB_MAX = 1 in scaled simulation
    constant TB_MAX_RETRIES   : positive := 3;
    constant TB_BASE_LOCK_SEC : positive := 2;     -- Tier 1 = 200 clks, Tier 2 = 400 clks

    -- Expected 7-segment patterns (gfedcba, active-high)
    type seg7_arr_t is array (0 to 9) of std_logic_vector(6 downto 0);
    constant C_SEG7_DIGITS : seg7_arr_t := (
        0 => "0111111",
        1 => "0000110",
        2 => "1011011",
        3 => "1001111",
        4 => "1100110",
        5 => "1101101",
        6 => "1111101",
        7 => "0000111",
        8 => "1111111",
        9 => "1101111"
    );
    constant C_SEG7_U     : std_logic_vector(6 downto 0) := "0111110";
    constant C_SEG7_L     : std_logic_vector(6 downto 0) := "0111000";
    constant C_SEG7_BLANK : std_logic_vector(6 downto 0) := "0000000";

    -- Expected 14-segment patterns (nmlkjihgfedcba, active-high)
    type seg14_arr_t is array (0 to 9) of std_logic_vector(13 downto 0);
    constant C_SEG14_DIGITS : seg14_arr_t := (
        0 => "00110000111111",
        1 => "00010000000110",
        2 => "00000011011011",
        3 => "00000011001111",
        4 => "00000011100110",
        5 => "00000011101101",
        6 => "00000011111101",
        7 => "00000000000111",
        8 => "00000011111111",
        9 => "00000011101111"
    );
    constant C_SEG14_U : std_logic_vector(13 downto 0) := "00000000111110";
    constant C_SEG14_E : std_logic_vector(13 downto 0) := "00000011111001";
    constant C_SEG14_L : std_logic_vector(13 downto 0) := "00000000111000";

    -- DUT signals
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '0';
    signal btn_inc      : std_logic := '0';
    signal btn_next     : std_logic := '0';
    signal btn_relock   : std_logic := '0';
    signal sw_key       : std_logic_vector(3 downto 0) := x"5";
    signal led_pos      : std_logic_vector(3 downto 0);
    signal led_unlocked : std_logic;
    signal led_alarm    : std_logic;
    signal led_entry    : std_logic;
    signal seg7_out     : std_logic_vector(6 downto 0);
    signal seg7_sel     : std_logic;
    signal seg14_out    : std_logic_vector(13 downto 0);
    signal seg14_en     : std_logic;
    signal buzzer_out   : std_logic;

    signal sim_done     : boolean := false;

begin

    -- Unit Under Test
    uut : entity work.brankas_top
        generic map (
            CLK_FREQ_HZ      => TB_CLK_FREQ_HZ,
            DEBOUNCE_MS      => TB_DEBOUNCE_MS,
            MAX_RETRIES      => TB_MAX_RETRIES,
            BASE_LOCKOUT_SEC => TB_BASE_LOCK_SEC,
            DEFAULT_PASSWORD => x"1234",
            DEFAULT_KEY      => x"5",
            SEG7_ACTIVE_LOW  => false,
            SEG14_ACTIVE_LOW => false
        )
        port map (
            clk          => clk,
            rst          => rst,
            btn_inc      => btn_inc,
            btn_next     => btn_next,
            btn_relock   => btn_relock,
            sw_key       => sw_key,
            led_pos      => led_pos,
            led_unlocked => led_unlocked,
            led_alarm    => led_alarm,
            led_entry    => led_entry,
            seg7_out     => seg7_out,
            seg7_sel     => seg7_sel,
            seg14_out    => seg14_out,
            seg14_en     => seg14_en,
            buzzer_out   => buzzer_out
        );

    -- Clock generator (terminates cleanly when sim_done = true)
    clk_gen : process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process clk_gen;

    -- Main test stimulus & verification process
    stim_proc : process

        procedure wait_cycles(n : in natural) is
        begin
            for k in 1 to n loop
                wait until rising_edge(clk);
            end loop;
            wait for 1 ns;
        end procedure wait_cycles;

        -- Debounced button press: 6 cycles high + 6 cycles low = 12 cycles total
        procedure press_btn(signal btn : out std_logic) is
        begin
            btn <= '1';
            wait_cycles(6);
            btn <= '0';
            wait_cycles(6);
        end procedure press_btn;

        -- Enter a single decimal digit 0..9 and press btn_next
        procedure enter_digit(d : in integer range 0 to 9) is
        begin
            for k in 1 to d loop
                press_btn(btn_inc);
            end loop;
            press_btn(btn_next);
        end procedure enter_digit;

        -- Enter a full 4-digit code d0 d1 d2 d3
        procedure enter_code(
            d0 : in integer range 0 to 9;
            d1 : in integer range 0 to 9;
            d2 : in integer range 0 to 9;
            d3 : in integer range 0 to 9
        ) is
        begin
            enter_digit(d0);
            enter_digit(d1);
            enter_digit(d2);
            enter_digit(d3);
        end procedure enter_code;

        -- Wait until 7-segment multiplexer selects target_sel ('0' or '1')
        procedure sync_seg7_sel(target_sel : in std_logic) is
            variable guard : integer := 0;
        begin
            while seg7_sel /= target_sel and guard < 16 loop
                wait until rising_edge(clk);
                wait for 1 ns;
                guard := guard + 1;
            end loop;
            assert seg7_sel = target_sel
                report "Timeout waiting for seg7_sel phase"
                severity failure;
        end procedure sync_seg7_sel;

    begin
        report "=== [TB] Starting tb_brankas_top ===" severity note;

        ------------------------------------------------------------------------
        -- Test 1: Global Reset & Initial Idle State
        ------------------------------------------------------------------------
        rst        <= '1';
        btn_inc    <= '0';
        btn_next   <= '0';
        btn_relock <= '0';
        sw_key     <= x"5";
        wait for CLK_PERIOD * 4;
        wait until rising_edge(clk);
        rst <= '0';
        wait_cycles(4); -- Allow sw_key 2-FF synchronizer to settle

        assert led_entry = '1' and led_unlocked = '0' and led_alarm = '0'
            report "Test 1 FAIL: Unexpected initial mode LEDs after reset"
            severity failure;
        assert buzzer_out = '0'
            report "Test 1 FAIL: Buzzer active after reset"
            severity failure;
        assert led_pos = "0001"
            report "Test 1 FAIL: Expected initial led_pos = 0001"
            severity failure;
        assert seg14_en = '0'
            report "Test 1 FAIL: Expected seg14_en = 0 for active-high config"
            severity failure;
        assert seg14_out = C_SEG14_DIGITS(0)
            report "Test 1 FAIL: Expected initial 14-seg digit '0'"
            severity failure;
        report "Test 1 PASS: Reset & initial state verified." severity note;

        ------------------------------------------------------------------------
        -- Test 2: Debounce Glitch Rejection & Full 0..9 -> 0 Digit Cycle
        ------------------------------------------------------------------------
        -- 1-clock bounce glitch on btn_inc must be ignored (DB_MAX = 1)
        btn_inc <= '1';
        wait_cycles(1);
        btn_inc <= '0';
        wait_cycles(6);
        assert seg14_out = C_SEG14_DIGITS(0)
            report "Test 2 FAIL: Debouncer failed to reject 1-cycle glitch"
            severity failure;

        -- Step through digits 1..9 and verify both 14-seg & 7-seg decoders
        for d in 1 to 9 loop
            press_btn(btn_inc);
            assert seg14_out = C_SEG14_DIGITS(d)
                report "Test 2 FAIL: 14-seg mismatch during 0..9 cycle"
                severity failure;
            sync_seg7_sel('0');
            assert seg7_out = C_SEG7_DIGITS(d)
                report "Test 2 FAIL: 7-seg digit mismatch during 0..9 cycle"
                severity failure;
        end loop;

        -- Wrap 9 -> 0
        press_btn(btn_inc);
        assert seg14_out = C_SEG14_DIGITS(0)
            report "Test 2 FAIL: Digit failed to wrap 9 -> 0"
            severity failure;
        report "Test 2 PASS: Debounce glitch rejection & 0..9->0 wrap verified." severity note;

        ------------------------------------------------------------------------
        -- Test 3: Position Advance 0..3 & Partial Clear via btn_relock
        ------------------------------------------------------------------------
        assert led_pos = "0001" report "Test 3 FAIL: pos 0 expected" severity failure;
        press_btn(btn_inc); -- digit = 1
        press_btn(btn_next);
        assert led_pos = "0010" report "Test 3 FAIL: pos 1 expected" severity failure;
        sync_seg7_sel('1');
        assert seg7_out = C_SEG7_DIGITS(1)
            report "Test 3 FAIL: 7-seg pos indicator expected 1"
            severity failure;

        press_btn(btn_next); -- digit = 0 locked at pos 1 -> advance to pos 2
        assert led_pos = "0100" report "Test 3 FAIL: pos 2 expected" severity failure;
        press_btn(btn_inc); -- digit = 1 at pos 2
        press_btn(btn_next); -- advance to pos 3
        assert led_pos = "1000" report "Test 3 FAIL: pos 3 expected" severity failure;
        sync_seg7_sel('1');
        assert seg7_out = C_SEG7_DIGITS(3)
            report "Test 3 FAIL: 7-seg pos indicator expected 3"
            severity failure;

        -- Clear partial entry back to pos 0 using btn_relock
        press_btn(btn_relock);
        assert led_pos = "0001" and led_entry = '1' and seg14_out = C_SEG14_DIGITS(0)
            report "Test 3 FAIL: btn_relock did not clear partial entry"
            severity failure;
        report "Test 3 PASS: Position tracking 0..3 & partial clear verified." severity note;

        ------------------------------------------------------------------------
        -- Test 4: Invalid BCD XOR Key Warning ('E' on 14-segment)
        ------------------------------------------------------------------------
        sw_key <= x"F"; -- Non-BCD key (> 9)
        wait_cycles(4);
        assert seg14_out = C_SEG14_E
            report "Test 4 FAIL: Expected 'E' on 14-seg for non-BCD sw_key"
            severity failure;
        sw_key <= x"5"; -- Restore valid default key
        wait_cycles(4);
        assert seg14_out = C_SEG14_DIGITS(0)
            report "Test 4 FAIL: 14-seg did not recover after restoring valid key"
            severity failure;
        report "Test 4 PASS: Non-BCD XOR key warning verified." severity note;

        ------------------------------------------------------------------------
        -- Test 5: Valid Password (1234) with Correct Key (5) -> UNLOCKED
        ------------------------------------------------------------------------
        enter_code(1, 2, 3, 4);
        assert led_unlocked = '1' and led_alarm = '0' and led_entry = '0'
            report "Test 5 FAIL: Safe did not unlock on valid password 1234 + key 5"
            severity failure;
        assert led_pos = "1111"
            report "Test 5 FAIL: Expected led_pos = 1111 in unlocked state"
            severity failure;
        assert seg14_out = C_SEG14_U
            report "Test 5 FAIL: Expected 'U' on 14-seg when unlocked"
            severity failure;
        sync_seg7_sel('0');
        assert seg7_out = C_SEG7_U
            report "Test 5 FAIL: Expected 'U' on 7-seg digit 0 when unlocked"
            severity failure;
        sync_seg7_sel('1');
        assert seg7_out = C_SEG7_BLANK
            report "Test 5 FAIL: Expected blank on 7-seg digit 1 when unlocked"
            severity failure;

        -- Buttons btn_inc and btn_next must be ignored while unlocked
        press_btn(btn_inc);
        press_btn(btn_next);
        assert led_unlocked = '1' and led_entry = '0'
            report "Test 5 FAIL: Unlocked state corrupted by btn_inc/btn_next"
            severity failure;
        report "Test 5 PASS: Unlock behavior & display outputs verified." severity note;

        ------------------------------------------------------------------------
        -- Test 6: Relock Back to Entry Mode via btn_relock
        ------------------------------------------------------------------------
        press_btn(btn_relock);
        assert led_unlocked = '0' and led_entry = '1' and led_alarm = '0'
            report "Test 6 FAIL: btn_relock failed to return to entry mode"
            severity failure;
        assert led_pos = "0001" and seg14_out = C_SEG14_DIGITS(0)
            report "Test 6 FAIL: Input state not cleanly reset after relock"
            severity failure;
        report "Test 6 PASS: Relock to entry mode verified." severity note;

        ------------------------------------------------------------------------
        -- Test 7: Wrong XOR Key & Repeated Failures -> Lockout Tier 1 (2 s = 200 clks)
        ------------------------------------------------------------------------
        -- Attempt 1: Correct digits (1234) but WRONG XOR key (3 /= 5)
        sw_key <= x"3";
        wait_cycles(4);
        enter_code(1, 2, 3, 4);
        assert led_unlocked = '0' and led_alarm = '0' and led_entry = '1'
            report "Test 7 FAIL: Wrong XOR key unlocked safe or triggered premature lockout"
            severity failure;

        -- Restore correct key (5), then fail twice more (9999, 0000) -> 3 fails total
        sw_key <= x"5";
        wait_cycles(4);
        enter_code(9, 9, 9, 9); -- Fail 2
        assert led_alarm = '0' and led_entry = '1'
            report "Test 7 FAIL: Premature lockout on fail 2"
            severity failure;

        enter_code(0, 0, 0, 0); -- Fail 3 -> triggers Tier 1 Lockout (200 clks)
        -- Note: enter_code finishes 6 clock cycles after Edge 6 (when led_alarm rose)
        assert led_alarm = '1' and buzzer_out = '1' and led_unlocked = '0' and led_entry = '0'
            report "Test 7 FAIL: Lockout Tier 1 did not activate on 3rd failure"
            severity failure;
        assert led_pos = "0001"
            report "Test 7 FAIL: Expected led_pos = 0001 (Tier 1 bar-graph)"
            severity failure;
        assert seg14_out = C_SEG14_L
            report "Test 7 FAIL: Expected 'L' on 14-seg during lockout"
            severity failure;
        sync_seg7_sel('1');
        assert seg7_out = C_SEG7_L
            report "Test 7 FAIL: Expected 'L' on 7-seg digit 1 during <10s lockout"
            severity failure;

        -- Buttons must be ignored during active lockout (also consumes ~24 clks)
        press_btn(btn_inc);
        press_btn(btn_next);
        assert led_alarm = '1' and led_unlocked = '0'
            report "Test 7 FAIL: Lockout exited early on button press"
            severity failure;

        -- Wait until just before 200 cycles expire (6 release + <=32 mux/btn + 150 = <=188 < 200)
        wait_cycles(150);
        assert led_alarm = '1'
            report "Test 7 FAIL: Tier 1 lockout released too early (< 200 clocks)"
            severity failure;

        -- Wait out remaining cycles past 200 total -> must auto-release
        wait_cycles(25);
        assert led_alarm = '0' and buzzer_out = '0' and led_entry = '1' and led_unlocked = '0'
            report "Test 7 FAIL: Tier 1 lockout did not auto-release after 2 s"
            severity failure;
        assert led_pos = "0001" and seg14_out = C_SEG14_DIGITS(0)
            report "Test 7 FAIL: Entry mode did not cleanly reset after Tier 1 release"
            severity failure;
        report "Test 7 PASS: Wrong key rejection, Tier 1 lockout (2 s) & auto-release verified." severity note;

        ------------------------------------------------------------------------
        -- Test 8: Escalating Lockout Tier 2 (4 s = 400 clks) & Recovery Unlock
        ------------------------------------------------------------------------
        enter_code(1, 1, 1, 1); -- Fail 1 (after Tier 1)
        enter_code(2, 2, 2, 2); -- Fail 2
        enter_code(3, 3, 3, 3); -- Fail 3 -> triggers Tier 2 Lockout (400 clks)

        assert led_alarm = '1' and buzzer_out = '1'
            report "Test 8 FAIL: Tier 2 lockout did not activate"
            severity failure;
        assert led_pos = "0011"
            report "Test 8 FAIL: Expected led_pos = 0011 (Tier 2 bar-graph)"
            severity failure;

        -- After 250 clocks (longer than Tier 1's 200 clocks!), Tier 2 must STILL be locked
        wait_cycles(250);
        assert led_alarm = '1' and led_pos = "0011"
            report "Test 8 FAIL: Tier 2 did not escalate beyond Tier 1 duration"
            severity failure;

        -- Wait remaining ~150 clocks -> must auto-release after 400 clocks total
        wait_cycles(160);
        assert led_alarm = '0' and led_entry = '1' and buzzer_out = '0'
            report "Test 8 FAIL: Tier 2 lockout did not auto-release after 4 s"
            severity failure;

        -- Verify valid unlock succeeds after Tier 2 release (also resets retry & tier)
        enter_code(1, 2, 3, 4);
        assert led_unlocked = '1' and led_alarm = '0'
            report "Test 8 FAIL: Failed to unlock with valid password after lockout release"
            severity failure;

        -- Verify global reset cleanly restores idle state from unlocked
        rst <= '1';
        wait_cycles(4);
        rst <= '0';
        wait_cycles(4);
        assert led_entry = '1' and led_unlocked = '0' and led_alarm = '0' and led_pos = "0001"
            report "Test 8 FAIL: Global reset from unlocked did not restore idle state"
            severity failure;
        report "Test 8 PASS: Tier 2 escalation (4 s), post-lockout unlock & reset verified." severity note;

        report "=== [TB] ALL TESTS PASSED SUCCESSFULLY ===" severity note;
        sim_done <= true;
        wait;
    end process stim_proc;

end architecture sim;
