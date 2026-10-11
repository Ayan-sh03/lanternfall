"""Packs windows/icon.png into windows/icon.ico (the icon of the Windows .exe).
Run after regenerating the icons with:  godot --path . -- --autotest --icons"""
import os
from PIL import Image

here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = Image.open(os.path.join(here, "windows", "icon.png")).convert("RGBA")
# Whole-number reductions of the 256 px art stay crisp; the rest are smoothed.
sizes = [256, 128, 64, 48, 32, 16]
frames = [src.resize((n, n), Image.NEAREST if 256 % n == 0 and n >= 64 else Image.LANCZOS) for n in sizes]
frames[0].save(os.path.join(here, "windows", "icon.ico"), format="ICO", sizes=[(n, n) for n in sizes],
    append_images=frames[1:])
print("wrote windows/icon.ico")
