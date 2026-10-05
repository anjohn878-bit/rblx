# 👗 Build a Dress Store

A Roblox tycoon game. Build your own dress boutique, sew dresses, and sell them to shoppers to make money.

## How to play it in Roblox Studio

1. Open **`Place1.rbxl`** in Roblox Studio (`Place1.rbxlx` has the same game in text form).
2. Press **Play** (F5).
3. You spawn at your own store plot. Your name is on the gate.

To try it with friends in Studio, use **Test → Clients and Servers** and pick 2 or more players.

## How the game works

| Step | What to do |
| --- | --- |
| 1. Open your store | Walk to the glowing button in your front yard and press **E** (or tap it on a phone). The first one is free. |
| 2. Build | Buy the **Cash Register** and the **Sundress Rack**. Buttons are green when you have enough money and red when you don't. |
| 3. Sew | Hold **E** at the **Sewing Table** at the back of the store to sew dresses. They get hung on your racks. |
| 4. Sell | Shoppers walk in, take a dress from a rack, and line up at the register. Press **E** at the **Cash Register** to ring them up and get paid. If you make them wait too long they leave. |
| 5. Upgrade | Every upgrade opens new buttons. Sewing machines sew for you, a **Cashier** rings shoppers up for you, and decorations bring in more shoppers. |
| 6. Rebirth | When everything is built, press **⭐ Rebirth**. Your store starts over, but you earn **+50% money** forever (stacks every time). |

There are 6 dresses to sell, from the $20 **Sundress** to the $2,000 **Wedding Dress**, and 23 things to build: walls, a shop sign, window mannequins, fitting rooms, chandeliers, sofas, designer handbags, a fashion runway, a garden fountain and a golden dress statue. The prices are tuned so building the whole store takes roughly 50 minutes the first time, and less after each rebirth.

The screen shows your cash, how many dresses are on your racks, a tip about what to do next, and how close you are to your next upgrade. The **🏠 My Store** button takes you back to your store.

## Saving progress

Progress (cash, everything you built, rebirths) is saved with DataStores. Saving only works in a published game:

1. **File → Publish to Roblox**.
2. To also save while testing in Studio: **Game Settings → Security → Enable Studio Access to API Services**.

If saving isn't available, the game still works. It prints a warning in the Output window and starts everyone fresh.

Each server has 6 store plots, so set the place's max players to 6 (**Game Settings → Places → Edit**). If more people join anyway, the extra players get a store as soon as someone leaves.

## Changing the game

Most numbers live in **`ReplicatedStorage › DressStore › Config`**. In this repo that's [`src/ReplicatedStorage/DressStore/Config.lua`](src/ReplicatedStorage/DressStore/Config.lua):

- `STARTING_CASH`, `REBIRTH_BONUS`
- `Config.Dresses`: names, prices and colours of the dresses
- `Config.Items`: everything you can build, its price, and what it needs first
- `Config.Customer`: how often shoppers come, how patient they are, and how fast the cashier is

## Project layout

```
src/
  ReplicatedStorage/DressStore/      shared by server and players
    Config.lua                       prices, dresses, upgrades
    Util.lua                         money formatting
  ServerScriptService/DressStoreServer/
    init.server.lua                  main server script (players, plots, rebirth)
    Store.lua                        one store: buying, racks, sewing, the register line
    Customer.lua                     shopper behaviour
    Builders.lua                     builds each item out of parts
    WorldBuilder.lua                 the boulevard and the store plots
    DressModel.lua                   builds a dress model
    Npc.lua                          shopper and cashier characters
    DataManager.lua                  saving and loading
    Layout.lua                       where things go inside a plot
    Parts.lua, Remotes.lua           helpers
  StarterPlayer/StarterPlayerScripts/
    DressStoreClient.client.lua      the player's screen (HUD, tips, popups)
tools/
  build-place.luau                   copies src/ into Place1.rbxl and Place1.rbxlx
  test/                              automated play-through test
default.project.json                 Rojo project
```

The whole town is built by the scripts when the game starts, so the place file itself only holds the scripts.

### For developers

- **Rojo:** `rojo serve` with `default.project.json` syncs `src/` into Studio.
- **Rebuild the place files** after editing `src/` (needs [Lune](https://lune-org.github.io/docs)): `lune run tools/build-place.luau`
- **Run the tests:** `lune run tools/test/test.luau` (add `r15` for R15 shoppers). They run the real server and client scripts against a small fake Roblox engine with simulated time. They cover opening a store, buying all 23 items, shoppers walking, buying and paying (and checking they never walk into furniture), impatient shoppers, the cashier, rebirth, saving and loading, two players, a full server, and Studio without API access.
