# HDMI_VHDL — HDMI Video Generator per TangNano-20K

Generatore video HDMI scritto in VHDL per la scheda **Sipeed Tang Nano 20K**.
Produce un segnale **1280×720 @ 60 Hz** con pattern di test selezionabili e un
overlay orologio **HH:MM:SS** in sovraimpressione.

![colorbars](docs/colorbars.png)

---

## Funzionalità

- **7 pattern di test** selezionabili via pulsante:
  | `I_pat_sel` | Pattern |
  |-------------|---------|
  | `000` | Barre colore a pieno schermo |
  | `001` | Griglia rossa su nero |
  | `010` | Gradiente grayscale |
  | `011` | Schermo blu |
  | `100` | Schermo verde |
  | `101` | Schermo rosso |
  | `110` | Schermo bianco |

- **Overlay orologio HH:MM:SS** con pannello arrotondato semi-trasparente
  - Font DIN Condensed Bold 44×56 px con anti-aliasing a 4 livelli (grayscale 2 bit/px)
  - Testo giallo, bordo colorato, fill semi-trasparente
  - Tick a 1 secondo derivato contando 60 frame video

- **Sincronizzazione orario via UART** (115200 8N1)
  - Formato frame: `HH:MM:SS` + CR/LF oppure `THH:MM:SS` + CR/LF
  - Script helper: `tools/send_time.py`

---

## Struttura del progetto

```
src/
  video_top.vhd        — Top level: PLL, reset, integrazione moduli
  testpattern.vhd      — Pattern generator + overlay orologio
  clock_font_pkg.vhd   — ROM font bitmap (auto-generata)
  key_led_ctrl.vhd     — Debounce pulsante, selezione pattern, LED
  tmds_rpll.vhd        — Wrapper PLL Gowin (rPLL + CLKDIV)
  uart_time_rx.vhd     — Ricevitore UART per sincronizzazione orario
  dvi_tx.v             — DVI/TMDS encoder (IP Gowin)
  hdmi.cst             — Pin constraint
  nano_20k_video.sdc   — Timing constraint

tools/
  ttf_to_vhdl_font.py  — Converte un TTF in clock_font_pkg.vhd
  send_time.py         — Invia l'orario corrente via UART alla scheda

docs/
  HDMI_VHDL_SPEC.md    — Specifica tecnica completa
```

---

## Requisiti

- **Scheda**: Sipeed Tang Nano 20K
- **Toolchain**: Gowin EDA (include i primitivi `rPLL`, `CLKDIV`, `DVI_TX_Top`)
- **Python 3** + `Pillow` (solo per rigenerare il font)

---

## Rigenerare il font

```bash
python3 -m pip install pillow
python3 tools/ttf_to_vhdl_font.py /percorso/font.ttf \
  --font-size 56 --width 44 --height 56 --grayscale \
  --output src/clock_font_pkg.vhd
```

---

## Sincronizzazione orario via UART

```bash
# Invia l'ora corrente una volta
python3 tools/send_time.py /dev/tty.usbserial-0001

# Invia l'ora ogni secondo (watch mode)
python3 tools/send_time.py /dev/tty.usbserial-0001 --watch --interval 1

# Accesso diretto via pyftdi (Tang Nano 20K debugger)
python3 tools/send_time.py ftdi://ftdi:2232h/2 --verbose
python3 tools/send_time.py --tang-uart --ftdi-serial 2023030621
```

Configurazione UART: **115200 baud, 8N1, 3.3 V LVCMOS** — pin `70` della scheda.

---

## Licenza

Distribuito sotto licenza **GNU General Public License v3.0**.
Vedi [LICENSE](LICENSE) per i dettagli.
