# 🏥 Work as a Doctor

An original Roblox hospital tycoon/simulator built in Luau.

**Patients arrive → you diagnose them → you get paid → you upgrade your hospital → Auto Doctors work for you → you expand → repeat.**

Everything (map, hospitals, NPCs, UI) is generated from code, so the place needs no uploaded assets.

## Quick start

### Option A: open the built place
1. Open `WorkAsADoctor.rbxlx` in Roblox Studio.
2. Press **Play**.

### Option B: develop with Rojo (recommended)
1. Install [Rojo](https://rojo.space) 7.x and the Rojo Studio plugin.
2. Run `rojo serve` in this folder, then click **Connect** in the Studio plugin (any empty Baseplate works; the default `Baseplate`/`SpawnLocation` are removed automatically).
3. Rebuild the place file any time with:
   ```
   rojo build default.project.json --output WorkAsADoctor.rbxlx
   ```

### Saving in Studio
DataStores only work in Studio when the place is published and **Game Settings → Security → Enable Studio Access to API Services** is on. Without that the game still runs, but progress isn't saved (you'll see a warning in Output, and the Stats panel shows "Saving: Off").

### Server size
There are 6 hospital plots arranged around the central plaza, so set **Max Players to 6** in Game Settings. If a 7th player joins, they're told the server is full.

## How to play

| Step | What happens |
| --- | --- |
| 1 | You spawn inside your own **Small Clinic**. Nurse Nina's tutorial walks you through your first patient. |
| 2 | Patients arrive at the bus stop, check in at reception, wait in the waiting room, then walk to a free exam room. |
| 3 | Walk up to a patient lying in an exam room and press **E** (or tap **Diagnose**). |
| 4 | Read the **symptoms**, then pick the matching illness. Wrong answers aren't punished much: you just try again for slightly less money. |
| 5 | Get paid (`+$45`), level up as a doctor, and spend your money in the **🛒 Shop**. |

Ways to earn more:
- **Personal care bonus:** diagnosing yourself pays 1.5× what Auto Doctors earn.
- **Combo streak:** +10% per correct diagnosis in a row (up to +100%).
- **Expert bonus:** +25% if you don't open the 📖 Handbook and get it right first try.
- **Doctor level:** +5% personal income per level, and harder cases (more symptoms and choices) that pay more.
- **Rare patients:** ⭐ Rare / ⭐⭐⭐ Epic / ⭐⭐⭐⭐ Legendary patients glow, get announced, can have quirky illnesses (Giggle Fever, Pixel Pox...) and pay up to 12×.

Shortcuts: keys **1–6** pick an answer, **H** opens the handbook.

## Progression

| Lv | Hospital | Cost | Exam rooms | Patients at once | Pay |
| --- | --- | --- | --- | --- | --- |
| 1 | Small Clinic | free | 1 | 3 | 1× |
| 2 | Local Hospital | $500 | 2 | 6 | 1.5× |
| 3 | Modern Hospital | $2,000 | 4 | 10 | 2.25× |
| 4 | Medical Center | $10,000 | 6 | 15 | 3.5× |
| 5 | Regional Hospital | $40,000 | 7 | 18 | 5.5× |
| 6 | University Hospital | $250,000 | 8 | 21 | 8.5× |
| 7 | Mega Hospital | $1.2M | 9 | 24 | 13× |
| 8 | Legendary Medical Citadel | $5M | 10 | 28 | 20× |

Every level rebuilds the building: it gets bigger, adds windows, towers, a helipad, gold trim and finally a glowing rooftop beacon.

**Auto Doctors** (one per exam room): I (15s per patient, $1,000) → II (10s, $5,000) → III (6s, $20,000) → Specialist IV (4s, $75,000) → Robo-Doc 3000 (2.5s, $300,000). Each extra hire costs more.

