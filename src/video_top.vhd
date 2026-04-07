-- =============================================================================
-- PROGETTO: HDMI Video Generator per TangNano-20K
-- FILE:     video_top.vhd
-- SCOPO:    Top-level del sottosistema video HDMI.
-- FUNZIONE: Integra clocking, selezione pattern, generazione video e
--           conversione TMDS verso l'IP Gowin di trasmissione DVI/HDMI.
-- ARCH.:    Architettura dual-clock con dominio seriale e dominio pixel.
-- RIF.:     Struttura documentale ispirata a STANAG 4234.
-- NOTA:     I commenti adottano uno stile da specifica tecnica; non implicano
--           conformita' formale o certificazione NATO.
-- VERSIONE: 1.3
-- =============================================================================
-- INTERFACCIA ESTERNA
--   I_clk        : clock di riferimento board.
--   I_rst        : reset globale attivo alto.
--   I_key        : pulsante utente per selezione pattern.
--   I_uart_rx    : linea UART RX opzionale per sincronizzazione orario.
--   O_led        : LED diagnostici/pattern, attivi bassi sulla board.
--   running      : indicatore di logica fuori reset.
--   O_tmds_*     : uscite differenziali HDMI/TMDS.
--
-- FLUSSO FUNZIONALE
--   1. tmds_rpll genera il clock seriale.
--   2. CLKDIV ricava il pixel clock.
--   3. key_led_ctrl produce il selettore pattern.
--   4. testpattern genera HS/VS/DE/RGB.
--   5. DVI_TX_Top serializza il flusso nel dominio TMDS.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity video_top is
    port (
        I_clk         : in  std_logic;   -- Clock di riferimento board.
        I_rst         : in  std_logic;   -- Reset globale, attivo alto.
        I_key         : in  std_logic;   -- Ingresso pulsante utente.
        I_uart_rx     : in  std_logic;   -- UART RX opzionale per time sync.
        O_led         : out std_logic_vector(4 downto 0);  -- LED board.
        running       : out std_logic;   -- '1' se il top-level non e' in reset.
        O_tmds_clk_p  : out std_logic;   -- TMDS clock positivo.
        O_tmds_clk_n  : out std_logic;   -- TMDS clock negativo.
        O_tmds_data_p : out std_logic_vector(2 downto 0);  -- TMDS data P.
        O_tmds_data_n : out std_logic_vector(2 downto 0)   -- TMDS data N.
    );
end entity video_top;

architecture behavioral of video_top is

    -- CLOCKING E RESET
    -- serial_clk : clock ad alta velocita' per il trasmettitore TMDS.
    -- pix_clk    : clock nel dominio video/pattern.
    -- pll_lock   : validita' del clock PLL.
    -- hdmi_rst_n : reset attivo basso verso i blocchi HDMI.
    signal serial_clk    : std_logic;
    signal pix_clk       : std_logic;
    signal pll_lock      : std_logic;
    signal rst_n         : std_logic;
    signal hdmi_rst_n    : std_logic;

    -- SEGNALI VIDEO NEL DOMINIO pixel_clk
    signal key_state     : unsigned(2 downto 0);
    signal pixel_data    : std_logic_vector(23 downto 0);
    signal video_hsync   : std_logic;
    signal video_vsync   : std_logic;
    signal video_de      : std_logic;
    signal uart_time_valid : std_logic;
    signal uart_h10        : unsigned(3 downto 0);
    signal uart_h01        : unsigned(3 downto 0);
    signal uart_m10        : unsigned(3 downto 0);
    signal uart_m01        : unsigned(3 downto 0);
    signal uart_s10        : unsigned(3 downto 0);
    signal uart_s01        : unsigned(3 downto 0);

    -- COMPONENTE: tmds_rpll
    component tmds_rpll is
        port (
            I_clk  : in  std_logic;
            O_clk  : out std_logic;
            O_lock : out std_logic
        );
    end component;

    -- COMPONENTE: CLKDIV (primitiva Gowin)
    component CLKDIV is
        generic (
            DIV_MODE : string := "5";
            GSREN    : string := "false"
        );
        port (
            RESETN : in  std_logic;
            HCLKIN : in  std_logic;
            CLKOUT : out std_logic;
            CALIB  : in  std_logic
        );
    end component;

    -- COMPONENTE: key_led_ctrl
    component key_led_ctrl is
        port (
            I_clk       : in  std_logic;
            I_rst       : in  std_logic;
            I_key       : in  std_logic;
            O_key_count : out unsigned(2 downto 0);
            O_led       : out std_logic_vector(4 downto 0)
        );
    end component;

    -- COMPONENTE: testpattern
    component testpattern is
        port (
            I_clk        : in  std_logic;
            I_rst        : in  std_logic;
            I_pat_sel    : in  unsigned(2 downto 0);
            I_time_valid : in  std_logic;
            I_hour_tens  : in  unsigned(3 downto 0);
            I_hour_ones  : in  unsigned(3 downto 0);
            I_min_tens   : in  unsigned(3 downto 0);
            I_min_ones   : in  unsigned(3 downto 0);
            I_sec_tens   : in  unsigned(3 downto 0);
            I_sec_ones   : in  unsigned(3 downto 0);
            O_hsync      : out std_logic;
            O_vsync      : out std_logic;
            O_de         : out std_logic;
            O_data       : out std_logic_vector(23 downto 0)
        );
    end component;

    -- COMPONENTE: uart_time_rx
    component uart_time_rx is
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
    end component;

    -- COMPONENTE: DVI_TX_Top (IP Gowin, modulo Verilog)
    component DVI_TX_Top is
        port (
            I_rst_n      : in  std_logic;
            I_serial_clk : in  std_logic;
            I_rgb_clk    : in  std_logic;
            I_rgb_vs     : in  std_logic;
            I_rgb_hs     : in  std_logic;
            I_rgb_de     : in  std_logic;
            I_rgb_r      : in  std_logic_vector(7 downto 0);
            I_rgb_g      : in  std_logic_vector(7 downto 0);
            I_rgb_b      : in  std_logic_vector(7 downto 0);
            O_tmds_clk_p : out std_logic;
            O_tmds_clk_n : out std_logic;
            O_tmds_data_p: out std_logic_vector(2 downto 0);
            O_tmds_data_n: out std_logic_vector(2 downto 0)
        );
    end component;

