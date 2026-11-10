#!/usr/bin/env python3
"""Assert evidence emitted by the production AppKit/Core Animation renderer."""
import json
from pathlib import Path

report=json.loads((Path(__file__).resolve().parents[1]/"artifacts/renderer.json").read_text())
assert report["fill_is_nil"] and report["interior_pixel_alpha"] == 0
assert abs(report["selected_width"]-1.4) < 0.001
assert report["animation_keypath"] == "opacity" and report["half_cycle_seconds"] == 10 and report["autoreverses"]
assert report["button_font"] == 13 and report["region_font"] == 20
# Native material is composited by WindowServer; an offscreen AppKit bitmap
# contains its fallback, not the live desktop blur. Verify tint and material separately.
glass=report["glass"]
assert glass["label_count"] == 14 and glass["backdrop_count"] == 14
assert glass["behind_window"] and glass["active_material"]
assert report["glass_style"] == "light"
assert glass["material_alpha"] == 0.62
assert glass["button_tint_alpha"] == 0.06 and glass["region_tint_alpha"] == 0.28
assert 0.5 <= report["button_background_pixel_alpha"] < 0.75
assert 0.5 <= report["region_background_pixel_alpha"] < 0.75
reduced=report["reduced_transparency"]
assert reduced["backdrop_count"] == 0 and reduced["label_count"] == 14
assert reduced["button_tint_alpha"] == 1 and reduced["region_tint_alpha"] == 1
assert abs(report["endpoint_pixel_alpha"]-0.55) < 0.005 and report["endpoint_width"] == 3
assert report["reduced_motion"]["animation_keypath"] == "none"
assert abs(report["reduced_motion"]["selected_width"]-1.4) < 0.001
print("Production renderer: transparent content, native label material, reduced transparency, endpoint and animation checks passed. Live desktop blur is not measured by offscreen rendering.")