**Rooms**: 💊 Pharmacy (+25% income), 🧪 Laboratory (harder, better-paying illnesses + Lab Test hint), 🧸 Children's Ward (kids, faster arrivals), 🚨 Emergency Room (2× pay emergencies that skip the queue), 🔪 Surgery, 🧠 Specialist (more rare patients), 👑 VIP (5× pay celebrities).

**Boosts**: 📣 Marketing (faster arrivals), 🔬 Better Equipment (+10% income), 🎓 Doctor Training (faster Auto Doctors).

An active player reaches max level in roughly two hours (see `tests/pacing_sim.luau`).

## Project layout

```
default.project.json        Rojo project
src/shared   -> ReplicatedStorage.Shared
  Config/                   All tuning: levels, rooms, doctors, rarities, boosts, sounds
  Economy.luau              Shared price/rate formulas (server validates, client displays)
  Remotes.luau              Every RemoteEvent/RemoteFunction in one place
  Util/                     Format ($1,250 / $1.25M), Signal
src/server   -> ServerScriptService.Server
  Main.server.luau          Boot + player lifecycle
  Data/Illnesses.luau       Illness + symptom database and case generator
  Services/                 DataService, EconomyService, PlotService, WorldBuilder,
                            HospitalBuilder, HospitalService, DiagnosisService,
                            ShopService, LeaderboardService
  Classes/                  HospitalSim (per-player simulation), Patient, AutoDoctor
  NPC/                      R6 rig builder, animator, pathfinding mover
src/client   -> StarterPlayerScripts.Client
  Main.client.luau          Boot
  UI/                       UIKit helpers + Theme
  Controllers/              HUD, Shop, Diagnosis, Stats, Tutorial, Notifications,
                            Effects, PatientVisuals, Guide, World, Sound
tests/                      Plain-Luau logic tests + economy pacing sim
```

## Security model

- The server owns all money, rewards, prices and progress. Clients only send *intent* (`Purchase("HospitalLevel")`, `SubmitDiagnosis(patientId, illnessId)`).
- The diagnosis case (shown symptoms, options, correct answer) is generated and checked on the server. Answers are only accepted for a patient in *your* hospital, in an exam room, that you opened, while you are standing near it.
- Every remote is type-checked and rate-limited.
- DataStore saves use `UpdateAsync` with retries, a light session lock (so two servers never overwrite each other), autosave every 60s, save on leave, and `BindToClose`. If a load fails, saving is disabled for that session so a real save is never overwritten with defaults.

## Extending

- **New illness:** add a line to `src/server/Data/Illnesses.luau` (reuse symptom keys so overlapping symptoms compare equal). Cases stay unambiguous automatically; the case builder never offers a wrong answer that matches every shown symptom.
- **New hospital level:** add an entry to `src/shared/Config/HospitalLevels.luau` (keep `ExamRooms * 12 + 16 <= Width`, `Width <= 136`).
- **New room:** add it to `src/shared/Config/Rooms.luau`, add furniture in `HospitalBuilder`'s `FURNISH` table, and use `data.Rooms.<Id>` wherever its bonus applies.
- **New doctor tier / boost:** `AutoDoctors.luau` / `Improvements.luau`.
- **Sounds:** `src/shared/Config/Sounds.luau` uses built-in Roblox sounds; swap in your own `rbxassetid://` IDs.

## Tests

`tests/` contains plain-Luau unit tests for the pure logic (formatting, economy formulas, level tables, and thousands of generated diagnosis cases checked for solvability). They run outside Studio using a small Roblox mock (`tests/harness.luau`) and any Luau runtime that exposes two helper globals, `__readfile(path)` and `__loadstring(source, chunkName)`:

```
<luau-runner> tests/run_tests.luau
```

`tests/pacing_sim.luau` is a rough simulation of how long each hospital level takes to reach. Use it when tuning prices.

## Notes

- `Place1.rbxl` / `Place1.rbxlx` are the original empty Baseplate files and aren't used by the game.
- Patients and doctors are classic R6 characters built from parts. Their walk/idle/sit animations use Roblox's default R6 animation IDs.
