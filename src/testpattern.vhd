-- =============================================================================
-- PROGETTO: HDMI Video Generator per TangNano-20K
-- FILE:     testpattern.vhd
-- SCOPO:    Generatore video di pattern e overlay orologio.
-- FUNZIONE: Produce HS/VS/DE e bus RGB 24 bit nel dominio pixel.
-- MODALITA': 1280x720@60Hz con pannello HH:MM:SS in sovraimpressione.
-- RIF.:     Struttura documentale ispirata a STANAG 4234.
-- NOTA:     La documentazione seguente e' pensata per manutenzione tecnica del
--           progetto e non rappresenta una conformita' normativa formale.
-- VERSIONE: 1.5
-- =============================================================================
-- PATTERN:
--   000: COLORBARS - 8 barre verticali a tutto schermo
--   001: GRID      - Griglia rossa su sfondo nero
--   010: GRAYSCALE - Gradient orizzontale
--   011: BLUE      - Schermo pieno blu
--   100: GREEN     - Schermo pieno verde
--   101: RED       - Schermo pieno rosso
--   110: WHITE     - Schermo pieno bianco
--
-- PIPELINE FUNZIONALE
--   1. hcount/vcount descrivono il raster completo.
--   2. de_w/hs_w/vs_w sono derivati combinatorialmente.
--   3. Una pipeline a due stadi riallinea sincronismi e dati.
--   4. hcnt_act e' allineato a de_r0 (non de_w) per evitare reset spurio
--      all'ultimo pixel attivo che causava una riga verticale parasssita.
--   5. vcnt_act incrementa al fronte di discesa di de_w per riga.
--   6. Il pattern renderer costruisce il pixel base.
--   7. L'overlay clock disegna un pannello rounded-rect con:
--      - bordo  : BOX_BORDER (opaco)
--      - fill   : mix_color(BLACK, BOX_FILL, 3) -- 75% opaco, colore fisso
--                 per evitare righe di transizione delle barre sottostanti.
--      - testo  : giallo (FFFF00) con anti-aliasing a 4 livelli (0/25/50/100%)
--                 letto direttamente dalla ROM font a 2 bit/pixel.
--   8. Se disponibile, I_time_valid carica un orario esterno via seriale.
--
-- FONT
--   Il package work.clock_font_pkg contiene la ROM del font.
--   Formato: 2 bit per pixel, livelli AA 0-3 (grayscale nativo FreeType).
--   Dimensione cella: 44x56 pixel (DIN Condensed Bold, font-size 56).
--   Il package puo' essere rigenerato con:
--     python3 tools/ttf_to_vhdl_font.py <font.ttf> \
--       --font-size 56 --width 44 --height 56 --grayscale \
--       --output src/clock_font_pkg.vhd
-- =============================================================================

library ieee;
library work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.clock_font_pkg.all;

entity testpattern is
    port (
        I_clk        : in  std_logic;                      -- Pixel clock.
        I_rst        : in  std_logic;                      -- Reset attivo alto.
        I_pat_sel    : in  unsigned(2 downto 0);           -- Selettore pattern.
        I_time_valid : in  std_logic;                      -- Impulso load time.
        I_hour_tens  : in  unsigned(3 downto 0);           -- Ora decine.
        I_hour_ones  : in  unsigned(3 downto 0);           -- Ora unita'.
        I_min_tens   : in  unsigned(3 downto 0);           -- Minuti decine.
        I_min_ones   : in  unsigned(3 downto 0);           -- Minuti unita'.
        I_sec_tens   : in  unsigned(3 downto 0);           -- Secondi decine.
        I_sec_ones   : in  unsigned(3 downto 0);           -- Secondi unita'.
        O_hsync      : out std_logic;                      -- Sync orizzontale.
        O_vsync      : out std_logic;                      -- Sync verticale.
        O_de         : out std_logic;                      -- Data enable area attiva.
        O_data       : out std_logic_vector(23 downto 0)   -- RGB {R,G,B}.
    );
end entity testpattern;