begin

    -- CONVERSIONE POLARITA' RESET
    -- L'interfaccia utente usa reset attivo alto; il trasmettitore HDMI
    -- richiede invece un reset attivo basso e valido solo a PLL agganciata.
    rst_n      <= not I_rst;
    hdmi_rst_n <= rst_n and pll_lock;
    running    <= rst_n;

    -- GENERAZIONE CLOCK SERIALE
    U_tmds_rpll: tmds_rpll
        port map (
            I_clk  => I_clk,
            O_clk  => serial_clk,
            O_lock => pll_lock
        );

    -- DIVISIONE CLOCK VERSO DOMINIO PIXEL
    U_clkdiv: CLKDIV
        generic map (
            DIV_MODE => "5",
            GSREN    => "false"
        )
        port map (
            RESETN => hdmi_rst_n,
            HCLKIN => serial_clk,
            CLKOUT => pix_clk,
            CALIB  => '1'
        );

    -- INTERFACCIA UTENTE
    U_key_led_ctrl: key_led_ctrl
        port map (
            I_clk       => pix_clk,
            I_rst       => I_rst,
            I_key       => I_key,
            O_key_count => key_state,
            O_led       => O_led
        );

    -- RICEZIONE OPZIONALE ORARIO DA UART ASCII
    U_uart_time_rx: uart_time_rx
        port map (
            I_clk        => pix_clk,
            I_rst        => I_rst,
            I_uart_rx    => I_uart_rx,
            O_time_valid => uart_time_valid,
            O_hour_tens  => uart_h10,
            O_hour_ones  => uart_h01,
            O_min_tens   => uart_m10,
            O_min_ones   => uart_m01,
            O_sec_tens   => uart_s10,
            O_sec_ones   => uart_s01
        );

    -- GENERATORE RASTER E PIXEL DATA
    U_testpattern: testpattern
        port map (
            I_clk        => pix_clk,
            I_rst        => I_rst,
            I_pat_sel    => key_state,
            I_time_valid => uart_time_valid,
            I_hour_tens  => uart_h10,
            I_hour_ones  => uart_h01,
            I_min_tens   => uart_m10,
            I_min_ones   => uart_m01,
            I_sec_tens   => uart_s10,
            I_sec_ones   => uart_s01,
            O_hsync      => video_hsync,
            O_vsync      => video_vsync,
            O_de         => video_de,
            O_data       => pixel_data
        );

    -- CODIFICA TMDS E USCITA HDMI
    U_DVI_TX_Top: DVI_TX_Top
        port map (
            I_rst_n       => hdmi_rst_n,
            I_serial_clk  => serial_clk,
            I_rgb_clk     => pix_clk,
            I_rgb_vs      => video_vsync,
            I_rgb_hs      => video_hsync,
            I_rgb_de      => video_de,
            I_rgb_r       => pixel_data(23 downto 16),
            I_rgb_g       => pixel_data(15 downto 8),
            I_rgb_b       => pixel_data(7 downto 0),
            O_tmds_clk_p  => O_tmds_clk_p,
            O_tmds_clk_n  => O_tmds_clk_n,
            O_tmds_data_p => O_tmds_data_p,
            O_tmds_data_n => O_tmds_data_n
        );

end architecture behavioral;
