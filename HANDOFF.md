# Lanternfall: handoff

Where things stand, for picking the work up locally.

## Branches

| Branch | What is on it |
|---|---|
| `main` | The released game, without any of the work below. |
| `claude/repo-testing-9x92x5` | 2.5D billboard 3D view (F3), game feel, parry, lantern and gloams, fair deaths, town, deeds, duo kindlings, nemesis, oil and fire, snuffing the lamp, echo, Flit, hollow walls. CI green. |
| `claude/lowpoly-3d` | Everything above, plus the full 3D overhaul (rigged models, kit dungeon, Forward+ look, 3D title). **This is the latest.** |

Merging `claude/lowpoly-3d` into `main` publishes a release with all four builds (classic and 3D, `.exe` and `.apk`). Pushing a `v*` tag also publishes one.

## Running

```
godot --path . -- --3d                                     # 3D, lighter renderer
godot --path . --rendering-method forward_plus -- --3d     # 3D, full look (Vulkan)
godot --path . -- --2d                                     # classic flat view
```

- `F3` switches between 3D and flat at any time.
- In 3D: middle-drag or `[` `]` turns the camera (on touch, drag the open right side), the wheel zooms, `Home` resets.
- Debug flags:

| Flag | Effect |
|---|---|
| `--lowfx` | No Forward+ effects. |
| `--pixel3d` | Old pixel-block dungeon. |
| `--billboards` | Old cut-out characters. |
| `--nobloom` | No bloom. |
| `--dof` | Depth of field on (off by default; it blurred Wren). |

## Tests (all pass on `claude/lowpoly-3d`)

```
godot --headless --path . -- --autotest --mechanics --3d   # parry, reflect, lantern, gloams
godot --headless --path . -- --autotest --progress --3d    # mercy, resolve, embers, town, deeds, duos
godot --headless --path . -- --autotest --wild --2d        # oil/fire, snuff, echo, nemesis, Flit, hollow walls
godot --headless --path . -- --autotest --models --3d      # 3D figures, animations, camera turn/zoom
godot --headless --path . -- --autotest --view3d           # 3D aim round-trip, F3, kills
godot --path . -- --autotest --3d --shotdir=shots          # full 7-depth playthrough with screenshots
```

- Add `--shotdir=<dir>` (with a display) to any of these for screenshots.
- `--models --tour` takes one picture per depth.
- `--models --title` checks the 3D title.

CI (`ci/build.ps1`) runs mechanics, progress, wild and models, then exports four files. Windows exports retry up to three times, and the build folders are excluded from Defender (it was locking the half-written pack).

## Recordings

```
godot --path . --rendering-method forward_plus --write-movie trailer.avi --fixed-fps 30 -- --autotest --aaareel   # ~45 s 3D trailer
godot --path . --write-movie reel.avi --fixed-fps 30 -- --autotest --wildreel     # feature tour
godot --path . --write-movie tour.avi --fixed-fps 30 -- --autotest --showreel     # depth 1 tour
```

Convert with `ffmpeg -i trailer.avi -c:v libx264 -crf 21 -pix_fmt yuv420p trailer.mp4`.

## Architecture (3D)

The game rules still run entirely in 2D (`game.gd`, `enemy.gd`, 16 px tiles). The 3D view only reads that state each frame. Mapping: 2D x is 3D x, 2D y is 3D z, one tile is one unit.

| File | Role |
|---|---|
| `scripts/view3d.gd` | Camera (orbit and zoom), lights, environment and per-depth moods (`MOODS`), effects mesh (`FX_ADD` shader modes: flat, soft spark, sweep), surfaces, hollow-wall cracks, torches, dust, post pass. `aaa` is true on Forward+. |
| `scripts/dungeon3d.gd` | Kit dungeon as chunked MultiMeshes: floors, wall segments on edges, pillars, torches, decoration, stairs. `KIT_SHADER` handles fog of war, the camera-relative cutaway and the depth tint. |
| `scripts/actors3d.gd` | Rigged figures driven by game state (animation choice, heading, flash); props (chest, brazier, urn, lamp, stair seal); Flit; corpses. Fills `skip` so the cut-out sprites are not drawn. |
| `scripts/creatures3d.gd` | Shape-built ink maw, cinder skull, bat and moth. |
| `scripts/title3d.gd` | The 3D hall behind the title menu (`main.title_scene()`). |
| `models/*.glbx`, `models/kit/*.glbx` | KayKit CC0 `.glb` files: characters stripped to the animations used, renamed so they ship raw. Loaded at run time with `GLTFDocument.append_from_buffer`; no import step. |
| `project.godot`, `export_presets.cfg` | `renderer/rendering_method.aaa="forward_plus"`. The Windows 3D preset has `custom_features="view3d,aaa"`. |

## Gameplay systems added this session (all in `game.gd` unless noted)

| System | Where |
|---|---|
| Oil, fire, webs, water | `surfaces.gd` |
| Snuff and flare | `snuff()`, `relight()`, `_flare()`; enemy `lost` / `seen_at` |
| Echo | `echo.gd`, `_spawn_echo()`, `_record_echo()` |
| Nemesis | `nemesis.gd`, `_place_nemesis()`, `nemesis_woke()`, `_nemesis_fell()`; `profile["nemesis"]` |
| Flit | `moth.gd`, `_place_wild_moth()`, `_make_moth()`; saved in the save game |
| Hollow walls | `_carve_secrets()`, `open_secret()`, `secret_hint()`; `secrets_open` in the save |

## Known gaps and next steps

1. **Unverified in an exported build:** the Forward+ feature override in the Windows 3D export. If it doesn't apply, the build falls back to the lighter look; nothing breaks.
2. **Tuning on a real GPU:** lighting was tuned on a software renderer (lavapipe). Check brightness and haze; see `_grade()`, `MOODS`, and the light multipliers in `_mirror_light()` and `_torch()`.
3. **Mobile:** the Android 3D build runs on the Compatibility renderer and has not been performance-tested with the models on a phone.
4. **Not built yet:**
   - The dark eating the HUD.
   - A restyled HUD.
   - A 3D look for the town screen.
   - Flit visible on the title (the nemesis now waits there, in `title3d._nemesis()`).
   - Touch pinch to zoom (a drag on the open right side already turns the camera, `touch.gd` `cam_id`).
5. **Balance:** first guesses for flask cost (20), flare cooldown (5 s), echo damage (50%), gloams while snuffed, nemesis HP and payout, and Flit's bite.
