# 🐦 Grow a Bird Garden

A Roblox game inspired by *Grow a Garden*, except the plants grow to attract birds.

1. **Get seeds** from Polly the parrot at the Seed Shop.
2. **Plant them** in your garden.
3. **Wait** while they grow, from seed to sprout to young plant to full bloom.
4. **Birds visit** blooming plants. Walk up and **befriend** them to earn coins.
5. **Buy better seeds.** They cost more and take longer to grow, but they attract rarer birds that are worth a lot more.

Plants keep growing while you're offline, so a Golden Tree you plant before bed will be blooming when you come back.

## Play it

Open `Place1.rbxlx` (or `Place1.rbxl`) in Roblox Studio and press **Play**. The scripts are already in the place, and the world (gardens, paths, shop) is built when the server starts.

| Action | Keyboard | Gamepad / Mobile |
| --- | --- | --- |
| Plant the selected seed on empty soil | `E` | prompt button / tap |
| Befriend a perched bird | `E` | prompt button / tap |
| Dig up a plant | hold `R` | hold prompt button / tap and hold |
| Pick a seed from your seed bag | `1`–`9` or click | tap |
| Seed shop, go to garden, bird journal | buttons on the left | tap |

## Seeds and birds

| Seed | Rarity | Price | Grow time | Attracts |
| --- | --- | --- | --- | --- |
| 🌻 Sunflower | Common | 10 | 30s | Sparrow, Pigeon, Goldfinch |
| 🍒 Berry Bush | Common | 30 | 1m 15s | Robin, Sparrow, Blue Jay, Cardinal |
| 💜 Lavender | Uncommon | 90 | 3m | Goldfinch, Blue Jay, Cardinal, Hummingbird |
| 🌺 Hibiscus | Uncommon | 250 | 5m | Hummingbird, Cardinal, Goldfinch, Scarlet Macaw |
| 🥭 Mango Tree | Rare | 700 | 10m | Scarlet Macaw, Hummingbird, Toucan |
| 🌸 Pink Lotus | Rare | 1,800 | 15m | Flamingo, Scarlet Macaw, Toucan, Peacock |
| 🌙 Moonflower | Epic | 5,000 | 25m | Snowy Owl, Flamingo, Toucan, Peacock |
| 🌟 Golden Tree | Legendary | 15,000 | 40m | Peacock, Snowy Owl, Toucan, Phoenix |
| 🔥 Ember Bloom | Mythic | 50,000 | 1h | Phoenix, Peacock, Snowy Owl |

There are 13 birds, from the Sparrow (4 coins) to the Phoenix (2,500 coins). Some extra rules:

- The **first time** you befriend a species you get triple coins, and it's added to your 📖 Bird Journal.
- One visitor in 50 is a sparkly **✨ Shiny** bird worth 5x coins.
- A bird stays for 45 seconds. If nobody befriends it, it flies away.
- The shop **restocks every 5 minutes**, and the rare seeds aren't in stock every time.

## Settings

All the tuning numbers are in `src/shared/Config.lua`. Seeds are defined in `src/shared/Seeds.lua` and birds in `src/shared/Birds.lua`.

- **Testing quickly:** set `GrowthSpeed = 20` in `Config.lua` so plants bloom 20x faster. Set it back to `1` before publishing.
- **Saving:** progress is saved with DataStores. To save while testing in Studio, publish the place and turn on *Game Settings → Security → Enable Studio Access to API Services*.
- **Server size:** there are 6 gardens, so set *Max Players* to 6 when you publish.

## Project layout

```
src/shared/   ReplicatedStorage.Shared: config, seed and bird data, model builders
src/server/   ServerScriptService.BirdGardenServer: world, plots, birds, shop, saving
src/client/   StarterPlayerScripts.BirdGardenClient: HUD, seed bag, shop, journal, effects
tools/        build-place.luau copies src/ into the place files
tests/        a simulated playthrough of the game
```

The scripts in `src/` are the source of truth. After editing them, copy them into the place files with [Lune](https://lune-org.github.io/docs):

```sh
lune run tools/build-place   # updates Place1.rbxlx and Place1.rbxl
lune run tests/run           # plays through the game in a simulated server
```

You can also live-sync with [Rojo](https://rojo.space) using `default.project.json`.
