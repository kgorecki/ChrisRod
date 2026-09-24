# Setup

## Requirements

- [Godot 4.6.1](https://godotengine.org/download) standard build (GDScript). The .NET build is not required.
- Git, to clone the repo.
- A desktop OpenGL 3 / Vulkan / Metal capable machine for the editor. The exported game targets the Web.

No language runtime, package install, or `.env` file is required.

## Environment variables

The project reads **no environment variables**.

Local data is created by the game under Godot’s `user://` directory (OS-specific app-data path for the project name `ChrisRod`):

| File | Format | Contents |
| --- | --- | --- |
| `user://savegame.json` | JSON, `version` 1 | Car, cash, ownership, equipped gearbox, paint, opponent, race type, scene to resume |
| `user://settings.cfg` | Godot `ConfigFile` | `display/fullscreen`, `audio/master_db`, `audio/music_enabled` |

Delete those files to reset a profile. They are not in the repository.

## Get the project

```bash
git clone <repo-url> ChrisRod
cd ChrisRod
```

Open the folder in Godot 4.6 (**Import** or **Open**). The editor imports GLB, PNG, MP3, and OBJ on first load and writes caches under `.godot/` (safe to delete; Godot regenerates them).

Main scene: `res://scenes/main_menu.tscn`.

## Run

From the editor: press **F5** (Play), or the Play button. That runs the main scene.

From a shell, with `godot` on `PATH`:

```bash
# Editor import, then play the main scene
godot --import
godot
```

Headless import only (what CI does before export):

```bash
godot --headless --import
```

There is no separate dev server. Play happens inside the Godot process or a Web export.

## Web export

Preset name in `export_presets.cfg` is `Web`. Export templates for 4.6.1 must be installed (**Editor → Manage Export Templates**).

```bash
mkdir -p build/web
godot --headless --export-release "Web" build/web/index.html
```

A successful export writes `build/web/index.html`, `index.wasm`, and `index.pck`. Serve that directory with any static host. Godot’s Web export needs the [cross-origin isolation headers](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html) (`Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`) if you enable thread support later. The current preset has `variant/thread_support=false`.

`.trk` and `.obj` files are included via `include_filter` in `export_presets.cfg`. If you add another non-imported extension, add it there or the Web build will not see the file.

## Continuous integration

| Workflow | When | What it does |
| --- | --- | --- |
| `.github/workflows/export-web.yml` | Called by deploy | Godot 4.6.1, headless import, `--export-release "Web"`, uploads `web-build` |
| `.github/workflows/deploy.yml` | Push to `master`, or manual dispatch | Calls the export workflow, then deploys `build/web` to GitHub Pages |

Local export and CI use the same preset name (`Web`) and the same output checks (`index.html`, `index.wasm`, `index.pck`).

## First session in game

1. **New Game** on the main menu. Starts with $2500, the Basic Car, and the automatic 3-speed.
2. In the garage, orbit with the right mouse button and zoom with the wheel. Click the newspaper to buy parts, click the doors to race.
3. Choose **Drag race** (quarter mile) or **Road race** (course in `assets/tracks/track1.trk`), then a rival.
4. **Save** from the main menu or the garage clock. **Load** returns to the saved scene.

Controls during a race: **W / Up** throttle, **S / Down** brake, **A / D** or arrows steer, **Q / E** shift on a manual gearbox, **C** cycle camera. Narrow or touch viewports replace the keyboard hint with on-screen controls.
