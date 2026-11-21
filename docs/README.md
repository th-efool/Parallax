# PARALLAX Developer Documentation

These pages explain how the game's systems work and how to change them safely. They are written for developers new to the codebase.

For what the game is and how to run it, see the [project README](../README.md). The design intent (GDD, tuning tables, level atlas, changelog) lives in [`MEMORY/`](../MEMORY/00_MEMORY_INDEX_AND_RULES.md). These docs describe the **code**.

## Reading order

| # | Page | Read it when you need to… |
| --: | :-- | :-- |
| 01 | [Architecture overview](01_architecture_overview.md) | understand the runtime scene tree, autoloads, groups, signals and physics layers |
| 02 | [Realm system](02_realm_system.md) | touch anything that behaves differently in Reality and Mirror |
| 03 | [Combat and damage](03_combat_and_damage.md) | change the player, attacks, hitboxes, enemies or the Warden |
| 04 | [Encounters, waves and saves](04_encounters_waves_saves.md) | work on sections, checkpoints, gates, waves, scoring or save/continue |
| 05 | [Level generation](05_level_generation.md) | move, add or resize anything in the level |
| 06 | [Environment and world](06_environment_and_world.md) | work on breakables, puzzles, terrain, weather, set dressing, wildlife or performance |
| 07 | [UI, HUD and audio](07_ui_hud_and_audio.md) | change the HUD, objectives, menus, loading screen or music and sound |
| 08 | [Squad AI](08_squad_ai.md) | change companion behaviour or add a new squad command |
| 09 | [Voice and LLM](09_voice_and_llm.md) | configure providers, keys, text-to-speech or speech-to-text |
| 10 | [Testing and workflow](10_testing_and_workflow.md) | run or write tests, and follow the project's commit and documentation rules |

## Five rules that prevent most bugs

1. **The level is code.**
   - `main.tscn` is nearly empty in the editor; `GrandJourneyBuilder` builds the level at run time.
   - To see the level, bake `scenes/main/map_preview.scn` with `scripts/tools/bake_map_preview.gd`.
2. **Never hard-code world z positions.**
   - Use `JourneyLayout` (`to_world()`, `story_z()`, `ROUTES`, the stage offsets).
   - Zones, objectives, weather and music all compare story z.
3. **Inactive means no collision.**
   - Anything hidden by a realm, a section or a wave must also disable its colliders and hurtboxes.
   - Hiding the mesh alone causes phantom hits.
4. **One hit per swing.**
   - Hitboxes track their targets per activation.
   - Breakables guard their break with a state check, so damage and score never fire twice.
5. **Keys and saves.**
   - API keys come from environment variables or `.env`, never from committed files.
   - Starting a run (including in tests) clears `user://savegame.cfg`, so back it up first.
