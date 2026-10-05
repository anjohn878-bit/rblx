# Become a Delivery Driver

A Roblox game where you start on a scooter and work your way up to a hyper-car, delivering parcels around a small town for cash, tips and rank.

## Play it

1. Open **`Place1.rbxl`** (or `Place1.rbxlx`) in Roblox Studio.
2. Press **Play** (F5).

You spawn at the **Swift Drop Depot** in the middle of town. The whole town is already built into the place, so you can fly around it in the edit view too.

### How to play

| Step | What to do |
| --- | --- |
| 1. Take an order | Walk or drive up to the **DISPATCH** counter and press **E** (tap the prompt on mobile). |
| 2. Hit the road | Your vehicle appears and you're seated in it. Drive (**WASD** / arrow keys / thumbstick / gamepad) to the glowing ring. An arrow at the top of the screen always points the way. |
| 3. Deliver | Slow down inside the ring. Faster runs earn a **speed bonus** and a bigger **customer tip**; consecutive on-time deliveries build a **streak** bonus. |
| 4. Level up | XP raises your **rank**, which unlocks longer, better-paying orders and the best vehicles. |
| 5. Upgrade | Spend your cash in the **Garage** (button on the left, or the garage building at the depot). |

Other controls: **V** calls your vehicle to you (or use the *My Vehicle* button), **G** opens the garage at the depot. Jump to get out of a car.

Late deliveries still pay the base fee but lose all bonuses and break your streak. If you're *very* late, the customer cancels.

### Vehicles

| Vehicle | Price | Rank | Notes |
| --- | --- | --- | --- |
| Delivery Scooter | free | Rookie | Zippy and nimble |
| City Hatch | $450 | Rookie | Faster and sturdier |
| Cargo Van | $1,400 | Courier | +10% on every payout |
| Street Roadster | $3,800 | Pro Driver | Open-top speed machine |
| Hyper Courier | $11,000 | Road Legend | Fastest in the game |

Ranks: Rookie → Courier → Driver → Pro Driver → Elite Courier → Road Legend → Delivery Master.

## Saving

Progress (cash, XP, vehicles, stats) is saved with DataStores: every minute, when you leave, and when the server shuts down. If a save can't be loaded, the game tells you and **will not overwrite** your old data.

To test saving in Studio, turn on **Game Settings → Security → Enable Studio Access to API Services** (the place has to be published first). With it off, the game still plays normally; it just doesn't save.

## Project layout

```
Place1.rbxl / Place1.rbxlx   the playable place (generated - see "Building")
default.project.json         Rojo project (optional; maps src/ into the DataModel)
src/
  shared/    -> ReplicatedStorage.Shared
    Config.luau              every tunable number: ranks, vehicles, payouts, town size
    Economy.luau             pure payout / XP / rank maths
    Remotes.luau             all RemoteEvents/Functions in one place
    VehicleBuilder.luau      builds each vehicle model from Parts (no asset ids)
  server/    -> ServerScriptService.Server
    Main.server.luau         entry point
    WorldBuilder.luau        generates the town (also run at build time to bake it in)
    Profile.luau / Orders.luau   pure game rules (what you own, what an order is)
    DataService / PlayerService / VehicleService / OrderService / GarageService
  client/    -> StarterPlayer.StarterPlayerScripts.Client
    Main.client.luau         entry point
    DriveModel.luau          the arcade driving maths (pure, unit-tested)
    VehicleController / VehicleVisuals    drive your car; spin everyone's wheels
    Hud / OrderPanel / GarageUI / Waypoint / Splash    the UI, all built from code
tools/       build tool + a small Roblox-like environment for Lune
tests/       the test suite
```

### How it works

* **Rules live in plain modules** (`Economy`, `Profile`, `Orders`, `DriveModel`) with no engine calls, so they're easy to test and tweak. The services around them are thin glue.
* **The server owns the truth.** Cash, XP, orders and purchases are all decided on the server; the client only sends requests (*call my vehicle*, *cancel*, *buy X*) and everything is re-checked there. Deliveries are judged from the player's position and speed on the server.
* **State reaches the client as attributes** on the `Player` (`Cash`, `XP`, `OrderAddress`, …), so the UI just reacts to changes and late joiners are always in sync.
* **Driving is arcade physics.** The driver's client owns the car and sets its velocity each frame from the seat's throttle/steer (`DriveModel`). The car can't flip, and it's parked (anchored) when empty. Cars and characters are in separate collision groups so nobody gets flung.
* **No external assets.** The town, vehicles and UI are all generated from Parts and UI instances. (There's no audio yet - see below.)

## Building and testing

You only need these if you change the code. They use [Lune](https://github.com/lune-org/lune) (`cargo install lune --locked`).

```bash
lune run tools/build   # regenerate Place1.rbxl + Place1.rbxlx from src/
lune run tests/run     # run the tests
```

`tools/build` loads the existing place, injects `src/`, runs `WorldBuilder` to bake the town into `Workspace.Town`, writes both files, then reads them back to verify. The tests include a check that the committed place files match `src/` exactly, so a stale place can't slip through.

**Prefer Rojo?** `rojo serve` with `default.project.json` works too: the town is built at runtime if `Workspace.Town` doesn't exist.

### What the tests cover

Instances in the tests are Lune's real ones, so every property, enum and class the game uses is checked against Roblox's API database. The engine itself (time, services, remotes, seats, raycasts) is mocked, which lets the tests play whole sessions in virtual time:

* economy, ranks, orders, profile rules and save-data sanitising
* the town's geometry (no overlapping houses, markers on the right lane, depot layout)
* every vehicle model (wheels on the ground, rider head-room, joined together, facing -Z)
* the driving model (steering direction, grip, levelling) and the controller/wheel scripts
* the server end to end: joining, ordering, delivering (on time, late, too fast, too early, cancelled, timed out), vehicles, garage purchases, anti-abuse checks, saving and failed DataStores
* the client end to end: HUD, order card and countdown, toasts, result popup, garage UI, waypoint arrow, splash

**What they can't tell you:** how the game *feels* (physics, camera, UI layout on your device) - that needs a human in Studio. If something feels off, the numbers to tweak are all in `Config.luau` and the top of `DriveModel.luau`.

## Ideas for next steps

* Audio: engine, horn, delivery chime (needs asset ids you own or are licensed to use)
* Day/night cycle with street lights and headlights
* More towns / a district unlocked by rank
* Passengers or multi-drop orders for the Van
* Gamepasses, daily rewards, a global leaderboard of best streaks
