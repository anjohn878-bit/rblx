# CONCRETE KINGS

An original Roblox social football game: a living urban "grounds" hub with caged
3v3 matches, progression, reputation, customization and AI regulars. All code,
names, UI and art are original (built from Roblox primitives, no external assets).

This repo contains the **MVP**: one hub, one 3v3 pitch, working ball physics,
passing/through balls/lobs/shooting/tackling/skill moves, goals, timer, teams,
matchmaking with bot fill, XP/levels, currency, reputation, attribute
upgrades, the Locker (shop + customization with live preview), UI and DataStore saving.

## Play it in Studio

### Option A: open the built place (quickest)
1. Download `build/ConcreteKings.rbxlx` from this branch.
2. Double-click it to open it in Roblox Studio.
3. Press **Play**. The map builds itself when the server starts.

### Option B: live-sync with Rojo (recommended for development)
1. Install [Rojo](https://rojo.space) (the Studio plugin plus the CLI, version 7.x).
2. In this folder run `rojo serve`.
3. In Studio open any place, click **Rojo → Connect**, then press **Play**.

### To test saving
Go to **Game Settings → Security**, turn on **Enable Studio Access to API Services**,
then publish the place. Without this the game still runs, but it uses temporary profiles
and warns about it in the Output window.

### Testing with several players
Go to **Test → Clients and Servers**, choose 2–6 players, and click **Start**. With one
player, join the queue (the **PLAY** button or the green pad by the cage). After 8 seconds,
AI "Regulars" fill the empty slots.

## Controls (edit them all in `src/shared/Config.luau → Config.Controls`)

| Action | PC | Gamepad | Mobile |
|---|---|---|---|
| Move | WASD | Left stick | Thumbstick |
| Sprint | Shift (hold) | RT | Sprint button |
| Pass | Left click | A | Pass |
| Shoot (hold to charge) | Right click | B | Shoot |
| Through ball | F | Y | Through |
| Lob (with ball) / Jump | Space | X | Lob |
| Tackle | E | LT | Tackle |
| Skill move | Q | LB | Skill |
| Camera mode | C | R3 | – |
| Menu | M | Select | – |

## Project layout

```
src/shared   -> ReplicatedStorage.Shared   (Config, Remotes, Progression, KickMath, Catalog, Cosmetics)
src/server   -> ServerScriptService.Server (Main + Services/*)
src/client   -> StarterPlayerScripts.Client (Main, ClientState, Controllers/*, UI/*)
tests        -> Lune unit tests for the pure modules
build        -> ConcreteKings.rbxlx (built by `rojo build -o build/ConcreteKings.rbxlx`)
```

For how the systems fit together, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Dev commands

```
rojo build default.project.json -o build/ConcreteKings.rbxlx   # rebuild the place file
selene src                                                     # lint
lune run tests/run.luau                                        # unit tests
```
