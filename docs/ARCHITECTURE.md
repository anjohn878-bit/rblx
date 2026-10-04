# Architecture

## Principles
- **The server decides everything that matters.** Clients only send intents (`Kick`, `Tackle`,
  `SkillMove`, `RequestQueue`, `PurchaseItem`, `EquipItem`, `SpendAttribute`). Currency, XP,
  stats, inventory, possession and match results are only ever changed in server services.
- **Each system is one module** with `Init()` (create state) and `Start()` (connect events, start loops),
  booted in order by `Server/Main.server.luau` and `Client/Main.client.luau`.
- **All tuning lives in `Shared/Config.luau`**, including controls, physics, rewards and pitch layout.
- **Pure logic is kept free of Roblox services** (`Progression`, `KickMath`) so it can be unit tested with Lune.

## Server services (boot order)

| Service | Responsibility |
|---|---|
| DataService | Loads and saves profiles through UpdateAsync with a **session lock** (`{Data, Lock={JobId,Time}}`). Retries with backoff, autosaves every 90s, saves on leave and in `BindToClose`, never saves a profile that failed to load, stops saving and kicks the player if another server takes the lock. Uses temporary profiles in Studio when API access is off. |
| ProgressionService | The only writer of XP, levels, Kicks (currency), reputation, attributes and lifetime stats. Sends the profile to its owner (batched per frame) and updates leaderstats. |
| InventoryService | Validated purchases and equips (reputation tier locks, price), and applies the kit to characters. Team bib colour during matches. |
| MapBuilder | Generates the Grounds from Config: lighting, plaza, caged pitch, goals, stands, floodlights, buildings and graffiti, the Locker, the practice court, area gates, benches and lights. |
| Actors | Gives players and bots one shared interface (root, attributes, name, id). |
| BallService | Server-authoritative balls (details below). Also runs the free practice balls. |
| BotService | AI "Regulars" that fill match slots. One shared 0.15s AI tick; bots use the same BallService API as players. |
| MatchService | Match state machine per pitch, goal detection, stats (goals, assists, passes, tackles, shots, skills), rewards, and returning players to the Grounds. |
| MatchmakingService | Queue per pitch (pad prompt or PLAY button), snake-draft team balancing on skill rating, bot fill after 8s. |
| LeaderboardService | Physical board in the plaza (this server's players). |
| AmbientService | Fans in the stands, locals emoting and walkers, so the hub never feels empty. |

## How the ball works
- **Free ball:** owned by the server. Roblox physics handles bounces off posts, walls and nets, plus a
  `VectorForce` for lighter custom gravity and per-frame rolling and air drag.
- **Possession:** when a player comes within `ControlRadius`, the server gives them possession and
  **network ownership**. The client's `BallController` steers the ball in front of their feet every physics
  step, so dribbling feels instant. The server checks a leash distance (`MaxDribbleLeash`) and drops
  possession if it is broken.
- **Kicks:** the client sends a kind, an aim direction and a power. The server checks rate limits, that the
  player has the ball or is within reach of it, and team eligibility. It then computes the velocity with
  `KickMath`: pass assist cone, through-ball lead, lob flight time, shot assist and accuracy error from
  attributes. Ownership goes back to the server before the velocity is applied.
- **First touch:** hard balls can bounce off a player depending on their Ball Control attribute.
- **Tackles:** the chance comes from Defending vs Dribbling, plus a small Physicality factor. A skill
  move gives a 0.5s evade window. A failed tackle slows the tackler.
- **No character collisions:** balls never collide with characters (collision groups). All
  player–ball contact goes through the logic above, which is what keeps the ball predictable.

## Match flow
`Idle → MatchFound (rosters, 4s) → Kickoff (players placed and anchored, 3-2-1) → Playing → Goal (4s celebration) → Kickoff → … → Ended (results and rewards) → back to the Grounds → Idle`

Replication works like this:
- `ReplicatedStorage.Matches.<PitchId>` attributes hold `State`, `ScoreA`, `ScoreB`, `EndsAt`,
  `TimeLeft`, `QueueCount` and `BotFillAt`. Spectators read these too.
- Player attributes hold `MatchId`, `Team`, `AttackDir`, `HasBall` and `QueuedPitch`.
- One-off moments (`MatchFound`, `Countdown`, `Goal`, `Results`) go through the `MatchEvent` remote.

If a player leaves mid-match, a bot takes their place. If no humans remain, the match ends with no rewards.

## Client
- `InputController`: ContextActionService bindings from `Config.Controls`, which covers keyboard and mouse,
  Xbox/PlayStation gamepads and mobile touch buttons from one table.
- `MovementController`: sprint ramp, stamina, dribble slowdown, dash for skill moves and tackle lunges.
- `BallController`: dribble steering while we own the ball.
- `CameraController`: match camera with Follow (mouse, stick or touch orbit, adjustable sensitivity) and
  Broadcast modes. It cuts to the ball for goals and kickoffs and smooths every move, with no camera shake.
- `UI/*`: HUD, MatchHUD, Locker (live viewport preview), Profile (stats and attribute points),
  Settings and Results, all built in code with one visual identity (`UIKit.Theme`).

## Anti-pay-to-win
Kicks only buy cosmetics. Attribute points come only from levelling up, and the gameplay effect of
attributes is deliberately small (for example, Pace adds at most 3 to sprint speed).

## Roadmap (next phases)
1. **Feel and audio:** custom kick, tackle and celebration animations (uploaded to your account) and an original sound set (kicks, crowd, UI, whistle).
2. **Daily and weekly challenges**, plus a daily login reward (profile `Challenges` is already saved).
3. **Parties and friend invites** (queue entries already support groups), and spectator cameras.
4. **Global leaderboards** (OrderedDataStore) and player profile cards you can view on other players.
5. **World progression:** open the Street Court / Urban Arena gates by reputation, and add more pitches with
   other formats. Matches already read `Config.Match.TeamSize`, and formations exist for 1–5 players a side.
6. **Emote wheel and post-goal celebrations**, hidden collectibles and more hairstyles and accessories.
