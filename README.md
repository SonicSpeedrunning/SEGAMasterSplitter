# SEGAMasterSplitter
LiveSplit autosplitter designed to handle multiple 8 and 16 bit SEGA games running on various emulators

## Supported Emulators

* Retroarch (32bit and 64bit), using Genesis Plus GX or BlastEm! Core
* BlastEm!
* Fusion 3.64
* SEGA Game Room
* SEGA Simple Launcher
* Gens (though banned for most speedruns)

## Supported Games
### 16-bit
* Magical Taruruuto-kun
* Mystic Defender
* Sonic the Hedgehog 1 (Genesis/Mega Drive)
* Sonic the Hedgehog 2 (Genesis/Mega Drive)
* Sonic 3 & Knuckles
* Sonic 3 Complete
* Sonic 3D Blast
* Sonic CD
* Sonic Eraser
* Sonic Spinball (Genesis/Mega Drive)
* Tiny Toons Adventures: Buster's Hidden Treasure
### 8-bit
* Alex Kidd in Miracle World
* Sonic the Hedgehog 1 (Master System)
* Sonic the Hedgehog 2 (Game Gear / Master System)
* Sonic 2 Rebirth
* Sonic Chaos

## Timing Methods
IGT is stored in Game Time, and RTA-TB is stored in "Real Time" for Sonic 1, 2, CD, and 2 (8-bit).  
IGT is stored in Game Time for 3D Blast.
RTA-TB is stored in Game Time for Sonic 1 (SMS), and Sonic 3 & Knuckles, with the option of storing it in Real Time.
RTA is also stored in Game Time for all other games.

## Splits
Most splits are done at the beginning of the next level (i.e. after bonus screens etc) This is with the exception of Sonic Spinball
where splits are done at the final hit on each boss, and at the start of a new level.

Final split is done according to the SRC rules for the relevant game at the time of coding.
Sonic 2 (8 bit) starts the timer just before the Underground 1 splash screen appears, and final split is on fade out (in either SE3 or CE3).

## Debugging options
### Level Select Activation
To help test the autosplitter it has a Debug setting to enable Level Select in games that have one.
### Forcing All Emeralds (Sonic 2 8-bit)
As there are extra levels for collecting all emeralds in this game, and the count is reset when the game is, there is an option to have the correct emerald counts for the Silver Sonic boss, and Crystal Egg Act 3 to play the good ending.
