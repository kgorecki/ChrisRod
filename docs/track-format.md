# Track file format (`.trk`)

Race courses are stored as JSON graphs. The file extension is `.trk`. ChrisRod currently loads `res://assets/tracks/track1.trk` for the road race.

The drag strip in `scenes/race.tscn` is still a separate, hardcoded layout. It does not use this format yet.

## Coordinates

`x` and `y` are planar meters in a top-down map.

| Track | Godot world |
| --- | --- |
| `x` | `X` (right) |
| `y` | `Z` (forward when yaw is 0) |
| (height) | always `Y = 0` |

A road from `(0, 0)` to `(0, 100)` runs along world `+Z`. A road from `(0, 0)` to `(100, 0)` runs along world `+X`.

## Root object

```json
{
  "name": "Track 1",
  "nodes": [ ... ],
  "roads": [ ... ]
}
```

| Field | Required | Default | Description |
| --- | --- | --- | --- |
| `name` | no | `""` | Display name. Unused by gameplay so far. |
| `nodes` | yes | — | Graph vertices. |
| `roads` | yes | — | Directed edges between nodes. |

Unknown root fields are ignored.

## Nodes

```json
{ "id": 1, "x": 0, "y": 0, "type": "start" }
```

| Field | Required | Default | Description |
| --- | --- | --- | --- |
| `id` | yes | — | Unique integer. |
| `x` | yes | — | Planar X in meters. |
| `y` | yes | — | Planar Y in meters (world Z). |
| `type` | no | `"regular"` | `start`, `finish`, or `regular`. |

### Node types

| Type | Meaning |
| --- | --- |
| `start` | Race spawn / path origin. If omitted, the first node is used. Extra starts are ignored after the first. |
| `finish` | Race end. The path stops when it first reaches a finish node after leaving start. If omitted, the last node is used. |
| `regular` | Intermediate waypoint. The default; the field can be omitted. |

## Roads

```json
{ "from": 1, "to": 2, "width": 8, "type": "narrow-left", "surface": "wet" }
```

Roads are **directed**. `from` and `to` must name existing nodes and must differ.

| Field | Required | Default | Description |
| --- | --- | --- | --- |
| `from` | yes | — | Start node id. |
| `to` | yes | — | End node id. |
| `width` | no | `8` | Full road width in meters (not half-width). |
| `type` | no | `"regular"` | Width / shoulder variant. |
| `surface` | no | `"regular"` | Surface material. |

### Road types

A narrow side loses **one third of the full road width** from that edge. Left / right are from the driver’s view traveling `from` → `to`.

| Type | Pavement | Barriers |
| --- | --- | --- |
| `regular` | Full width. Default; can be omitted. | No |
| `narrow` | Same as `narrow-both`. | No |
| `narrow-left` | Left edge moves in by `width/3`. | No |
| `narrow-right` | Right edge moves in by `width/3`. | No |
| `narrow-both` | Both edges move in by `width/3` (remaining width is `width/3`). | No |
| `narrow-obstacle` | Same as `narrow-both-obstacle`. | Yes |
| `narrow-left-obstacle` | Same cut as `narrow-left`. | Construction barriers on the closed left strip |
| `narrow-right-obstacle` | Same cut as `narrow-right`. | Construction barriers on the closed right strip |
| `narrow-both-obstacle` | Same cut as `narrow-both`. | Barriers on both closed strips |

Hitting a `-obstacle` barrier sets the car’s speed to **0** immediately.

### Surfaces

| Surface | Meaning | Used in gameplay today |
| --- | --- | --- |
| `regular` | Default asphalt. Can be omitted. | Parsed only |
| `dry` | Dry asphalt. | Parsed only |
| `wet` | Wet / rain. | Parsed only |
| `icy` | Ice / low grip. | Parsed only |

Surface is stored on path samples for later physics and visuals. It does not change grip yet.

## Race path

The loader walks directed roads from the start node, taking the first unused outgoing road at each node, and stops when it reaches a finish node (after at least one hop).

A closing road from finish back to start is allowed (a circuit) and is **not** followed for a single-lap point-to-point race.

If the walk cannot leave start, loading fails.

## Example

```json
{
  "nodes": [
    { "id": 1, "x": 0, "y": 0, "type": "start" },
    { "id": 2, "x": 100, "y": 0 },
    { "id": 3, "x": 100, "y": 80 },
    { "id": 4, "x": 0, "y": 80, "type": "finish" }
  ],
  "roads": [
    { "from": 1, "to": 2, "width": 8 },
    { "from": 2, "to": 3, "width": 8, "type": "narrow-left" },
    { "from": 3, "to": 4, "width": 8, "surface": "wet" },
    { "from": 4, "to": 1, "width": 8 }
  ]
}
```

This is a 400 m-ish rectangle. The last road is a circuit closer and is ignored for the start→finish race path.

## Shipping

`.trk` files are not Godot-imported resources. Web export includes them through `include_filter=*.trk` in `export_presets.cfg`. Read them at runtime with `TrackFile.load_path("res://assets/tracks/....trk")`.
