#!/usr/bin/env python3
"""
Convertitore TTF -> package VHDL per il renderer dell'orologio HH:MM:SS.

Genera un file compatibile con `src/clock_font_pkg.vhd`.

Esempio:
    python3 tools/ttf_to_vhdl_font.py \
        /System/Library/Fonts/SFNSMono.ttf \
        --font-size 28 \
        --width 20 \
        --height 32 \
        --output src/clock_font_pkg.vhd

Dipendenze:
    python3 -m pip install pillow
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import sys


DEFAULT_CHARS = "0123456789:"


@dataclass
class GlyphBitmap:
    char: str
    rows: list[str]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Converte un font TTF in un package VHDL bitmap per l'orologio."
    )
    parser.add_argument("font", help="Percorso del file .ttf da convertire.")
    parser.add_argument(
        "--output",
        default="src/clock_font_pkg.vhd",
        help="File VHDL di output. Default: src/clock_font_pkg.vhd",
    )
    parser.add_argument(
        "--package-name",
        default="clock_font_pkg",
        help="Nome del package VHDL. Default: clock_font_pkg",
    )
    parser.add_argument(
        "--chars",
        default=DEFAULT_CHARS,
        help="Ordine glifi da esportare. Default: 0123456789:",
    )
    parser.add_argument(
        "--font-size",
        type=int,
        default=28,
        help="Dimensione nominale del font TTF. Default: 28",
    )
    parser.add_argument(
        "--width",
        type=int,
        default=None,
        help="Larghezza cella glifo. Se omessa viene calcolata.",
    )
    parser.add_argument(
        "--height",
        type=int,
        default=None,
        help="Altezza cella glifo. Se omessa viene calcolata.",
    )
    parser.add_argument(
        "--padding-x",
        type=int,
        default=2,
        help="Padding orizzontale interno glifo. Default: 2",
    )
    parser.add_argument(
        "--padding-y",
        type=int,
        default=2,
        help="Padding verticale interno glifo. Default: 2",
    )
    parser.add_argument(
        "--offset-x",
        type=int,
        default=0,
        help="Offset orizzontale applicato al render del glifo.",
    )
    parser.add_argument(
        "--offset-y",
        type=int,
        default=0,
        help="Offset verticale applicato al render del glifo.",
    )
    parser.add_argument(
        "--threshold",
        type=int,
        default=128,
        help="Soglia 0..255 per binarizzare il raster. Default: 128",
    )
    parser.add_argument(
        "--grayscale",
        action="store_true",
        help="Emette 2 bit per pixel (4 livelli AA) invece di 1 bit binario.",
    )
    parser.add_argument(
        "--preview",
        action="store_true",
        help="Stampa una preview ASCII del font generato.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Abilita log sintetici.",
    )
    return parser.parse_args()


def require_pillow():
    try:
        from PIL import Image, ImageDraw, ImageFont  # type: ignore
    except ImportError as exc:
        raise SystemExit(
            "Pillow non installato. Esegui: python3 -m pip install pillow"
        ) from exc
    return Image, ImageDraw, ImageFont


def compute_cell_size(chars: str, font, padding_x: int, padding_y: int) -> tuple[int, int]:
    metrics = [font.getbbox(char) for char in chars]
    max_w = max((bbox[2] - bbox[0]) for bbox in metrics)
    max_h = max((bbox[3] - bbox[1]) for bbox in metrics)
    ascent, descent = font.getmetrics()

    width = max_w + (padding_x * 2)
    height = max(max_h, ascent + descent) + (padding_y * 2)
    return width, height


def render_glyphs(args: argparse.Namespace) -> tuple[list[GlyphBitmap], int, int]:
    Image, ImageDraw, ImageFont = require_pillow()

    font = ImageFont.truetype(args.font, args.font_size)
    cell_w, cell_h = compute_cell_size(args.chars, font, args.padding_x, args.padding_y)

    if args.width is not None:
        cell_w = args.width
    if args.height is not None:
        cell_h = args.height

    glyphs: list[GlyphBitmap] = []

    for char in args.chars:
        bbox = font.getbbox(char)
        glyph_w = bbox[2] - bbox[0]
        glyph_h = bbox[3] - bbox[1]

        image = Image.new("L", (cell_w, cell_h), color=0)
        draw = ImageDraw.Draw(image)

        x_pos = ((cell_w - glyph_w) // 2) - bbox[0] + args.offset_x
        y_pos = ((cell_h - glyph_h) // 2) - bbox[1] + args.offset_y
        draw.text((x_pos, y_pos), char, fill=255, font=font)

        rows: list[str] = []
        for row_idx in range(cell_h):
            bits = []
            for col_idx in range(cell_w):
                px = image.getpixel((col_idx, row_idx))
                if args.grayscale:
                    # Quantizza 0-255 a 4 livelli (2 bit): 0,1,2,3
                    level = min(3, px >> 6)
                    bits.append(f"{level:02b}")
                else:
                    bits.append("1" if px >= args.threshold else "0")
            rows.append("".join(bits))

        glyphs.append(GlyphBitmap(char=char, rows=rows))

    return glyphs, cell_w, cell_h


def ascii_preview(glyphs: list[GlyphBitmap]) -> str:
    lines: list[str] = []
    for glyph in glyphs:
        lines.append(f"[{glyph.char}]")
        for row in glyph.rows:
            lines.append("".join("#" if bit == "1" else "." for bit in row))
        lines.append("")
    return "\n".join(lines)


def vhdl_string(bits: str) -> str:
    return f"\"{bits}\""


def build_vhdl(
    package_name: str,
    font_path: str,
    glyphs: list[GlyphBitmap],
    width: int,
    height: int,
    grayscale: bool = False,
) -> str:
    lines: list[str] = []
    row_bits = width * 2 if grayscale else width
    gs_flag  = "SI" if grayscale else "NO"
    lines.extend(
        [
            "-- =============================================================================",
            f"-- FILE:     {package_name}.vhd",
            "-- ORIGINE:  Generato automaticamente da tools/ttf_to_vhdl_font.py",
            f"-- FONT:     {font_path}",
            f"-- GLIFI:    {''.join(g.char for g in glyphs)}",
            f"-- DIM.:     {width}x{height}",
            f"-- GRAYSCALE: {gs_flag}  (2 bit/pixel se SI: livelli AA 0-3)",
            "-- =============================================================================",
            "",
            "library ieee;",
            "use ieee.std_logic_1164.all;",
            "",
            f"package {package_name} is",
            f"    constant CLOCK_FONT_GLYPHS    : integer := {len(glyphs)};",
            f"    constant CLOCK_FONT_WIDTH     : integer := {width};",
            f"    constant CLOCK_FONT_HEIGHT    : integer := {height};",
            f"    constant CLOCK_FONT_GRAYSCALE : boolean := {'true' if grayscale else 'false'};",
            "",
            f"    subtype clock_font_row_t is std_logic_vector({row_bits} - 1 downto 0);",
            "",
            "    function clock_font_row(glyph : integer; row_idx : integer)",
            "        return clock_font_row_t;",
            f"end package {package_name};",
            "",
            f"package body {package_name} is",
            "    function clock_font_row(glyph : integer; row_idx : integer)",
            "        return clock_font_row_t is",
            "    begin",
            "        case glyph is",
        ]
    )

    for glyph_idx, glyph in enumerate(glyphs):
        lines.append(f"            when {glyph_idx} =>  -- '{glyph.char}'")
        lines.append("                case row_idx is")
        for row_idx, bits in enumerate(glyph.rows):
            lines.append(f"                    when {row_idx} => return {vhdl_string(bits)};")
        lines.append("                    when others => return (others => '0');")
        lines.append("                end case;")

    lines.extend(
        [
            "            when others =>",
            "                return (others => '0');",
            "        end case;",
            "    end function;",
            f"end package body {package_name};",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    glyphs, width, height = render_glyphs(args)

    if args.verbose:
        print(
            f"Font rasterizzato: {args.font} -> {len(glyphs)} glifi "
            f"da {width}x{height} px"
        )

    if args.preview:
        print(ascii_preview(glyphs))

    vhdl = build_vhdl(
        package_name=args.package_name,
        font_path=args.font,
        glyphs=glyphs,
        width=width,
        height=height,
        grayscale=args.grayscale,
    )

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(vhdl, encoding="ascii")

    if args.verbose:
        print(f"Package VHDL scritto in {output_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
