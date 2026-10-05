# 🐦 Grow a Bird Garden

A Roblox game inspired by *Grow a Garden*, except the plants grow to attract birds, and the birds become your pets.

1. **Get seeds** from Polly the parrot at the Seed Shop.
2. **Plant them** in your garden.
3. **Wait** while they grow, from seed to sprout to young plant to full bloom.
4. **Birds visit** blooming plants. Walk up and **befriend** them and they join your aviary as pets.
5. **Your best birds roam your garden** and help it: faster growth, more visitors, rarer birds, better prices, even free seeds.
6. **Breed** two birds of the same kind to hatch babies and grow a family.
7. **Sell** spare birds for coins, or **trade** them with other players, then buy better seeds that attract rarer birds.

Plants keep growing and eggs keep hatching while you're offline, so a Golden Tree you plant before bed will be blooming when you come back.

## Play it

Open `Place1.rbxlx` (or `Place1.rbxl`) in Roblox Studio and press **Play**. The scripts are already in the place, and the world (gardens, paths, shop) is built when the server starts.

| Action | Keyboard | Gamepad / Mobile |
| --- | --- | --- |
| Plant the selected seed on empty soil | `E` | prompt button / tap |
| Befriend a perched bird | `E` | prompt button / tap |
| Dig up a plant | hold `R` | hold prompt button / tap and hold |
| Open a nest (breeding) | `E` near a nest | prompt button / tap |
| Pick a seed from your seed bag | `1`–`9` or click | tap |
| Seed shop, garden, journal, birds, trade | buttons on the left | tap |

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

- A bird stays for 45 seconds. If nobody befriends it, it flies away.
- The **first time** you befriend a species you get a discovery bonus (3x its value) and it's added to your 📖 Bird Journal.
- One visitor in 50 is a sparkly **✨ Shiny** bird worth 5x.
- The shop **restocks every 5 minutes**, and the rare seeds aren't in stock every time.

## Pet birds

Every bird you befriend gets a name and **1–3 stars** and moves into your 🐦 **Birds** aviary (60 birds max). Up to **6** at a time can be *out* in your garden, hopping around, fluttering up onto your flowers, and giving their perk. New birds go out by themselves while there's room, and a better new bird takes the place of the weakest one. **⭐ Best out** sends out your strongest six.

| Bird | Rarity | Worth | Perk while out |
| --- | --- | --- | --- |
| Sparrow | Common | 4 | 🎒 Seed Finder |
| Pigeon | Common | 5 | 🐦 Social |
| Robin | Common | 7 | 🎒 Seed Finder |
| Goldfinch | Uncommon | 12 | 🪙 Haggler |
| Blue Jay | Uncommon | 16 | 🎒 Seed Finder |
| Cardinal | Uncommon | 22 | 🍀 Lucky |
| Hummingbird | Rare | 45 | 🌱 Green Thumb |
| Scarlet Macaw | Rare | 70 | 🪙 Haggler |
| Toucan | Epic | 150 | 🎒 Seed Finder |
| Flamingo | Epic | 200 | 🌱 Green Thumb |
| Peacock | Legendary | 550 | 🐦 Social |
| Snowy Owl | Legendary | 700 | 🍀 Lucky |
| Phoenix | Mythic | 2,500 | 🌱 Green Thumb |

- 🌱 **Green Thumb**: plants grow faster (up to +150%).
- 🐦 **Social**: birds visit more often (up to +100%).
- 🍀 **Lucky**: rarer birds and more shinies visit (up to +150%).
- 🪙 **Haggler**: birds sell for more (up to +200%).
- 🎒 **Seed Finder**: a chance every minute to find a free seed, up to one rarity better than the bird itself.

Perks get stronger with rarer birds, more stars (up to 5), and shiny birds. Babies give half until they grow up.

### Breeding and families

Each garden has **two nests**. Put two grown-up birds of the same kind in a nest and they keep an egg warm until it hatches (2 minutes for Common birds, up to 30 minutes for Mythic). The baby:

- gets its parents' average stars, with a 35% chance of one more, up to 5,
- is often shiny if its parents are (15% with one shiny parent, 50% with two),
- joins their **family**: the first pair to breed starts a new family with its own surname, like *the Featherby family*,
- follows its parents around the garden and grows up after a while (3 minutes for Common birds, up to 40 for Mythic).

### Selling

Selling birds is how you earn coins. Sell one bird from its card, or use **💰 Sell spares** to sell every *spare* bird up to a rarity you choose. Spares are birds that aren't out, nesting, ❤ favorites, shiny, in a family, babies or 4 stars and up. Tap ♡ to make a bird a favorite so it can't be sold or traded by accident.

When the aviary is full, a plain common bird you befriend is sold straight away. A rare, shiny, 3-star or brand-new kind of bird waits on its perch until you make room.

### Trading

Press 🤝 **Trade**, pick a player and send a request. When they accept, both of you add birds (up to 8) and coins. Each side shows what it's worth. When both players press **Ready**, a 3-second countdown starts, and any change un-readies both. The server checks everything again and swaps it all at once, then saves both players straight away.

## Settings

All the tuning numbers are in `src/shared/Config.lua`. Seeds are defined in `src/shared/Seeds.lua` and birds in `src/shared/Birds.lua`.

- **Testing quickly:** set `GrowthSpeed = 20` in `Config.lua` so plants, eggs and babies grow 20x faster. Set it back to `1` before publishing.
- **Testing trading:** in Studio use *Test → Clients and Servers* with 2 players.
- **Saving:** progress is saved with DataStores, with a session lock so a player's data is only ever open on one server (this stops trade duplication by server hopping). To save while testing in Studio, publish the place and turn on *Game Settings → Security → Enable Studio Access to API Services*.
- **Server size:** there are 6 gardens, so set *Max Players* to 6 when you publish.

## Project layout

```
src/shared/   ReplicatedStorage.Shared: config, seed/bird/pet rules, model builders
src/server/   ServerScriptService.BirdGardenServer: world, plots, birds, pets, nests, trading, shop, saving
src/client/   StarterPlayerScripts.BirdGardenClient: HUD, windows, roaming pets, effects
tools/        build-place.luau copies src/ into the place files
tests/        a simulated playthrough of the game
```

The scripts in `src/` are the source of truth. After editing them, copy them into the place files with [Lune](https://lune-org.github.io/docs):

```sh
lune run tools/build-place   # updates Place1.rbxlx and Place1.rbxl
lune run tests/run           # plays through the game in a simulated server
```

You can also live-sync with [Rojo](https://rojo.space) using `default.project.json`.
