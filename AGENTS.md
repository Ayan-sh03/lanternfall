# AGENTS.md

Guide for coding agents (Claude Code, Codex, ...) changing Lanternfall. For what the game is and how to play it, read `README.md`; this file is about the code.

## Overview

Lanternfall is a dark-fantasy pixel-art dungeon crawler in Godot 4.3 (GL Compatibility renderer) for Windows and Android. GDScript only, all of it in `scripts/`. `main.tscn` is a single `Node` with `main.gd` on it; every other node is built in code. All art is drawn in code (`scripts/art.gd`); there are no image assets for sprites. Audio is in `audio/` (effects CC0, three music tracks CC-BY/OGA-BY; all listed in `CREDITS.txt`), fonts in `fonts/`. MIT licence.

## Run and build

- Local Godot 4.3: `D:\Ayan\Setup\Godot_v4.3-stable_win64.exe\Godot_v4.3-stable_win64.exe` (`Play Lanternfall.bat` launches it). Below it is written `godot`.
- Play: `godot --path .`. Nothing is imported ahead of time; there is no build step for running.
- Flags: `--3d` start in the 3D view, `--2d` force flat, `--hires` draw the world at window size, `--touch` force the touch pad, `--nobloom`. `F3` flips 2D/3D live, `F11` fullscreen, `M` mute.
- CI (`.github/workflows/build.yml`, scripts in `ci/`) exports the `.exe` and `.apk` (classic and `-3D` twins) on every push to `main` and on PRs, and publishes a release only for `main`/tags. Markdown-only pushes are skipped. The root `.bat` files do the same locally with the author's paths.
- Line endings (`.gitattributes`): LF everywhere, CRLF only for `.bat`. Indent with tabs.

## Code map

- `main.gd` (Node): entry point. Owns the HUD, save slots and profile, and the run flow. Makes `world` (a `WorldView`) and puts each new `game` inside `world.vp`. The game lives in a SubViewport and hears no input on its own, so `main._unhandled_input` forwards events to `game._unhandled_input`.
- `world_view.gd`: draws the 2D world (see next section).
- `game.gd`: one run. Floor generation (via `dungeon.gd`), player, enemies, shots, powers, pickups, fog of war, camera intent. `_process` calls `_tick(dt)` then `view.sync()`. Has a section profiler: `prof_on`, `prof`, `_pt(name, t0)`.
- `enemy.gd`: foes (husk, moth, cantor, brute, slime/slimelet, wisp, gloam, the warden boss). `hurt(amount, kb, col, snd)` is the damage entry point; `snd` names the kind of blow (`hit`, `hit_heavy`, `crit`, `burn`...) so each sounds different.
- `hud.gd` (CanvasLayer): full-resolution UI; labels over the world are placed with `game.screen_pos`. `touch.gd`: on-screen pad. `story.gd`: all the writing.
- `fx.gd`: particles, arcs and rings, drawn with `_draw`. `surfaces.gd`: oil, fire, webs, water, slick. `echo.gd`, `moth.gd` (Flit), `nemesis.gd`: features.
- `view3d.gd`: optional 3D renderer that watches the 2D state and re-draws it; game rules never run in 3D.
- `sfx.gd`: autoload `Sfx`, see Audio. `art.gd`: static class holding every texture.
- Tours and tests: `autotest.gd` (harness), `wildtest.gd`, `showcase.gd`, `showreel.gd`, `wildreel.gd`.

## Rendering pipeline (world_view.gd)

The 2D world is drawn into a small `SubViewport` at one pixel per art pixel, then scaled up (nearest filter) behind the full-resolution HUD. 3D mode and `--hires` use the same SubViewport at full size.

- `game.cam` (Camera2D) is disabled (`cam.enabled = false`). It is only the intended camera: game logic, cutscenes and reels set its `position`/`zoom`/`offset`. `world_view.sync()` (process priority 1000, runs after everyone has moved the camera) turns it into `vp.canvas_transform`, snaps to whole art pixels, and slides the picture by the leftover fraction so motion stays smooth.
- `view_xf` maps world-picture pixels to window (HUD) units.
- Never use `get_viewport()` size, mouse or canvas transform from game-side code for screen maths; it is the small world picture, not the window. Use `game.screen_pos(p)`, `game.mouse_world()`, `game.view.screen_size()`, `game.view.screen_mouse()`, `game.view.view_mouse()`. These handle 2D and 3D.
- The 3D camera's `unproject_position` returns world-picture pixels; multiply by `game.view.view_xf` to get window units (see `view3d_test` in `autotest.gd`).

## Conventions and gotchas

- Comments are plain English, full sentences, explaining why, in the game's voice. Use `##` doc comments at the top of a script and on non-obvious functions. Match the surrounding style rather than adding banners or restating the code.
- Static typing where practical (`var x: float`, `-> void`), tabs for indentation.
- Never call `texture.get_image()` at runtime: on GL Compatibility it reads back from the GPU and stalls 20-25 ms. Use `Art.image_of(tex)`, which returns the CPU image the art was built from. (Only the test harness and `--icons` do readbacks.)
- Do not create a `ShaderMaterial` per object for one-off effects; share them (death ghosts use `Art.ghost_mat`). Enemies still own one material each for the hit flash.
- Avoid per-frame allocations in `_tick`, `enemy.gd` and `fx.gd`. Keep work off the first-kill and first-spawn path (build or cache things when the floor loads).
- Saves go through `main.gd`; the test harness uses slot 9 and deletes it.

