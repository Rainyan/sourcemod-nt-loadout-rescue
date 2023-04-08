# sourcemod-nt-loadout-rescue
Experimental plugin for Neotokyo that provides the following change:

If a player spawns without a primary weapon, let them choose their weapon loadout again.

## Background
In Neotokyo, players can spawn without a primary weapon under the following situations:

#### Player chose a weapon loadout with insufficient XP
* If a player deranks after the loadout menu was displayed, it won't update.
  Choosing a weapon at too high a tier will then leave them without a primary weapon.
  This happens particularly in comp games, where the game gets restarted when it goes live
  but the client chose their initial load before that final restart went through.
#### Player chose an incompatible loadout
* If a player doesn't choose a weapon in time, the game will eventually forcibly spawn them,
  and pick the loadout they chose last in their stead.
  If this previous loadout is no longer available for them (deranked or the loadout isn't available
  for their current player class), this player will end up without a primary weapon.
  This can happen if players go AFK, and then return to find themselves empty handed.

## What this plugin does
If a player spawns without a weapon, this plugin will re-display that weapon loadout menu for them,
so they can choose a valid loadout. The player will then receive this weapon post-spawn.

## Build requirements
* SourceMod 1.11 or newer
* The [neotokyo.inc include](https://github.com/softashell/sourcemod-nt-include/blob/master/scripting/include/neotokyo.inc), version 1.1 or newer

## Installation
* Move the compiled .smx binary to addons/sourcemod/plugins
* Move the gamedata file to addons/sourcemod/gamedata/neotokyo
