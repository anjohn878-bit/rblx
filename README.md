# Become a Delivery Driver (Roblox)

Pick up orders at **Burger Barn**, drive to the glowing green house, and earn cash.
Faster deliveries pay a speed bonus. Spend cash at the **Garage** (blue pad) on faster cars,
and climb ranks from Rookie to Delivery Legend. Progress is saved with DataStores.

## Run it
1. Install [Rojo](https://rojo.space) and the Rojo Studio plugin.
2. `rojo serve` in this folder, then Connect from Studio (open `Place1.rbxl` or any empty place).
   Or build a place: `rojo build -o BecomeADeliveryDriver.rbxl`.
3. Press Play. Enable *Studio Access to API Services* to test saving.

The map is generated at runtime by `src/server/WorldBuilder.luau`; tune pay and cars in `src/shared/Config.luau`.
