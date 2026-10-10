"""Tool regression tests - every bug fixed in a tool gets a test here so it can't come back."""
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from tools.map import mapcheck  # noqa: E402
from tools.ui import uikit  # noqa: E402


def run_map(path):
    mv = mapcheck.load_movement(ROOT / "src/shared/Config/Movement.luau")
    parts = [mapcheck.Part(d) for d in json.loads(pathlib.Path(path).read_text())["parts"]]
    return mapcheck.run(parts, mv)[0]


def test_example_map_passes():
    res = run_map(ROOT / "specs/maps/example_arena.json")
    assert not any(res.values()), res


def test_broken_map_trips_every_check():
    res = run_map(ROOT / "tests/python/broken_map.json")
    failing = {k for k, v in res.items() if v}
    assert failing == set(res), f"checks that missed their planted bug: {set(res) - failing}"


def test_part_resting_on_ground_is_not_a_ceiling():
    # regression: pillars on the ground made the ground report 0 headroom
    res = run_map(ROOT / "specs/maps/example_arena.json")
    assert not any("headroom" in m for m in res["2 unstandable tops"])


def test_jump_reach_matches_physics():
    mv = mapcheck.load_movement(ROOT / "src/shared/Config/Movement.luau")
    assert mapcheck.jump_reach(mv["JumpHeight"][0], mv) == -1  # can't land at full height (margin)
    assert mapcheck.jump_reach(-10, mv) > mapcheck.jump_reach(0, mv) > mapcheck.jump_reach(3, mv) > 0


def test_ui_specs_pass_layout_checks():
    for spec_path in (ROOT / "specs/ui").glob("*.json"):
        spec, theme = uikit.load(spec_path)
        for screen in spec["screens"]:
            for name, size in uikit.SCREENS.items():
                assert uikit.check_screen(screen, theme, name, size) == [], spec_path


def test_list_layout_moves_grandchildren():
    # regression: a list moved its child but left the child's own list children behind
    spec = {"name": "S", "children": [{
        "name": "Row", "type": "Group", "size": [1, 0, 0, 200], "list": {"dir": "x", "gap": 10},
        "children": [{"name": "Card", "type": "Panel", "size": [0, 100, 0, 200], "list": {"dir": "y", "gap": 5},
                      "children": [{"name": "A", "type": "Label", "text": "a", "size": [0, 50, 0, 50]},
                                   {"name": "B", "type": "Label", "text": "b", "size": [0, 50, 0, 50]}]}]}]}
    root, _ = uikit.layout_screen(spec, uikit.DEFAULT_THEME, (1920, 1080))
    card = root.children[0].children[0]
    a, b = card.children
    assert card.rect[0] <= a.rect[0] and a.rect[0] + a.rect[2] <= card.rect[0] + card.rect[2]
    assert b.rect[1] > a.rect[1] + a.rect[3]


def test_ui_scale_matches_luau():
    src = (ROOT / "src/client/UI/Depth.luau").read_text()
    assert f"= {uikit.REF_HEIGHT}, {uikit.MIN_SCALE}, {uikit.MAX_SCALE}" in src


def test_generated_ui_is_up_to_date(tmp_path):
    for spec_path in (ROOT / "specs/ui").glob("*.json"):
        spec, theme = uikit.load(spec_path.relative_to(ROOT))
        for screen in spec["screens"]:
            committed = (ROOT / "src/client/UI/Generated" / f"{screen['name']}.luau").read_text()
            fresh = tmp_path / "g.luau"
            fresh.write_text(uikit.build_luau(spec, screen, theme))
            subprocess.run(["stylua", str(fresh)], check=True)
            assert fresh.read_text() == committed, f"rebuild UI: python -m tools.ui.uikit build {spec_path}"



def test_spec_label_uses_forward_slashes():
    # regression: Windows wrote specs\ui\hud.json into the generated header
    assert uikit.spec_label("specs\\ui\\hud.json") == "specs/ui/hud.json"
