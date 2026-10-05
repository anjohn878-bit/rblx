# Grow a Bird Garden

A cozy, idle-style Roblox game in the spirit of *Grow a Garden* — but instead of harvesting
crops, you grow plants to **attract birds**.

> Buy seeds → plant them → **wait** → the plant blooms → birds come to visit → they pay you in
> **feathers** → spend feathers on better seeds.
>
> **Better seeds take longer to grow, and attract better birds.** The player waits; the garden
> does the rest.

## Play it

1. Open **`GrowABirdGarden.rbxlx`** in Roblox Studio.
2. Press **Play** (Studio's *Play* button, not *Run*, so you get a character).
3. In Studio only, a red **DEV** panel appears on the right: *+100K feathers*, *+5 of every seed*,
   *grow all plants*, *unlock all plots*, *fill shop stock*. Use it to see the whole game in a few
   minutes. It never appears (and the server ignores it) in a published game.

To publish: **File → Publish to Roblox**, then in *Game Settings*:

- **Security → Enable Studio Access to API Services** (lets you test saving in Studio)
- **Places → Max Players: 8** (the map has 8 gardens; a 9th player is politely kicked)

## How it plays

| | |
|---|---|
| **Seed hotbar** (bottom) | Click a slot or press `1`–`6` to choose the seed to plant. |
| **Plant** | Walk up to one of *your* soil plots and press `E`. |
| **Wait** | A floating label shows each plant's name and countdown. Growth continues **while you're offline**. |
| **Birds** | Once bloomed, a plant gets visitors. A bird flies in, lands on a perch, **pays feathers**, stays a while, and flies off. |
| **Discover** | The first time you see a species you get a **×5 bonus** and a banner. |
| **Seed Shop** | Button on the left, or the red kiosk in the plaza. Stock is limited and restocks every 3 minutes on a global clock. |
| **Birdpedia** | Button on the left (or `B`). Undiscovered birds are silhouettes with a hint about which seed attracts them. |
| **More plots** | The next locked plot shows an unlock prompt. 4 plots to start, 12 max. |
| **Dig up** | Hold `X` on a plant. Digging up a *growing* plant returns the seed; a *grown* plant is lost. |

A one-line **objective bar** at the top always tells you what to do next.

## The seeds and the birds

Each seed mostly draws birds of its own tier, with about a 3% chance of a "lucky visit" from the tier above.

| Seed | Rarity | Price | Grows in | Perches | Attracts |
|---|---|---:|---:|---:|---|
| **Sunflower** | Common | 15 | 20 sec | 1 | House Sparrow, Goldfinch, Mourning Dove |
| **Berry Bush** | Uncommon | 140 | 1.5 min | 1 | Robin, Chickadee, Eastern Bluebird |
| **Cherry Blossom** | Rare | 2,100 | 5 min | 2 | Blue Jay, Cardinal, Baltimore Oriole |
| **Hibiscus** | Epic | 13,000 | 15 min | 2 | Ruby Hummingbird, Sunny Parakeet, Kingfisher |
| **Golden Apple Tree** | Legendary | 140,000 | 40 min | 3 | Toucan, Scarlet Macaw, Peacock |
| **Starbloom** | Mythic | 1,050,000 | 2 hr | 3 | Aurora Owl, Celestial Quetzal, Phoenix |

Every perch on a plant is an independent visitor slot, so multi-perch plants earn proportionally more.

| Bird | Rarity | Feathers per visit |
|---|---|---:|
| House Sparrow | Common | 3 |
| Goldfinch | Common | 5 |
| Mourning Dove | Common | 8 |
| Robin | Uncommon | 18 |
| Chickadee | Uncommon | 26 |
| Eastern Bluebird | Uncommon | 36 |
| Blue Jay | Rare | 110 |
| Cardinal | Rare | 150 |
| Baltimore Oriole | Rare | 210 |
| Ruby Hummingbird | Epic | 520 |
| Sunny Parakeet | Epic | 720 |
| Kingfisher | Epic | 1,050 |
| Toucan | Legendary | 3,000 |
| Scarlet Macaw | Legendary | 4,200 |
| Peacock | Legendary | 6,400 |
| Aurora Owl | Mythic | 22,000 |
| Celestial Quetzal | Mythic | 31,000 |
| Phoenix | Mythic | 48,000 |

### Economy (measured by simulating the real scheduler for 6 hours per seed)

| Seed | Feathers/min per plant | Price | Pays for itself in |
|---|---:|---:|---:|
| Sunflower | 7 | 15 | 2.0 min |
| Berry Bush | 46 | 140 | 3.0 min |
| Cherry Blossom | 519 | 2,100 | 4.0 min |
| Hibiscus | 2,657 | 13,000 | 4.9 min |
| Golden Apple Tree | 23,635 | 140,000 | 5.9 min |
| Starbloom | 153,622 | 1,050,000 | 6.8 min |

Payback time rises smoothly with tier, so each upgrade feels a little more like an investment, and the
*growth* time is what makes the player wait. A new player (30 feathers + 3 free sunflowers) sees
their first bird about 30 seconds in, and can afford a Berry Bush after roughly 4 minutes.
Everything is tunable in `src/shared/Config.luau`, `Seeds.luau` and `Birds.luau`; the test suite
re-runs the simulation and fails if a change breaks these progression rules.

## How it's built

All content is generated from code, so there are **no uploaded assets to manage**: the map, the 6
plants and 18 birds are built from primitive parts at runtime, and the UI is built in code.

```
src/
  shared/    ReplicatedStorage.Shared    rules + content, usable by server and client
    Config, Seeds, Birds                 every tunable number
    Growth, Scheduler, BirdFlight        pure logic: growth, shop restock, visit state machine, flight paths
    PlantModels, BirdModel               procedural models (also used for the shop/Birdpedia 3D previews)
    Remotes, Signal, Clock, Format, Types
  server/    ServerScriptService.Server  all authority
    DataService      DataStore profiles: retries, validation, Studio fallback, autosave, BindToClose
    WorldBuilder     ground, plaza, shop kiosk, 8 gardens, lighting
    GardenService    garden ownership + plot visuals
    PlantService     plant / grow / bloom / dig (growth is derived from a timestamp)
    BirdService      runs visits and pays feathers
    ShopService      shared stock on a global restock clock, plot unlocks
    DevService       Studio-only cheats
  client/    StarterPlayerScripts.Client UI and rendering
    Hud, Hotbar, ShopUI, BirdpediaUI, Toasts, Objective
    PlantLabels, Prompts, BirdRenderer
tests/       unit + simulation tests (see below)
```

Design decisions worth knowing:

- **Server-authoritative.** Clients only render and send requests; every remote is rate-limited and
  validated (types, ranges, ownership, stock, price).
- **Waiting is cheap.** Plants store only a *planted-at* time; growth, offline progress and the
  countdown labels are all computed from it, with no per-second network traffic.
- **Birds cost almost no bandwidth.** The server sends one small message per visit. Every client
  animates the bird locally from a deterministic flight function (`BirdFlight`), so players who join
  mid-visit see the bird in the right place.
- **Fair, global shop.** Restock rolls are seeded by the restock number, so every server shows the
  same shelves, as in the original game; stock is shared by everyone on a server.
- **Safe saving.** A failed load never lets someone play on default data (they're asked to rejoin,
  so their real save can't be overwritten). In Studio without API access the game still plays,
  unsaved. Saved data is sanitised on load.
- **No soft-locks.** A player with no plants, no seeds and too few feathers gets a free sunflower seed.

## Developing

The source is a normal [Rojo](https://rojo.space) project (7.4+):

```
rojo serve                                        # live-sync into Studio
rojo build default.project.json -o GrowABirdGarden.rbxlx   # rebuild the place file
```

### Tests

The tests run under the standalone [Luau](https://github.com/luau-lang/luau) CLI. They load the **real**
source files into a small fake of the Roblox engine (`tests/robloxmock.luau`: instance tree, CFrame
math, a virtual-time scheduler, an in-memory DataStore, players, remotes):

```
node tests/run.js            # all specs
node tests/run.js server     # just the ones whose name contains "server"
```
(set `LUAU=/path/to/luau` if `luau` isn't on your PATH)

| Spec | What it covers |
|---|---|
| `logic` | content tables, growth, deterministic shop restock, scheduler, flight paths, and the economy simulation |
| `models` | every plant/bird model: perches sit on real surfaces, plants fit their plots, birds pose and flap |
| `server` | the real server script end-to-end: join, plant, grow, bloom, bird visits, shop, plots, digging, saving, rejoining after being offline, 8 players, bad input, DataStore outages, save-data corruption, shutdown |
| `client` | the real client script bridged to a live server world: HUD, hotbar, prompts, shop, Birdpedia, bird rendering frame by frame, toasts, long idle sessions |

Type-check against the real Roblox API with [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp)
(every file is `--!strict`), and format with [StyLua](https://github.com/JohnnyMorganz/StyLua)
(`stylua.toml` is included):

```
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json src
stylua src tests
```

## What has and hasn't been verified

Built without access to Roblox Studio, so be aware:

- **Verified:** the code type-checks cleanly in strict mode against the real Roblox API definitions;
  the 6,000+ automated checks above pass; the built `.rbxlx` is well-formed and every script in it is
  byte-identical to `src/`.
- **Not verified:** how it *looks and feels* in the real engine. Colors, proportions, UI layout on
  your screen size, camera and lighting have never been seen by a human, and the mock engine can't
  catch a Roblox behavior that differs from the documentation. Real DataStore behavior was only
  exercised against an in-memory fake.

So the first thing to do is **playtest it** (including on a phone-sized emulator) and tweak what
you see. Everything visual is in `WorldBuilder`, `PlantModels`, `BirdModel` and the `client/` UI
modules, and it's all plain code.

Ideas for next steps: sound effects, weather/"mutation" bonuses, bird-feeder upgrades, trading,
pets that follow you, a rebirth/prestige loop.
