-- =============================================================================
-- PROGETTO: HDMI Video Generator per TangNano-20K
-- FILE:     tmds_rpll.vhd
-- SCOPO:    Wrapper VHDL della primitive rPLL Gowin.
-- FUNZIONE: Genera il clock seriale richiesto dal sottosistema HDMI/TMDS.
-- PARAM.:   Configurazione statica della PLL, definita nei generic map.
-- RIF.:     Struttura documentale ispirata a STANAG 4234.
-- VERSIONE: 1.3
-- =============================================================================
-- NOTE DI MANUTENZIONE
--   1. Questo blocco e' vendor-specific.
--   2. Ogni modifica a divisori o sorgenti richiede allineamento con:
--      - video_top.vhd
--      - nano_20k_video.sdc
--      - aspettative di timing monitor/HDMI
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity tmds_rpll is
    port (
        I_clk  : in  std_logic;  -- Clock di riferimento.
        O_clk  : out std_logic;  -- Clock seriale generato.
        O_lock : out std_logic   -- Indicatore lock PLL.
    );
end entity tmds_rpll;

architecture behavioral of tmds_rpll is

    -- Primitive Gowin usata in modalita' statica.
    component rPLL is
        generic (
            FCLKIN           : string  := "27";
            DYN_IDIV_SEL     : string  := "false";
            IDIV_SEL         : integer := 3;
            DYN_FBDIV_SEL    : string  := "false";
            FBDIV_SEL        : integer := 54;
            DYN_ODIV_SEL     : string  := "false";
            ODIV_SEL         : integer := 2;
            PSDA_SEL         : string  := "0000";
            DYN_DA_EN        : string  := "true";
            DUTYDA_SEL       : string  := "1000";
            CLKOUT_FT_DIR    : bit := '1';
            CLKOUTP_FT_DIR   : bit := '1';
            CLKOUT_DLY_STEP  : integer := 0;
            CLKOUTP_DLY_STEP : integer := 0;
            CLKFB_SEL        : string  := "internal";
            CLKOUT_BYPASS    : string  := "false";
            CLKOUTP_BYPASS   : string  := "false";
            CLKOUTD_BYPASS   : string  := "false";
            DYN_SDIV_SEL     : integer := 2;
            CLKOUTD_SRC      : string  := "CLKOUT";
            CLKOUTD3_SRC     : string  := "CLKOUT";
            DEVICE           : string  := "GW2AR-18C"
        );
        port (
            CLKOUT   : out std_logic;
            LOCK     : out std_logic;
            CLKOUTP  : out std_logic;
            CLKOUTD  : out std_logic;
            CLKOUTD3 : out std_logic;
            RESET    : in  std_logic;
            RESET_P  : in  std_logic;
            CLKIN    : in  std_logic;
            CLKFB    : in  std_logic;
            FBDSEL   : in  std_logic_vector(5 downto 0);
            IDSEL    : in  std_logic_vector(5 downto 0);
            ODSEL    : in  std_logic_vector(5 downto 0);
            PSDA     : in  std_logic_vector(3 downto 0);
            DUTYDA   : in  std_logic_vector(3 downto 0);
            FDLY     : in  std_logic_vector(3 downto 0)
        );
    end component;

begin

    -- La PLL non utilizza ingressi dinamici; i selettori runtime sono forzati
    -- a valori costanti e le uscite non usate restano aperte.
    U_rPLL: rPLL
        generic map (
            FCLKIN           => "27",
            DYN_IDIV_SEL     => "false",
            IDIV_SEL         => 3,
            DYN_FBDIV_SEL    => "false",
            FBDIV_SEL        => 54,
            DYN_ODIV_SEL     => "false",
            ODIV_SEL         => 2,
            PSDA_SEL         => "0000",
            DYN_DA_EN        => "true",
            DUTYDA_SEL       => "1000",
            CLKOUT_FT_DIR    => '1',
            CLKOUTP_FT_DIR   => '1',
            CLKOUT_DLY_STEP  => 0,
            CLKOUTP_DLY_STEP => 0,
            CLKFB_SEL        => "internal",
            CLKOUT_BYPASS    => "false",
            CLKOUTP_BYPASS   => "false",
            CLKOUTD_BYPASS   => "false",
            DYN_SDIV_SEL     => 2,
            CLKOUTD_SRC      => "CLKOUT",
            CLKOUTD3_SRC     => "CLKOUT",
            DEVICE           => "GW2AR-18C"
        )
        port map (
            CLKIN    => I_clk,
            CLKOUT   => O_clk,
            LOCK     => O_lock,
            CLKOUTP  => open,
            CLKOUTD  => open,
            CLKOUTD3 => open,
            RESET    => '0',
            RESET_P  => '0',
            CLKFB    => '0',
            FBDSEL   => (others => '0'),
            IDSEL    => (others => '0'),
            ODSEL    => (others => '0'),
            PSDA     => (others => '0'),
            DUTYDA   => (others => '0'),
            FDLY     => (others => '0')
        );

end architecture behavioral;