## Testing

There is no unit-test framework; `scripts/autotest.gd` is the harness. Run from the repo root, with `godot` as above:

```
godot --path . -- --autotest --<mode> [--shotdir=<dir>]
```

Modes (dispatched in `run()` near line 990): `--quick`, `--mechanics` (combat rules, parry etc.), `--progress` (profile, saves, upgrades), `--wild` (wildtest.gd, random play), `--ui` and `--anim` and `--sheet` (screenshots), `--touch`, `--icons` (rewrites `windows/icon.png`), `--view3d` (checks the 3D mouse aim projects back to the cursor, view switching, saves shots), `--perf`, `--perfab`, `--audio` (every cue named in the scripts resolves to a sound; voice limits hold). With no mode it plays every floor with a bot and saves screenshots to `--shotdir`.

- Results are printed lines tagged with the area (`MECH`, `VIEW3D`, `PERF`...); read them for `ok` / `FAIL` / `PASS`. `--view3d` ends with `VIEW3D PASS` or `VIEW3D FAIL n`.
- Harmless noise at shutdown: "Unreferenced static string", "Pages in use exist at exit", "PagedAllocator".
- Nothing tests 2D mouse aim yet. If you touch `mouse_world`, `view_xf` or `sync()`, check the cursor by hand in 2D, or add a test.
- Video: `godot --path . --write-movie out.avi --fixed-fps 30 -- --autotest --wildreel` (also `--showreel`).
- Headless runs skip drawing; `shot()` just steps a frame.

## Performance

Measured on an Intel Iris Xe laptop (Oct 2026).

- Benchmark: `godot --path . --disable-vsync --max-fps 0 -- --autotest --perf --2d`. Prints `PERF` lines: fps, frame avg/p99/worst, script ms (timed from the first to the last `_process`), draw CPU/GPU ms for the window and the world picture, draw calls, node count, and a per-section game-update breakdown (avg/worst ms). `--perfab` turns layers off one at a time (lights, glows, fog, fx, surfaces, decals, map, enemies, hud, full-size world), each against a fresh baseline.
- The laptop throttles; absolute numbers drift up to 2x between runs. Only trust back-to-back A/B pairs.
- Found and fixed: (1) pixel art drawn at window size (now world_view: GPU 5-15 ms down to about 2 ms; a 30-enemy fight went from 45-80 to 180-205 fps, walking from 60-127 to about 190); (2) 2D `PointLight2D`s were about 55% of GPU time at full size, about 10% now; (3) the first kill of each foe type stalled on `get_image()` (now `Art.image_of`; the 3D normal maps had the same bug).
- Still costly: enemy AI is about 65% of script time (`enemy._separate` is O(n^2) with a `move_body` per pair; `_animate` sets shader params and textures every frame; `enemies.duplicate()` each frame in `game.gd`). About 900 particles are Dictionaries updated and drawn one by one in `fx.gd`. One ShaderMaterial per enemy prevents batching. An empty Godot 4.3 GL project only reached about 215-357 fps here, so the engine/driver floor is near. Occasional frames where every section takes about 15.6 ms at once look like the OS descheduling the main thread (cause not found).
- Rules: measure before optimising; run the A/B on the same build back to back; do not trade correctness for a gain you cannot show.

## Audio

`sfx.gd` is the `Sfx` autoload. It keeps a pool of `AudioStreamPlayer`s. Recorded effects are loaded from `audio/sfx/`; the id is the filename minus `_<n>.ogg` (`bell_0.ogg`, `bell_1.ogg` are variants of `bell`). Music tracks live in `audio/music/`. A set of cues is also synthesised at startup on a thread (`_build_sfx`); a recording wins over a synthesised cue of the same id, and an id with neither plays nothing. The autotest prints `AUDIO n recorded sounds, m music tracks` on start.

- `ALIAS` maps a cue with no sound of its own to one that has (`crit` falls back to `hit_heavy`, then `hit`). `resolve()` prefers a cue's own files, so adding `<cue>_0.ogg` is all it takes to give it a voice.
- Voices are managed: `PRIO` (a death cry outranks a footstep), `GAP` (a repeat of the same cue within the gap is dropped, so a burst of 30 hits plays once), `MAX_SAME` (concurrent copies per cue). A new sound only steals a voice of equal or lower priority.
- `FILE_VOL` trims each recorded cue's level in dB. New takes were level-matched to the loud part of the sound they replaced; keep doing that so the mix holds.
- Every `.ogg` needs a `.ogg.import` holding `[remap]` and `importer="keep"`; the export filter includes `*.ogg`.

## Assets and licences

Only CC0, CC-BY or OGA-BY (or OFL for fonts) assets; attribution licences need the author credited in `CREDITS.txt`, which ships in the game. Record every new file in `CREDITS.txt` (title, author, source URL, licence) in the same change. Sprites and tiles are drawn in code, not imported.

## Git workflow

- Never commit to `main` directly: branch, push, open a PR. Every push to `main` publishes a release.
- Commit subject: short, imperative, no trailing full stop (for example "Draw the world at the art's own pixel size, and stop the first-kill stalls"). Body wrapped at about 72 columns, saying why and what was measured, not a list of edits.
- Keep commits focused; do not reformat files you are not changing. `.godot/`, `build/`, `*.mp4`, `*.avi` are ignored.