architecture behavioral of testpattern is

    -- COSTANTI DI TIMING
    -- Profilo video CEA-861 per 1280x720p60.
    constant H_TOTAL    : integer := 1650;
    constant H_SYNC     : integer := 40;
    constant H_BPORCH   : integer := 220;
    constant H_RES      : integer := 1280;
    constant V_TOTAL    : integer := 750;
    constant V_SYNC     : integer := 5;
    constant V_BPORCH   : integer := 20;
    constant V_RES      : integer := 720;

    -- PARAMETRI CLOCK OVERLAY
    -- BOX_* definisce il pannello.
    -- POS_* definisce il layout dei glifi HH:MM:SS.
    constant FRAMES_PER_SEC : integer := 60;
    constant FONT_SCALE     : integer := 1;
    constant GLYPH_W        : integer := CLOCK_FONT_WIDTH * FONT_SCALE;
    constant GLYPH_H        : integer := CLOCK_FONT_HEIGHT * FONT_SCALE;
    constant GLYPH_GAP      : integer := 6;
    constant TEXT_W         : integer := (GLYPH_W * 8) + (GLYPH_GAP * 7);
    constant CLOCK_X        : integer := (H_RES - TEXT_W) / 2;
    constant CLOCK_Y        : integer := 42;
    constant BOX_PAD_X      : integer := 14;
    constant BOX_PAD_Y      : integer := 12;
    constant BOX_X0         : integer := CLOCK_X - BOX_PAD_X;
    constant BOX_Y0         : integer := CLOCK_Y - BOX_PAD_Y;
    constant BOX_X1         : integer := CLOCK_X + TEXT_W + BOX_PAD_X;
    constant BOX_Y1         : integer := CLOCK_Y + GLYPH_H + BOX_PAD_Y;
    constant BOX_RADIUS     : integer := 14;
    constant BOX_BORDER_W   : integer := 2;
    constant POS_H10        : integer := 0;
    constant POS_H01        : integer := POS_H10 + GLYPH_W + GLYPH_GAP;
    constant POS_C1         : integer := POS_H01 + GLYPH_W + GLYPH_GAP;
    constant POS_M10        : integer := POS_C1 + GLYPH_W + GLYPH_GAP;
    constant POS_M01        : integer := POS_M10 + GLYPH_W + GLYPH_GAP;
    constant POS_C2         : integer := POS_M01 + GLYPH_W + GLYPH_GAP;
    constant POS_S10        : integer := POS_C2 + GLYPH_W + GLYPH_GAP;
    constant POS_S01        : integer := POS_S10 + GLYPH_W + GLYPH_GAP;

    -- CONTATORI RASTER COMPLETO
    signal hcount       : unsigned(11 downto 0);
    signal vcount       : unsigned(11 downto 0);

    -- SEGNALI COMBINATORIALI DEL RASTER
    signal de_w         : std_logic;
    signal hs_w         : std_logic;
    signal vs_w         : std_logic;

    -- PIPELINE DI ALLINEAMENTO SYNC/DATA
    signal de_r0, de_r1 : std_logic;
    signal hs_r0, hs_r1 : std_logic;
    signal vs_r0, vs_r1 : std_logic;

    -- CONTATORI AREA ATTIVA
    -- Validi solo nella finestra visibile.
    signal hcnt_act     : unsigned(10 downto 0);
    signal vcnt_act     : unsigned(10 downto 0);

    -- DATI PIXEL E REGISTRI DI USCITA
    signal data_r       : std_logic_vector(23 downto 0);
    signal data_out     : std_logic_vector(23 downto 0);

    signal pat_sel_r    : unsigned(2 downto 0);

    -- PALETTE RGB {R,G,B}
    constant WHITE   : std_logic_vector(23 downto 0) := x"FFFFFF";
    constant YELLOW  : std_logic_vector(23 downto 0) := x"FFFF00";
    constant CYAN    : std_logic_vector(23 downto 0) := x"00FFFF";
    constant GREEN   : std_logic_vector(23 downto 0) := x"00FF00";
    constant MAGENTA : std_logic_vector(23 downto 0) := x"FF00FF";
    constant RED_C   : std_logic_vector(23 downto 0) := x"FF0000";
    constant BLUE_C  : std_logic_vector(23 downto 0) := x"0000FF";
    constant BLACK   : std_logic_vector(23 downto 0) := x"000000";
    constant GRAY40    : std_logic_vector(23 downto 0) := x"666666";
    constant GRAY75    : std_logic_vector(23 downto 0) := x"BEBEBE";
    constant YELLOW75  : std_logic_vector(23 downto 0) := x"BEC906";
    constant CYAN75    : std_logic_vector(23 downto 0) := x"0FD2BC";
    constant GREEN75   : std_logic_vector(23 downto 0) := x"0EDE04";
    constant MAGENTA75 : std_logic_vector(23 downto 0) := x"AF00B9";
    constant RED75     : std_logic_vector(23 downto 0) := x"AE0001";
    constant BLUE75    : std_logic_vector(23 downto 0) := x"0000B6";
    constant CYAN100   : std_logic_vector(23 downto 0) := x"15FFFC";
    constant BLUE100   : std_logic_vector(23 downto 0) := x"0200F3";
    constant YELLOW100 : std_logic_vector(23 downto 0) := x"FBFF0A";
    constant RED100    : std_logic_vector(23 downto 0) := x"E80001";
    constant MINUS_I   : std_logic_vector(23 downto 0) := x"003D67";
    constant PLUS_Q    : std_logic_vector(23 downto 0) := x"3E0076";
    constant BLACK_4   : std_logic_vector(23 downto 0) := x"040404";
    constant BLACK_10  : std_logic_vector(23 downto 0) := x"0A0A0A";
    constant GRAY15    : std_logic_vector(23 downto 0) := x"262626";
    constant CLOCK_TEXT : std_logic_vector(23 downto 0) := x"FFFF00";
    constant BOX_FILL   : std_logic_vector(23 downto 0) := x"163B46";
    constant BOX_BORDER : std_logic_vector(23 downto 0) := x"2B7385";

    -- OROLOGIO INTERNO IN BCD
    -- Il secondo viene generato contando 60 frame video.
    signal vs_prev        : std_logic;
    signal frame_count    : integer range 0 to FRAMES_PER_SEC - 1;
    signal hour_tens      : integer range 0 to 2;
    signal hour_ones      : integer range 0 to 9;
    signal minute_tens    : integer range 0 to 5;
    signal minute_ones    : integer range 0 to 9;
    signal second_tens    : integer range 0 to 5;
    signal second_ones    : integer range 0 to 9;

    -- BLENDING DISCRETO A 4 LIVELLI
    -- Usato per ammorbidire bordi e angoli del pannello overlay.
    function mix_color(
        base_color    : std_logic_vector(23 downto 0);
        overlay_color : std_logic_vector(23 downto 0);
        alpha_level   : integer
    ) return std_logic_vector is
        variable base_r    : integer;
        variable base_g    : integer;
        variable base_b    : integer;
        variable over_r    : integer;
        variable over_g    : integer;
        variable over_b    : integer;
        variable mix_r     : integer;
        variable mix_g     : integer;
        variable mix_b     : integer;
        variable out_color : std_logic_vector(23 downto 0);
    begin
        if alpha_level <= 0 then
            return base_color;
        elsif alpha_level >= 4 then
            return overlay_color;
        end if;

        base_r := to_integer(unsigned(base_color(23 downto 16)));
        base_g := to_integer(unsigned(base_color(15 downto 8)));
        base_b := to_integer(unsigned(base_color(7 downto 0)));
        over_r := to_integer(unsigned(overlay_color(23 downto 16)));
        over_g := to_integer(unsigned(overlay_color(15 downto 8)));
        over_b := to_integer(unsigned(overlay_color(7 downto 0)));

        mix_r := ((base_r * (4 - alpha_level)) + (over_r * alpha_level)) / 4;
        mix_g := ((base_g * (4 - alpha_level)) + (over_g * alpha_level)) / 4;
        mix_b := ((base_b * (4 - alpha_level)) + (over_b * alpha_level)) / 4;

        out_color(23 downto 16) := std_logic_vector(to_unsigned(mix_r, 8));
        out_color(15 downto 8)  := std_logic_vector(to_unsigned(mix_g, 8));
        out_color(7 downto 0)   := std_logic_vector(to_unsigned(mix_b, 8));
        return out_color;
    end function;

    -- COLORE DI SFONDO PROCEDURALE
    -- Il pattern 000 usa 8 barre verticali uniformi su tutto lo schermo.
    function pattern_color(
        pat_sel : unsigned(2 downto 0);
        x_pix   : integer;
        y_pix   : integer
    ) return std_logic_vector is
        variable color_v  : std_logic_vector(23 downto 0) := BLACK;
        variable gray_u8  : std_logic_vector(7 downto 0);
    begin
        case pat_sel is
            when "000" =>  -- 8 full-screen color bars
                if x_pix < 160 then
                    color_v := WHITE;
                elsif x_pix < 320 then
                    color_v := YELLOW;
                elsif x_pix < 480 then
                    color_v := CYAN;
                elsif x_pix < 640 then
                    color_v := GREEN;
                elsif x_pix < 800 then
                    color_v := MAGENTA;
                elsif x_pix < 960 then
                    color_v := RED_C;
                elsif x_pix < 1120 then
                    color_v := BLUE_C;
                else
                    color_v := BLACK;
                end if;

            when "001" =>  -- GRID
                if (x_pix mod 32) = 0 or (y_pix mod 32) = 0 then
                    color_v := RED_C;
                else
                    color_v := BLACK;
                end if;

            when "010" =>  -- GRAYSCALE
                gray_u8 := std_logic_vector(to_unsigned(x_pix mod 256, 8));
                color_v := gray_u8 & gray_u8 & gray_u8;

            when "011" =>
                color_v := BLUE_C;

            when "100" =>
                color_v := GREEN;

            when "101" =>
                color_v := RED_C;

            when "110" =>
                color_v := WHITE;

            when others =>
                color_v := BLACK;
        end case;

        return color_v;
    end function;

    -- TEST DI APPARTENENZA A UN RETTANGOLO CON ANGOLI ARROTONDATI
    -- Versione binaria e opaca: evita bleed del fondo e mantiene i bordi netti.
    function rounded_rect_contains(
        px      : integer;
        py      : integer;
        left_x  : integer;
        top_y   : integer;
        right_x : integer;
        bot_y   : integer;
        radius  : integer
    ) return boolean is
        variable dx_v       : integer := 0;
        variable dy_v       : integer := 0;
        variable dist2_v    : integer := 0;
    begin
        if px < left_x or px >= right_x or py < top_y or py >= bot_y then
            return false;
        end if;

        if px < left_x + radius then
            dx_v := (left_x + radius) - px;
        elsif px >= right_x - radius then
            dx_v := px - (right_x - radius - 1);
        end if;

        if py < top_y + radius then
            dy_v := (top_y + radius) - py;
        elsif py >= bot_y - radius then
            dy_v := py - (bot_y - radius - 1);
        end if;

        if dx_v = 0 or dy_v = 0 then
            return true;
        end if;

        dist2_v := (dx_v * dx_v) + (dy_v * dy_v);
        return dist2_v <= (radius * radius);
    end function;

    -- LETTURA ALPHA GRAYSCALE DALLA ROM
    -- Il font e' memorizzato come 2 bit per pixel (livelli 0-3).
    -- Bits per colonna col: row(2*(W-1-col)+1 downto 2*(W-1-col)).
    -- Ritorna 0-3: 0=trasparente, 1=25%, 2=50%, 3=pieno.
    function glyph_alpha_font(glyph : integer; fx : integer; fy : integer)
        return integer is
        variable row_bits : clock_font_row_t;
        variable lo       : integer;
    begin
        if fx < 0 or fx >= CLOCK_FONT_WIDTH or fy < 0 or fy >= CLOCK_FONT_HEIGHT then
            return 0;
        end if;
        row_bits := clock_font_row(glyph, fy);
        lo := 2 * (CLOCK_FONT_WIDTH - 1 - fx);
        return to_integer(unsigned(row_bits(lo + 1 downto lo)));
    end function;

    -- ALPHA PIXEL NEL DOMINIO SCHERMO (FONT_SCALE=1, no scaling necessario)
    -- Mappa 0-3 sulla scala mix_color 0-4:
    --   0->0 (trasparente), 1->1 (bordo leggero), 2->3 (bordo pesante), 3->4 (pieno)
    function glyph_edge_alpha(glyph : integer; x_pos : integer; y_pos : integer)
        return integer is
        variable raw : integer;
    begin
        if x_pos < 0 or x_pos >= GLYPH_W or y_pos < 0 or y_pos >= GLYPH_H then
            return 0;
        end if;
        raw := glyph_alpha_font(glyph, x_pos, y_pos);
        case raw is
            when 0      => return 0;
            when 1      => return 1;
            when 2      => return 3;
            when others => return 4;
        end case;
    end function;

    -- HELPER BOOLEANO: pixel completamente acceso (alpha = 3)
    function glyph_pixel_on(glyph : integer; x_pos : integer; y_pos : integer)
        return boolean is
    begin
        return glyph_edge_alpha(glyph, x_pos, y_pos) = 4;
    end function;

