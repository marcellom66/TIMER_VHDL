-- =============================================================================
-- PROGETTO: HDMI Video Generator per TangNano-20K
-- FILE:     key_led_ctrl.vhd
-- DESCRIZIONE: Controller per pulsante di selezione pattern e LED indicatori.
--              Include logica di debounce per il pulsante e contatore
--              modulo 6 per la selezione tra 6 pattern disponibili.
-- NORMA:    STANAG 4234 - Documentazione Tecnica NATO
-- DATA:     2026-04-04
-- VERSIONE: 1.0
-- =============================================================================
-- MAPPATURA LED:
--   LED0 = Pattern 0 (spento)
--   LED1 = Pattern 1
--   LED2 = Pattern 2
--   LED3 = Pattern 3
--   LED4 = Pattern 4-5
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity key_led_ctrl is
    port (
        I_clk       : in  std_logic;
        I_rst       : in  std_logic;
        I_key       : in  std_logic;
        O_key_count : out unsigned(2 downto 0);
        O_led       : out std_logic_vector(4 downto 0)
    );
end entity key_led_ctrl;

architecture behavioral of key_led_ctrl is

    constant DEBOUNCE_TIME   : integer := 540000;
    constant MAX_PATTERN     : integer := 6;

    type fsm_state is (IDLE, WAIT_LOW, WAIT_HIGH, COUNT);

    signal state_reg         : fsm_state;
    signal state_next        : fsm_state;
    signal key_count_reg     : unsigned(2 downto 0);
    signal key_sync          : std_logic;
    signal key_prev          : std_logic;
    signal debounce_cnt       : unsigned(19 downto 0);
    signal debounce_done      : std_logic;
    signal led_reg            : std_logic_vector(4 downto 0);
    signal led_next           : std_logic_vector(4 downto 0);

begin

    -- SYNCHRONIZER (2-FF)
    p_sync: process (I_clk)
    begin
        if rising_edge(I_clk) then
            if I_rst = '1' then
                key_sync <= '1';
                key_prev <= '1';
            else
                key_sync <= I_key;
                key_prev <= key_sync;
            end if;
        end if;
    end process p_sync;

    -- DEBOUNCE COUNTER
    p_debounce: process (I_clk)
    begin
        if rising_edge(I_clk) then
            if I_rst = '1' then
                debounce_cnt   <= (others => '0');
                debounce_done  <= '0';
            else
                case state_reg is
                    when WAIT_LOW | WAIT_HIGH =>
                        if debounce_cnt >= DEBOUNCE_TIME then
                            debounce_done <= '1';
                            debounce_cnt  <= (others => '0');
                        else
                            debounce_cnt  <= debounce_cnt + 1;
                            debounce_done <= '0';
                        end if;
                    when others =>
                        debounce_cnt  <= (others => '0');
                        debounce_done <= '0';
                end case;
            end if;
        end if;
    end process p_debounce;

    -- FSM NEXT STATE
    p_fsm_next: process (state_reg, key_sync, debounce_done)
    begin
        state_next <= state_reg;
        case state_reg is
            when IDLE =>
                if key_sync = '0' then
                    state_next <= WAIT_LOW;
                end if;
            when WAIT_LOW =>
                if debounce_done = '1' then
                    if key_sync = '0' then
                        state_next <= WAIT_HIGH;
                    else
                        state_next <= IDLE;
                    end if;
                elsif key_sync = '1' then
                    state_next <= IDLE;
                end if;
            when WAIT_HIGH =>
                if debounce_done = '1' then
                    if key_sync = '1' then
                        state_next <= COUNT;
                    else
                        state_next <= WAIT_LOW;
                    end if;
                elsif key_sync = '0' then
                    state_next <= WAIT_LOW;
                end if;
            when COUNT =>
                state_next <= IDLE;
        end case;
    end process p_fsm_next;

    -- FSM STATE REGISTER
    p_fsm_reg: process (I_clk)
    begin
        if rising_edge(I_clk) then
            if I_rst = '1' then
                state_reg <= IDLE;
            else
                state_reg <= state_next;
            end if;
        end if;
    end process p_fsm_reg;

    -- COUNTER
    p_counter: process (I_clk)
    begin
        if rising_edge(I_clk) then
            if I_rst = '1' then
                key_count_reg <= (others => '0');
            else
                if state_reg = COUNT then
                    if key_count_reg >= (MAX_PATTERN - 1) then
                        key_count_reg <= (others => '0');
                    else
                        key_count_reg <= key_count_reg + 1;
                    end if;
                end if;
            end if;
        end if;
    end process p_counter;

    -- LED DECODE
    p_led_decode: process (key_count_reg)
    begin
        case key_count_reg is
            when "000"  => led_next <= "00001";
            when "001"  => led_next <= "00010";
            when "010"  => led_next <= "00100";
            when "011"  => led_next <= "01000";
            when "100"  => led_next <= "10000";
            when others => led_next <= "10000";
        end case;
    end process p_led_decode;

    -- LED REGISTER
    p_led_reg: process (I_clk)
    begin
        if rising_edge(I_clk) then
            if I_rst = '1' then
                led_reg <= (others => '0');
            else
                led_reg <= led_next;
            end if;
        end if;
    end process p_led_reg;

    O_key_count <= key_count_reg;
    O_led       <= not led_reg;  -- TangNano-20K: LED attivi bassi

end architecture behavioral;
