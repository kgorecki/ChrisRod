# Tech stack

ChrisRod is a Godot 4.6 project written entirely in GDScript. It does not use C#, GDExtension, third-party addons, or a package manager.

## Core

| Piece | Choice |
| --- | --- |
| Engine | Godot 4.6 (`config/features` in `project.godot`). CI pins **4.6.1**. |
| Language | GDScript. `TrackFile` is the only `class_name`. |
| Renderer | Default Forward+ 3D. No custom shaders. |
| Window | 1280×720. |
| Physics | `CharacterBody3D` with `MOTION_MODE_FLOATING`. Motion is scripted, not `VehicleBody3D`. |
| UI | Godot `Control` nodes. Race tachometer and touch controls are drawn in `_draw`. |
| Audio | Looping MP3 for music. Engine noise is an `AudioStreamGenerator` at 22050 Hz. |
| Data | JSON dictionaries in code and in `.trk` files. Settings use `ConfigFile`. |
| Export | Web only (`export_presets.cfg`, preset name `Web`). |

## Libraries

None. Gameplay, UI, mesh building, STL/GLB loading, and audio synthesis are engine APIs plus project scripts.

Godot imports GLB, PNG, MP3, and OBJ through the normal import pipeline (`.import` sidecars). `.trk` files are read with `FileAccess` at runtime and are pulled into the Web pack by `include_filter=*.trk,*.obj`.

## Conventions

- **Scene and script pairs.** Each screen is `scenes/<name>.tscn` with `scripts/<name>.gd`. Race subsystems (`player_race_car`, `race_track`, `rpm_meter`, and so on) are child nodes of `race.tscn`.
- **One autoload.** `GameState` is the shared model. Do not add another singleton unless the data must outlive a scene change.
- **Catalogs are `const` arrays of dictionaries** on `GameState` (`PARTS`, `GEARBOXES`, `USED_CARS`, `OPPONENTS`). Ids are strings except opponent ids, which are integers `0..2`.
- **Purchases return an empty string on success** and a short player-facing error otherwise (`buy_part`, `buy_or_equip_gearbox`, `buy_or_select_car`).
- **Cross-node calls use `has_method`.** Race code does not cast to script types except `TrackFile`.
- **Input is raw keys**, not the Input Map. Desktop: W/Up throttle, S/Down brake, A/D or arrows steer, Q/E shift, C camera. Touch controls override those when visible.
- **World axes.** Planar track `x` is world X. Planar track `y` is world Z. Height is always Y = 0. Car yaw 0 faces `+Z`.
- **Interaction in the garage** is a physics ray plus a `garage_interact` meta tag on the collider or an ancestor. Track barriers use `track_obstacle`.
- **Paint** is a `StandardMaterial3D` override applied after the body mesh loads (`stl_loaded`).

## Design patterns

**Autoload as the model.** Scenes are views and controllers. They read and write `GameState`, then change scene. Save files are a JSON snapshot of that model (`version: 1`).

**Shared visual scene.** `car_vehicle_visual.tscn` is instanced under the garage pivot and both race cars. `stl_mesh_instance.gd` loads GLB (or STL) at runtime, caches `ArrayMesh` results, recenters, and scales to a target height. `car_vehicle_visual.gd` scales wheels and aligns them to a floor mesh.

**Data-driven track, code-driven catalogs.** Courses are external JSON graphs ([track-format.md](track-format.md)). Cars, parts, and rivals are still hardcoded catalogs.

**Sampled path.** `race_track.gd` turns the graph into evenly spaced samples (`BAKE_STEP = 2` m) with fillets on corners. Gameplay queries samples instead of the raw graph:

- `closest_sample` — player off-road test and obstacle edges.
- `sample_at` — opponent placement along arc length.
- `remaining_distance` — HUD and road-race finish.

**Arcade drivetrain.** Each gear has a top speed from its ratio versus the top gear. Acceleration scales with ratio and horsepower, then falls off as speed approaches that gear’s top (`1 - progress²`). A shift timer blanks throttle. The reference first-gear ratio is `2.80` and the reference launch is `24` m/s².

**Procedural props.** Drag curbs, the finish gantry, the road mesh, signs, and the garage calendar are built in `_ready`, mostly with `MultiMesh` and `ArrayMesh`. They are not authored as separate scenes.

**Feature flags by race type.** `GameState.selected_race_type` chooses layout. On a road race, `track_visuals.gd` skips the strip, and `race.gd` disables the drag ground so only the baked road collides.