begin

    -- =========================================================================
    -- GENERAZIONE CONTATORI H/V
    -- I due processi descrivono il raster completo, inclusi porch e sync.
    -- =========================================================================
    p_hcnt: process (I_clk)
    begin
        if rising_edge(I_clk) then
            if I_rst = '1' then
                hcount <= (others => '0');
            elsif hcount = (H_TOTAL - 1) then
                hcount <= (others => '0');
            else
                hcount <= hcount + 1;
            end if;
        end if;
    end process p_hcnt;

    p_vcnt: process (I_clk)
    begin
        if rising_edge(I_clk) then
            if I_rst = '1' then
                vcount <= (others => '0');
            elsif hcount = (H_TOTAL - 1) then
                if vcount = (V_TOTAL - 1) then
                    vcount <= (others => '0');
                else
                    vcount <= vcount + 1;
                end if;
            end if;
        end if;
    end process p_vcnt;

    -- =========================================================================
    -- FINESTRE COMBINATORIALI DEL RASTER CORRENTE
    -- =========================================================================
    de_w <= '1' when (hcount >= (H_SYNC + H_BPORCH)) and
                     (hcount <  (H_SYNC + H_BPORCH + H_RES)) and
                     (vcount >= (V_SYNC + V_BPORCH)) and
                     (vcount <  (V_SYNC + V_BPORCH + V_RES))
            else '0';

    -- Sync positivo: attivo alto durante il periodo di sync
    hs_w <= '1' when hcount < H_SYNC else '0';
    vs_w <= '1' when vcount < V_SYNC else '0';

    -- =========================================================================
    -- PIPELINE SYNC/DE
    -- Allinea sincronismi e data-enable con il percorso dati RGB.
    -- =========================================================================
    p_pipe: process (I_clk)
    begin
        if rising_edge(I_clk) then
            if I_rst = '1' then
                de_r0 <= '0'; de_r1 <= '0';
                hs_r0 <= '0'; hs_r1 <= '0';
                vs_r0 <= '0'; vs_r1 <= '0';
            else
                de_r0 <= de_w;  de_r1 <= de_r0;
                hs_r0 <= hs_w;  hs_r1 <= hs_r0;
                vs_r0 <= vs_w;  vs_r1 <= vs_r0;
            end if;
        end if;
    end process p_pipe;

    -- =========================================================================
    -- CONTATORI PIXEL ATTIVI
    -- Ripartono da zero all'inizio di ogni linea/frame visibile.
    -- =========================================================================
    p_hcnt_act: process (I_clk)
    begin
        if rising_edge(I_clk) then
            if I_rst = '1' then
                hcnt_act <= (others => '0');
            elsif de_r0 = '0' then
                hcnt_act <= (others => '0');
            else
                hcnt_act <= hcnt_act + 1;
            end if;
        end if;
    end process p_hcnt_act;

    p_vcnt_act: process (I_clk)
    begin
        if rising_edge(I_clk) then
            if I_rst = '1' then
                vcnt_act <= (others => '0');
            elsif vs_w = '1' then
                vcnt_act <= (others => '0');
            elsif de_r0 = '0' and de_w = '1' then
                -- Ingresso nella finestra attiva: nessuna azione sul contatore Y.
                null;
            elsif de_w = '0' and de_r0 = '1' then
                vcnt_act <= vcnt_act + 1;
            end if;
        end if;
    end process p_vcnt_act;

    -- =========================================================================
    -- REGISTRO SELEZIONE PATTERN
    -- =========================================================================
    p_pat: process (I_clk)
    begin
        if rising_edge(I_clk) then
            if I_rst = '1' then
                pat_sel_r <= (others => '0');
            else
                pat_sel_r <= I_pat_sel;
            end if;
        end if;
    end process p_pat;

    -- =========================================================================
    -- OROLOGIO HH:MM:SS
    -- Il tick a 1 secondo e' ottenuto contando 60 frame completi.
    -- =========================================================================
    p_clock: process (I_clk)
    begin
        if rising_edge(I_clk) then
            if I_rst = '1' then
                vs_prev     <= '0';
                frame_count <= 0;
                hour_tens   <= 0;
                hour_ones   <= 0;
                minute_tens <= 0;
                minute_ones <= 0;
                second_tens <= 0;
                second_ones <= 0;
            else
                vs_prev <= vs_r1;

                if I_time_valid = '1' then
                    frame_count <= 0;
                    hour_tens   <= to_integer(I_hour_tens);
                    hour_ones   <= to_integer(I_hour_ones);
                    minute_tens <= to_integer(I_min_tens);
                    minute_ones <= to_integer(I_min_ones);
                    second_tens <= to_integer(I_sec_tens);
                    second_ones <= to_integer(I_sec_ones);
                elsif vs_prev = '0' and vs_r1 = '1' then
                    if frame_count = FRAMES_PER_SEC - 1 then
                        frame_count <= 0;

                        if second_ones = 9 then
                            second_ones <= 0;

                            if second_tens = 5 then
                                second_tens <= 0;

                                if minute_ones = 9 then
                                    minute_ones <= 0;

                                    if minute_tens = 5 then
                                        minute_tens <= 0;

                                        if hour_tens = 2 and hour_ones = 3 then
                                            hour_tens <= 0;
                                            hour_ones <= 0;
                                        elsif hour_ones = 9 then
                                            hour_ones <= 0;
                                            hour_tens <= hour_tens + 1;
                                        elsif hour_tens = 2 and hour_ones = 3 then
                                            hour_tens <= 0;
                                            hour_ones <= 0;
                                        else
                                            hour_ones <= hour_ones + 1;
                                        end if;
                                    else
                                        minute_tens <= minute_tens + 1;
                                    end if;
                                else
                                    minute_ones <= minute_ones + 1;
                                end if;
                            else
                                second_tens <= second_tens + 1;
                            end if;
                        else
                            second_ones <= second_ones + 1;
                        end if;
                    else
                        frame_count <= frame_count + 1;
                    end if;
                end if;
            end if;
        end if;
    end process p_clock;

    -- =========================================================================
    -- GENERAZIONE PIXEL DATA
    --   1. calcolo del pixel base dal pattern selezionato
    --   2. applicazione del pannello rounded-rectangle del clock
    --   3. sovrapposizione dei glifi del tempo corrente
    -- =========================================================================
    p_data: process (I_clk)
        variable base_pixel    : std_logic_vector(23 downto 0);
        variable overlay_pixel : std_logic_vector(23 downto 0);
        variable x_act         : integer;
        variable y_act         : integer;
        variable local_x       : integer;
        variable local_y       : integer;
        variable glyph_x       : integer;
        variable glyph_y       : integer;
        variable glyph_digit   : integer;
        variable glyph_alpha   : integer;
        variable outer_hit     : boolean;
        variable inner_hit     : boolean;
    begin
        if rising_edge(I_clk) then
            if I_rst = '1' then
                data_r <= (others => '0');
            elsif de_r0 = '1' then
                x_act := to_integer(hcnt_act);
                y_act := to_integer(vcnt_act);
                base_pixel := pattern_color(pat_sel_r, x_act, y_act);
                overlay_pixel := base_pixel;
                glyph_alpha := 0;
                glyph_digit := -1;
                outer_hit := rounded_rect_contains(
                    x_act, y_act, BOX_X0, BOX_Y0, BOX_X1, BOX_Y1, BOX_RADIUS
                );
                inner_hit := rounded_rect_contains(
                    x_act,
                    y_act,
                    BOX_X0 + BOX_BORDER_W,
                    BOX_Y0 + BOX_BORDER_W,
                    BOX_X1 - BOX_BORDER_W,
                    BOX_Y1 - BOX_BORDER_W,
                    BOX_RADIUS - BOX_BORDER_W
                );

                if outer_hit then
                    if inner_hit then
                        overlay_pixel := mix_color(BLACK, BOX_FILL, 3);
                    else
                        overlay_pixel := BOX_BORDER;
                    end if;

                    if inner_hit and
                       x_act >= CLOCK_X and x_act < CLOCK_X + TEXT_W and
                       y_act >= CLOCK_Y and y_act < CLOCK_Y + GLYPH_H then
                        local_x := x_act - CLOCK_X;
                        local_y := y_act - CLOCK_Y;
                        glyph_y := local_y;

                        if local_x >= POS_H10 and local_x < POS_H10 + GLYPH_W then
                            glyph_digit := hour_tens;
                            glyph_x := local_x - POS_H10;
                        elsif local_x >= POS_H01 and local_x < POS_H01 + GLYPH_W then
                            glyph_digit := hour_ones;
                            glyph_x := local_x - POS_H01;
                        elsif local_x >= POS_C1 and local_x < POS_C1 + GLYPH_W then
                            glyph_digit := 10;
                            glyph_x := local_x - POS_C1;
                        elsif local_x >= POS_M10 and local_x < POS_M10 + GLYPH_W then
                            glyph_digit := minute_tens;
                            glyph_x := local_x - POS_M10;
                        elsif local_x >= POS_M01 and local_x < POS_M01 + GLYPH_W then
                            glyph_digit := minute_ones;
                            glyph_x := local_x - POS_M01;
                        elsif local_x >= POS_C2 and local_x < POS_C2 + GLYPH_W then
                            glyph_digit := 10;
                            glyph_x := local_x - POS_C2;
                        elsif local_x >= POS_S10 and local_x < POS_S10 + GLYPH_W then
                            glyph_digit := second_tens;
                            glyph_x := local_x - POS_S10;
                        elsif local_x >= POS_S01 and local_x < POS_S01 + GLYPH_W then
                            glyph_digit := second_ones;
                            glyph_x := local_x - POS_S01;
                        end if;

                        if glyph_digit >= 0 then
                            glyph_alpha := glyph_edge_alpha(glyph_digit, glyph_x, glyph_y);
                        end if;

                        if glyph_alpha = 4 then
                            overlay_pixel := CLOCK_TEXT;
                        elsif glyph_alpha > 0 then
                            overlay_pixel := mix_color(overlay_pixel, CLOCK_TEXT, glyph_alpha);
                        end if;
                    end if;
                end if;

                data_r <= overlay_pixel;
            else
                data_r <= (others => '0');
            end if;
        end if;
    end process p_data;

    -- REGISTRO FINALE USCITA DATI
    -- Allinea il bus RGB a de_r1.
    p_out: process (I_clk)
    begin
        if rising_edge(I_clk) then
            if I_rst = '1' then
                data_out <= (others => '0');
            else
                data_out <= data_r;
            end if;
        end if;
    end process p_out;

    -- =========================================================================
    -- USCITE DEL BLOCCO VIDEO
    -- =========================================================================
    O_hsync <= hs_r1;
    O_vsync <= vs_r1;
    O_de    <= de_r1;
    O_data  <= data_out;

end architecture behavioral;
