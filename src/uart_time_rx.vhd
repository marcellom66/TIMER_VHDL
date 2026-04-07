-- =============================================================================
-- PROGETTO: HDMI Video Generator per TangNano-20K
-- FILE:     uart_time_rx.vhd
-- SCOPO:    Ricezione opzionale dell'ora da linea seriale UART.
-- FUNZIONE: Decodifica frame ASCII e produce un impulso di caricamento tempo.
-- FORMATO:  "HH:MM:SS\n" oppure "THH:MM:SS\n" a 115200 8N1.
-- NOTA:     In assenza di seriale o in caso di frame invalido, non genera
--           aggiornamenti e il clock video continua con il conteggio interno.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_time_rx is
    port (
        I_clk        : in  std_logic;
        I_rst        : in  std_logic;
        I_uart_rx    : in  std_logic;
        O_time_valid : out std_logic;
        O_hour_tens  : out unsigned(3 downto 0);
        O_hour_ones  : out unsigned(3 downto 0);
        O_min_tens   : out unsigned(3 downto 0);
        O_min_ones   : out unsigned(3 downto 0);
        O_sec_tens   : out unsigned(3 downto 0);
        O_sec_ones   : out unsigned(3 downto 0)
    );
end entity uart_time_rx;

architecture behavioral of uart_time_rx is

    constant CLOCKS_PER_BIT : integer := 645; -- 74.25MHz / 115200 ~= 644.53
    constant HALF_BIT       : integer := CLOCKS_PER_BIT / 2;

    type uart_state_t is (UART_IDLE, UART_START, UART_DATA, UART_STOP);
    type parser_state_t is (
        PARSER_IDLE,
        PARSER_H10,
        PARSER_H01,
        PARSER_C1,
        PARSER_M10,
        PARSER_M01,
        PARSER_C2,
        PARSER_S10,
        PARSER_S01,
        PARSER_TERM
    );

    signal rx_meta        : std_logic;
    signal rx_sync        : std_logic;
    signal rx_prev        : std_logic;

    signal uart_state     : uart_state_t;
    signal parser_state   : parser_state_t;

    signal baud_count     : integer range 0 to CLOCKS_PER_BIT - 1;
    signal bit_count      : integer range 0 to 7;
    signal rx_shift       : std_logic_vector(7 downto 0);
    signal rx_byte        : std_logic_vector(7 downto 0);
    signal rx_strobe      : std_logic;

    signal hour_tens_r    : unsigned(3 downto 0);
    signal hour_ones_r    : unsigned(3 downto 0);
    signal min_tens_r     : unsigned(3 downto 0);
    signal min_ones_r     : unsigned(3 downto 0);
    signal sec_tens_r     : unsigned(3 downto 0);
    signal sec_ones_r     : unsigned(3 downto 0);
    signal time_valid_r   : std_logic;

    function ascii_is_digit(b : std_logic_vector(7 downto 0)) return boolean is
    begin
        return unsigned(b) >= to_unsigned(character'pos('0'), 8) and
               unsigned(b) <= to_unsigned(character'pos('9'), 8);
    end function;

    function ascii_to_bcd(b : std_logic_vector(7 downto 0)) return unsigned is
    begin
        return resize(unsigned(b) - to_unsigned(character'pos('0'), 8), 4);
    end function;

begin

    O_time_valid <= time_valid_r;
    O_hour_tens  <= hour_tens_r;
    O_hour_ones  <= hour_ones_r;
    O_min_tens   <= min_tens_r;
    O_min_ones   <= min_ones_r;
    O_sec_tens   <= sec_tens_r;
    O_sec_ones   <= sec_ones_r;

    -- Sincronizzazione ingresso UART nel dominio pixel clock.
    p_sync: process (I_clk)
    begin
        if rising_edge(I_clk) then
            if I_rst = '1' then
                rx_meta <= '1';
                rx_sync <= '1';
                rx_prev <= '1';
            else
                rx_meta <= I_uart_rx;
                rx_sync <= rx_meta;
                rx_prev <= rx_sync;
            end if;
        end if;
    end process p_sync;

    -- Ricevitore UART minimale 8N1.
    p_uart_rx: process (I_clk)
    begin
        if rising_edge(I_clk) then
            if I_rst = '1' then
                uart_state <= UART_IDLE;
                baud_count <= 0;
                bit_count  <= 0;
                rx_shift   <= (others => '0');
                rx_byte    <= (others => '0');
                rx_strobe  <= '0';
            else
                rx_strobe <= '0';

                case uart_state is
                    when UART_IDLE =>
                        if rx_prev = '1' and rx_sync = '0' then
                            uart_state <= UART_START;
                            baud_count <= HALF_BIT;
                        end if;

                    when UART_START =>
                        if baud_count = 0 then
                            if rx_sync = '0' then
                                uart_state <= UART_DATA;
                                baud_count <= CLOCKS_PER_BIT - 1;
                                bit_count  <= 0;
                            else
                                uart_state <= UART_IDLE;
                            end if;
                        else
                            baud_count <= baud_count - 1;
                        end if;

                    when UART_DATA =>
                        if baud_count = 0 then
                            rx_shift(bit_count) <= rx_sync;
                            if bit_count = 7 then
                                uart_state <= UART_STOP;
                            else
                                bit_count <= bit_count + 1;
                            end if;
                            baud_count <= CLOCKS_PER_BIT - 1;
                        else
                            baud_count <= baud_count - 1;
                        end if;

                    when UART_STOP =>
                        if baud_count = 0 then
                            uart_state <= UART_IDLE;
                            if rx_sync = '1' then
                                rx_byte   <= rx_shift;
                                rx_strobe <= '1';
                            end if;
                        else
                            baud_count <= baud_count - 1;
                        end if;
                end case;
            end if;
        end if;
    end process p_uart_rx;

    -- Parser frame ASCII:
    --   HH:MM:SS\n
    --   THH:MM:SS\n
    p_parser: process (I_clk)
    begin
        if rising_edge(I_clk) then
            if I_rst = '1' then
                parser_state <= PARSER_IDLE;
                hour_tens_r  <= (others => '0');
                hour_ones_r  <= (others => '0');
                min_tens_r   <= (others => '0');
                min_ones_r   <= (others => '0');
                sec_tens_r   <= (others => '0');
                sec_ones_r   <= (others => '0');
                time_valid_r <= '0';
            else
                time_valid_r <= '0';

                if rx_strobe = '1' then
                    case parser_state is
                        when PARSER_IDLE =>
                            if rx_byte = x"54" then -- 'T'
                                parser_state <= PARSER_H10;
                            elsif ascii_is_digit(rx_byte) then
                                hour_tens_r  <= ascii_to_bcd(rx_byte);
                                parser_state <= PARSER_H01;
                            else
                                parser_state <= PARSER_IDLE;
                            end if;

                        when PARSER_H10 =>
                            if ascii_is_digit(rx_byte) then
                                hour_tens_r  <= ascii_to_bcd(rx_byte);
                                parser_state <= PARSER_H01;
                            else
                                parser_state <= PARSER_IDLE;
                            end if;

                        when PARSER_H01 =>
                            if ascii_is_digit(rx_byte) then
                                hour_ones_r  <= ascii_to_bcd(rx_byte);
                                parser_state <= PARSER_C1;
                            else
                                parser_state <= PARSER_IDLE;
                            end if;

                        when PARSER_C1 =>
                            if rx_byte = x"3A" then -- ':'
                                parser_state <= PARSER_M10;
                            else
                                parser_state <= PARSER_IDLE;
                            end if;

                        when PARSER_M10 =>
                            if ascii_is_digit(rx_byte) then
                                min_tens_r   <= ascii_to_bcd(rx_byte);
                                parser_state <= PARSER_M01;
                            else
                                parser_state <= PARSER_IDLE;
                            end if;

                        when PARSER_M01 =>
                            if ascii_is_digit(rx_byte) then
                                min_ones_r   <= ascii_to_bcd(rx_byte);
                                parser_state <= PARSER_C2;
                            else
                                parser_state <= PARSER_IDLE;
                            end if;

                        when PARSER_C2 =>
                            if rx_byte = x"3A" then
                                parser_state <= PARSER_S10;
                            else
                                parser_state <= PARSER_IDLE;
                            end if;

                        when PARSER_S10 =>
                            if ascii_is_digit(rx_byte) then
                                sec_tens_r   <= ascii_to_bcd(rx_byte);
                                parser_state <= PARSER_S01;
                            else
                                parser_state <= PARSER_IDLE;
                            end if;

                        when PARSER_S01 =>
                            if ascii_is_digit(rx_byte) then
                                sec_ones_r   <= ascii_to_bcd(rx_byte);
                                parser_state <= PARSER_TERM;
                            else
                                parser_state <= PARSER_IDLE;
                            end if;

                        when PARSER_TERM =>
                            if rx_byte = x"0A" or rx_byte = x"0D" then
                                if hour_tens_r <= 2 and
                                   not (hour_tens_r = 2 and hour_ones_r > 3) and
                                   min_tens_r <= 5 and sec_tens_r <= 5 then
                                    time_valid_r <= '1';
                                end if;
                            end if;
                            parser_state <= PARSER_IDLE;
                    end case;
                end if;
            end if;
        end if;
    end process p_parser;

end architecture behavioral;
