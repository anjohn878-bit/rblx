# Become a Delivery Driver

A Roblox game where you start out as a trainee courier at **Speedy Parcel Co.** and work your
way up to Logistics Legend. Load parcels at the depot, drive them across the town of
**Parcelton**, hand them over at the door, and spend your pay on bigger, faster vehicles.

## Play it

1. Open **`BecomeADeliveryDriver.rbxlx`** in Roblox Studio.
2. Press **Play**. The town is generated when the server starts, so in edit mode you only see the
   baseplate.

To publish it, use **File > Publish to Roblox**. Saving progress needs DataStores, so for a
published game turn on **Game Settings > Security > Enable Studio Access to API Services** if you
want saving to work while testing in Studio. Without it the game still runs; it just tells you
progress won't be saved.

### Controls

| Action | Keyboard | Mobile / gamepad |
| --- | --- | --- |
| Walk / drive | WASD or arrow keys | Thumbstick |
| Load packages, deliver a package | **E** at the counter or door | Tap the prompt |
| Get in your vehicle | **F** | Tap the prompt |
| Get out of your vehicle | **Space** | Jump button |
| Open the garage | **G** | GARAGE button |
| Get your vehicle | **V** | GET VEHICLE button |

## How it plays

- **Load up.** Walk to the Package Counter in the depot and press E. You get as many parcels as
  your vehicle holds, each with a random address somewhere in town.
- **Drive.** A coloured beacon marks every drop-off, and the arrow at the top of the screen points
  at your current target (click a parcel in the list to switch). Get a vehicle from the pick-up
  post, the GET VEHICLE button or by pressing V. Away from the depot it shows up on the
  nearest road.
- **Deliver.** Park, hop out and press E at the door. Farther addresses pay more, and beating the
  timer adds a 30% speed bonus. Express parcels pay 1.75x on a tight timer. Rare VIP parcels pay 3x.
- **Get promoted.** Completed deliveries raise your rank, which multiplies all future pay and
  unlocks new vehicles:

| Rank | Deliveries | Pay |
| --- | --- | --- |
| Trainee | 0 | 1.0x |
| Delivery Driver | 5 | 1.1x |
| Senior Driver | 25 | 1.25x |
| Route Master | 75 | 1.4x |
| Express Expert | 150 | 1.6x |
| Logistics Legend | 300 | 2.0x |

| Vehicle | Price | Needs rank | Top speed | Parcels per trip |
| --- | --- | --- | --- | --- |
| Delivery Bike | free | Trainee | 21 mph | 1 |
| City Moped | $400 | Trainee | 31 mph | 2 |
| Compact Car | $1,500 | Delivery Driver | 39 mph | 3 |
| Delivery Van | $5,000 | Senior Driver | 43 mph | 5 |
| Box Truck | $15,000 | Route Master | 39 mph | 8 |
| Express Supercar | $40,000 | Express Expert | 72 mph | 3 |

Other details: cash, deliveries and owned vehicles are saved. Vehicles pass through other players,
so nobody can ram you. Only the owner can drive a vehicle. The town has a day/night cycle and
its street lights switch on at dusk.

## Project layout

All game code is Luau in `src/`, laid out the same way as a [Rojo](https://rojo.space) project:

```
src/shared/   -> ReplicatedStorage.Shared       config, formatting, remotes, vehicle models
src/server/   -> ServerScriptService.Server     town builder, jobs, vehicles, saving, characters
src/client/   -> StarterPlayerScripts.Client    HUD, garage, waypoints, driving controls
tools/build_place.py                            packs src/ into BecomeADeliveryDriver.rbxlx
default.project.json                            Rojo project file (same mapping)
Place1.rbxlx                                    blank base place the build starts from
```

Most tuning (pay, timers, vehicle stats, ranks, town size) is in `src/shared/Config.luau`.

### Editing

You have two ways to work on it:

- **Edit `src/` and rebuild** the place file. This needs Python 3 and nothing else:

  ```
  python3 tools/build_place.py
  ```

  This regenerates `BecomeADeliveryDriver.rbxlx` from `Place1.rbxlx` plus the scripts, so make
  any map edits you want to keep in `Place1.rbxlx`.

- **Use Rojo**. Run `rojo serve` and connect from the Rojo Studio plugin to live-sync `src/` into
  an open place.

If you edit the scripts directly inside Studio instead, the place file becomes the source of truth.
Copy your changes back into `src/` before rebuilding, or the rebuild will overwrite them.
