--------------------------------------------------------------------------------
-- Module      : lockout_controller
-- Target      : Digilent Zybo Z7-10 (xc7z010clg400-1), 125 MHz system clock
-- Standard    : IEEE VHDL-93 (synthesizable)
-- Description : Tracks consecutive failed authentication attempts and enforces
--               escalating time-based lockout using a 1-second clock prescaler
--               (0 to CLK_FREQ_HZ - 1) and an 8-bit countdown register (0..255 s)
--               to avoid 32-bit integer overflow at 125 MHz.
--               Default escalation (BASE_LOCKOUT_SEC = 5):
--                 Tier 1:  5 s -> Tier 2: 10 s -> Tier 3: 20 s -> Tier 4+: 40 s
--               Auto-releases back to input mode when countdown reaches 0, and
--               resets retry + escalation tier counters upon auth_success.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lockout_controller is
    generic (
        CLK_FREQ_HZ      : positive := 125_000_000; -- System clock frequency in Hz
        MAX_RETRIES      : positive := 3;           -- Wrong attempts before lockout
        BASE_LOCKOUT_SEC : positive := 5            -- Tier 1 lockout duration (s)
    );
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;                    -- Active-high async reset
        auth_fail       : in  std_logic;                    -- 1-clock fail pulse
        auth_success    : in  std_logic;                    -- 1-clock success pulse
        locked_out      : out std_logic;                    -- '1' while locked out
        alarm           : out std_logic;                    -- '1' while locked out
        lockout_done    : out std_logic;                    -- 1-clock strobe on auto-release
        fail_count      : out std_logic_vector(2 downto 0); -- 0..MAX_RETRIES (clamped 7)
        lockout_tier    : out std_logic_vector(2 downto 0); -- 0=none, 1..4=escalation tier
        lockout_rem_sec : out std_logic_vector(7 downto 0); -- Remaining seconds (0..255)
        sec_tick_out    : out std_logic                     -- 1-clock tick every 1 s in lockout
    );
end entity lockout_controller;

architecture rtl of lockout_controller is

    -- Compute escalating lockout duration in seconds, clamped to 8-bit range (255)
    function tier_duration_sec(
        tier     : natural;
        base_sec : positive
    ) return natural is
        variable mult : natural;
        variable dur  : natural;
    begin
        case tier is
            when 0      => mult := 1;
            when 1      => mult := 2;
            when 2      => mult := 4;
            when others => mult := 8;
        end case;

        if base_sec >= 255 then
            return 255;
        else
            dur := base_sec * mult;
            if dur > 255 then
                return 255;
            else
                return dur;
            end if;
        end if;
    end function tier_duration_sec;

    function clamp_fail_cnt(val : natural) return natural is
    begin
        if val > 7 then
            return 7;
        else
            return val;
        end if;
    end function clamp_fail_cnt;

    signal is_locked      : std_logic := '0';
    signal fail_cnt       : integer range 0 to 7 := 0;
    signal tier_cnt       : integer range 0 to 4 := 0;
    signal sec_rem        : integer range 0 to 255 := 0;
    signal clk_cnt        : integer range 0 to CLK_FREQ_HZ - 1 := 0;
    signal lockout_done_r : std_logic := '0';
    signal sec_tick_r     : std_logic := '0';

begin

    locked_out      <= is_locked;
    alarm           <= is_locked;
    lockout_done    <= lockout_done_r;
    fail_count      <= std_logic_vector(to_unsigned(fail_cnt, 3));
    lockout_tier    <= std_logic_vector(to_unsigned(tier_cnt, 3));
    lockout_rem_sec <= std_logic_vector(to_unsigned(sec_rem, 8));
    sec_tick_out    <= sec_tick_r;

    process(clk, rst)
    begin
        if rst = '1' then
            is_locked      <= '0';
            fail_cnt       <= 0;
            tier_cnt       <= 0;
            sec_rem        <= 0;
            clk_cnt        <= 0;
            lockout_done_r <= '0';
            sec_tick_r     <= '0';

        elsif rising_edge(clk) then
            if is_locked = '0' then
                clk_cnt        <= 0;
                sec_tick_r     <= '0';
                lockout_done_r <= '0';

                if auth_success = '1' then
                    fail_cnt <= 0;
                    tier_cnt <= 0;

                elsif auth_fail = '1' then
                    if fail_cnt + 1 >= MAX_RETRIES then
                        is_locked <= '1';
                        fail_cnt  <= clamp_fail_cnt(MAX_RETRIES);
                        sec_rem   <= tier_duration_sec(tier_cnt, BASE_LOCKOUT_SEC);
                        clk_cnt   <= 0;
                        if tier_cnt < 4 then
                            tier_cnt <= tier_cnt + 1;
                        end if;
                    else
                        fail_cnt <= fail_cnt + 1;
                    end if;
                end if;

            else
                -- Lockout active: ignore auth_fail / auth_success and count down
                lockout_done_r <= '0';

                if clk_cnt = CLK_FREQ_HZ - 1 then
                    clk_cnt    <= 0;
                    sec_tick_r <= '1';

                    if sec_rem <= 1 then
                        sec_rem        <= 0;
                        is_locked      <= '0';
                        fail_cnt       <= 0;
                        lockout_done_r <= '1';
                        -- Keep tier_cnt so a subsequent retry failure batch escalates
                    else
                        sec_rem <= sec_rem - 1;
                    end if;
                else
                    clk_cnt    <= clk_cnt + 1;
                    sec_tick_r <= '0';
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
