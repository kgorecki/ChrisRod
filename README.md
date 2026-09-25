# ChrisRod

A single-player garage and street-racing game built with Godot 4.6. Buy parts, paint the car, then race a rival on a quarter-mile drag strip or a road course.

**Play in the browser:** [https://kgorecki.github.io/ChrisRod/](https://kgorecki.github.io/ChrisRod/)

Pushes to `master` export a Web build and deploy it to GitHub Pages.

## Play

| Action | Control |
| --- | --- |
| Throttle | W or Up |
| Brake | S or Down |
| Steer | A/D or Left/Right |
| Shift (manual gearbox) | Q / E |
| Camera | C |

On a phone or a narrow window, on-screen pedals and a steering wheel replace the keyboard hint.

New Game starts in the garage with cash, a basic car, and an automatic 3-speed. Click the newspaper to buy parts, and the garage doors to pick a rival.

## Run locally

Install [Godot 4.6.1](https://godotengine.org/download) (standard build, not .NET), open this folder, and press F5. The main scene is `scenes/main_menu.tscn`.

Setup, Web export, and save-file locations are in [docs/setup.md](docs/setup.md). Architecture and the track file format are in [docs/architecture.md](docs/architecture.md) and [docs/track-format.md](docs/track-format.md).
