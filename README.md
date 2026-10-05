# ❄ Ice Skating Simulator

A Roblox skating simulator. Glide around frozen rinks, land spinning jumps,
collect golden snowflakes, buy faster skates, unlock bigger rinks and rebirth
for permanent boosts.

## Play it

Open **`Place1.rbxl`** (or `Place1.rbxlx`) in Roblox Studio and press **Play**.
The map, scripts and lighting are already in the place.

To make progress save between sessions, publish the place and turn on
**Game Settings → Security → Enable Studio Access to API Services**. Without it
the game still works, it just starts every player fresh.

## How it plays

| Action | Keyboard | Gamepad | Touch |
| --- | --- | --- | --- |
| Skate / carve | WASD | Left stick | Thumbstick |
| Jump (spins automatically) | Space | A | Jump button |
| Scratch spin | F | Y | **Spin** button |
| Hockey stop | Hold the direction opposite your glide | Pull back | Pull back |

- **Skating** builds momentum. Speed carries, turns carve, and pushing against your glide does a hockey stop with a spray of snow.
- **Jumps** spin you in the air. The faster you're going and the higher you jump, the more rotations you land: Single, Double, Triple, Quad, then Quint. Each jump gets a random name (Axel, Lutz, Flip, and so on).
- **Combos**: land tricks within 4 seconds of each other to stack up to a ×3 bonus.
- **Snowflakes ❄** come from distance skated, tricks, and golden snowflakes scattered on the ice.

### Progression

| | |
| --- | --- |
| **Skates** | Rental → Hockey → Figure → Speed → Golden → Diamond → Aurora. Each pair is faster and earns more. |
| **Upgrades** | *Leg Power* (top speed), *Spring Jumps* (jump height, so more rotations), *Showmanship* (trick snowflakes). |
| **Rinks** | Frozen Pond ×1 (free), Pine Lake ×2, Glacier Bay ×4, Aurora Arena ×8. Unlock them at their glowing gates. |
| **Rebirth** | Spend snowflakes at the Rebirth Crystal. You reset skates, upgrades and snowflakes, keep your rinks, and get +0.5× earnings for good. |

The lobby also has the **Skate Shop**, the **Rebirth Crystal** and a **Top
Skaters** board showing lifetime snowflakes.

## Project layout

```
src/
  shared/            -> ReplicatedStorage.Shared
    Config.luau        every tunable number: skates, upgrades, rinks, tricks, prices
    Formulas.luau      derived stats & prices (used by both server and client)
    Format.luau        number formatting (1.25M)
    Remotes.luau       all RemoteEvents / RemoteFunctions
    Signal.luau
  server/            -> ServerScriptService.Server
    Main.server.luau
    Services/
      DataService        loading, saving & syncing player data, leaderstats
      SkaterService      character setup, server-side distance earnings, rink locks
      SkateGear          skate blades + ice trails on characters' feet
      TrickService       validates and scores tricks, combos
      ShopService        skates, upgrades, rink unlocks, rebirths
      CollectibleService golden snowflakes
      LeaderboardService the Top Skaters board
      WorldBuilder       builds the whole map from parts
  client/            -> StarterPlayer.StarterPlayerScripts.Client
    Main.client.luau
    Controllers/
      SkateController    skating physics, jumps, spins
      SkatePoser         procedural skating animation (R15)
      HUD, ShopUI, UI    interface
      Effects            snowfall, FOV, sprays, sparkles
      RinkGates          opens unlocked rinks for you
      ClientData         local copy of your profile
.lune/
  build.luau         rebuilds Place1.rbxl / Place1.rbxlx from src/
  test.luau          offline checks for the shared logic and config
default.project.json Rojo project (same layout)
```

The server is authoritative. Snowflakes for skating are measured from your
position on the server. Tricks are checked against what your speed and jump
height make possible. Purchases are priced on the server.

## Editing

`src/` is the source of truth. After changing code or `Config.luau`, rebuild the
place files with [Lune](https://lune-org.github.io/docs) (`rokit install` sets
up the pinned versions):

```sh
lune run test    # offline checks
lune run build   # writes Place1.rbxlx and Place1.rbxl
```

The build keeps everything else in `Place1.rbxlx`. It only replaces the script
folders and regenerates `Workspace.Map`, so don't hand-edit those inside Studio.
Do your Studio-side tweaks elsewhere, or move them into `WorldBuilder`.

You can also live-sync the scripts with [Rojo](https://rojo.space) using
`default.project.json`. If a place has no `Workspace.Map`, the server builds the
map when it starts.
