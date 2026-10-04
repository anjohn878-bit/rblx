# Build a Marble Run 🔮

A Roblox game where every player gets a plot, builds a marble track from a start tower down to a
Goal cup, and earns coins every time a marble makes it to the finish.

## Play it

Open **`Place1.rbxlx`** in Roblox Studio and press **Play**. The scripts are already inside the
place file. (`Place1.rbxl` is the old empty binary place and doesn't have the game in it.)

To publish, use *File → Publish to Roblox*. Enable *Game Settings → Security → Enable Studio Access
to API Services* if you want saving to work while testing in Studio. Set the server size to 6
players, since there are 6 plots.

## How to play

| Action | Keyboard / mouse | Mobile |
| --- | --- | --- |
| Pick a piece | `1`–`8` or click the hotbar | tap the hotbar |
| Place piece | left click | tap |
| Rotate | `R` | ⟳ button |
| Raise / lower the build height | `E` / `Q` | ▲ / ▼ buttons |
| Delete mode (full refund) | `X` | 🗑 button |
| Drop a marble | `F` | 🔮 button |

* Pieces **auto-snap**: hover the cell after the end of your track and the new piece rotates and
  sets its height to connect.
* Each piece drops the marble by a set number of levels. A piece's entry has to line up with the
  previous piece's exit.
* Get the marble into your **Goal** cup to earn coins:
  `10 + 3 × pieces touched + 2 × seconds of travel + chime bonuses`.
* Spend coins on more pieces. Longer and fancier runs pay more.

### Pieces

| Piece | Cost | Notes |
| --- | --- | --- |
| Ramp | 5 | drops 1 level |
| Curve L / R | 8 | 90° turn, drops 1 level |
| Steep | 10 | drops 4 levels |
| Flat | 4 | no drop |
| Booster | 25 | flat, launches the marble forward |
| Chime | 15 | rings a bell, +1 coin per run |
| Goal | free | the finish cup (1 per plot) |

## Project layout

```
src/
  ReplicatedStorage/MarbleRun/Config.luau      shared tuning (grid, prices, rewards)
  ReplicatedStorage/MarbleRun/Pieces.luau      piece definitions + geometry builder
  ServerScriptService/MarbleRunServer.server.luau   plots, building, marbles, saving
  StarterPlayerScripts/MarbleRunClient.client.luau  UI, ghost preview, input, camera
tools/build_place.py                           copies src/ into Place1.rbxlx
default.project.json                           Rojo project (optional)
```

After editing anything in `src/`, run `python3 tools/build_place.py` to update `Place1.rbxlx`, or
use [Rojo](https://rojo.space) (`rojo serve`) to sync live into Studio.
