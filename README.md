# FrontBack

FrontBack is a class-agnostic World of Warcraft 1.12 positioning HUD. It does not cast abilities or alter a rotation.

For hostile targets in melee range, it shows:

- a red up 3D arrow when in front or at the side
- a green down 3D arrow when behind

The up/down artwork comes from fixed pfQuest arrow frames; FrontBack does not use its animated or rotating behavior.

By default, `FRONT` or `BACK` appears below the icon. `/frontback text` toggles it, and the setting is saved per character.

`/frontback degrees` optionally adds the shortest movement amount below the status text, such as `< 45deg` or `45deg >`. This does not change the 3D arrow.

Drag the frame to move it. Position and visibility are saved per character.

## Commands

- `/frontback` - toggle the HUD
- `/frontback on|off`
- `/frontback text` - toggle `FRONT`/`BACK` text below the arrow
- `/frontback degrees` - toggle the number of degrees to move
- `/frontback reset` - restore the default position
- `/frontback status`
- `/frontback help`
- `/fb` - alias for `/frontback`

## Dependencies

- `UnitXP_SP3.dll` is recommended for authoritative NPC behind checks and accurate melee distance.
- `SuperWoW.dll` / `SuperWoWhook.dll` provides `UnitPosition` and `UnitFacing`. FrontBack uses this geometry for player targets and as a fallback for NPCs.

## Installation

If FrontBack is installed at `<WoW_Dir>\Interface\AddOns\FrontBack`, close the game and double-click `install_dependencies.bat`. It auto-detects the WoW root, downloads the current official releases when needed, validates the DLLs, backs up `dlls.txt`, and registers both filenames without duplicates. It prompts for the WoW folder only if the normal three-parent path is wrong.

In OctoWoW, launch with the VanillaFixes mod enabled so `dlls.txt` is loaded. If Windows Defender quarantines a DLL, review Protection History or antivirus quarantine, restore it only if trusted, and rerun the installer. If the APIs remain unavailable, the addon loads normally without guessing.

### Details

Player-target behind results are held for 120 ms before FrontBack shows green. Front/side changes apply immediately, preventing single-frame green flashes while players overlap closely.

## Addon integration

Other addons can read `FrontBackAPI:GetPosition()`. It returns `behind, known, directionHint`, where `known` is false when no positioning API is available. `FrontBackAPI:SetEnabled()` and `FrontBackAPI:IsEnabled()` control HUD visibility without duplicating its implementation.
