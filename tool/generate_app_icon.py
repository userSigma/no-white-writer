"""Render the canonical SVG into Windows icons using local Chromium and Pillow.

Run: python tool/generate_app_icon.py [--browser PATH] [--preview PATH]
No Flutter runtime dependency or online rendering service is required.
"""
from __future__ import annotations

import argparse
import html
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'assets/branding/app_icon.svg'
SIZES = [16, 24, 32, 48, 64, 128, 256]
RENDER_SIZE = 1024


def find_browser(explicit: Path | None = None) -> Path:
    if explicit is not None:
        if not explicit.is_file():
            raise FileNotFoundError(f'Browser executable not found: {explicit}')
        return explicit.resolve()
    candidates = []
    for name in ['chrome', 'chromium', 'chromium-browser', 'msedge']:
        if path := shutil.which(name):
            candidates.append(Path(path))
    for variable in ['PROGRAMFILES', 'PROGRAMFILES(X86)', 'LOCALAPPDATA']:
        if directory := os.environ.get(variable):
            candidates.extend([
                Path(directory) / 'Google/Chrome/Application/chrome.exe',
                Path(directory) / 'Microsoft/Edge/Application/msedge.exe',
            ])
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    raise FileNotFoundError('Install Chrome/Edge or pass --browser PATH.')


def draw_icon(browser: Path | None = None) -> Image.Image:
    """Keep SVG filters, transparent corners and contain-fit aspect ratio."""
    if not SOURCE.is_file():
        raise FileNotFoundError(f'SVG source not found: {SOURCE}')
    executable = find_browser(browser)
    build = ROOT / 'build'
    build.mkdir(exist_ok=True)
    # Retain owned render/profile files under ignored build for diagnostics.
    stage = Path(tempfile.mkdtemp(prefix='svg-icon-render-', dir=build))
    page = stage / 'render.html'
    screenshot = stage / 'render.png'
    page.write_text(
        '<!doctype html><meta charset="utf-8"><style>'
        'html,body{margin:0;background:transparent;overflow:hidden}'
        f'img{{display:block;width:{RENDER_SIZE}px;height:{RENDER_SIZE}px;'
        'object-fit:contain;object-position:center}</style>'
        f'<img src="{html.escape(SOURCE.as_uri(), quote=True)}">',
        encoding='utf-8',
    )
    result = subprocess.run([
        str(executable), '--headless', '--no-first-run',
        '--no-default-browser-check', '--disable-extensions',
        '--disable-background-networking', '--disable-component-update',
        '--disable-sync', '--hide-scrollbars', '--force-device-scale-factor=1',
        '--force-color-profile=srgb', '--default-background-color=00000000',
        f'--user-data-dir={stage / "profile"}', '--window-size=1200,1200',
        '--virtual-time-budget=1000', f'--screenshot={screenshot}', page.as_uri(),
    ], capture_output=True, text=True, errors='replace', timeout=90)
    if result.returncode != 0 or not screenshot.is_file():
        raise RuntimeError(f'SVG rendering failed: {result.stderr[-2000:]}')
    with Image.open(screenshot) as rendered:
        if min(rendered.size) < RENDER_SIZE:
            raise RuntimeError(f'Unexpected browser viewport: {rendered.size}')
        square = rendered.convert('RGBA').crop((0, 0, RENDER_SIZE, RENDER_SIZE))
    image = square.resize((256, 256), Image.Resampling.LANCZOS)
    if image.getpixel((0, 0))[3] != 0 or image.getextrema()[3][1] != 255:
        raise RuntimeError('Expected opaque artwork with transparent corners.')
    return image


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--browser', type=Path, help='Local Chrome/Edge executable')
    parser.add_argument('--preview', type=Path, help='Additional PNG preview path')
    args = parser.parse_args()
    image = draw_icon(args.browser)
    output = ROOT / 'windows/runner/resources/app_icon.ico'
    image.save(output, format='ICO', sizes=[(size, size) for size in SIZES])
    image.save(SOURCE.with_suffix('.png'), format='PNG')
    if args.preview:
        args.preview.parent.mkdir(parents=True, exist_ok=True)
        image.save(args.preview, format='PNG')
    print(f'Generated {output} from {SOURCE}')


if __name__ == '__main__':
    main()
