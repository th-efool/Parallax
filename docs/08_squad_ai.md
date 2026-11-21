# 08. Squad AI (the Echo companions)

This page explains how the three AI companions are defined, how player orders become behaviour, and how to add a new command. Voice, speech-to-text and the LLM transport are covered in [09_voice_and_llm.md](09_voice_and_llm.md).

## 1. Purpose and file map

The squad is three "Echoes" who fight beside the player. They follow in formation, fight on their own, protect wounded teammates, and obey free-text orders (typed or spoken). Every order, whatever its source, is reduced to one Dictionary schema and executed by the same code, so typed chat, voice and LLM tool calls behave identically.

Note on locations: the command model, parser, strategies and intel live in `scripts/allies/`. The `addons/parallax_squad_ai/` addon holds only the comms hub, the LLM client, config, text-to-speech and microphone code.

| File | Role |
| :-- | :-- |
| [ally_profile.gd](../scripts/allies/ally_profile.gd) | `AllyProfile` resource: stats, abilities, skills, voice, voice lines |
| [ally_skill.gd](../scripts/allies/ally_skill.gd) | `AllySkill` sub-resource: one signature skill (data only) |
| [01_brannoc.tres](../data/allies/01_brannoc.tres), [02_sera.tres](../data/allies/02_sera.tres), [03_ivo.tres](../data/allies/03_ivo.tres) | The three shipped profiles |
| [squad_command.gd](../scripts/allies/squad_command.gd) | `SquadCommand`: verb table, priorities, per-order state |
| [squad_command_parser.gd](../scripts/allies/squad_command_parser.gd) | `SquadCommandParser`: offline keyword parser |
| [squad_strategies.gd](../scripts/allies/squad_strategies.gd) | `SquadStrategies`: data-only squad plans |
| [world_intel.gd](../scripts/allies/world_intel.gd) | `WorldIntel`: enemy IDs, descriptions, marks, selector resolution |
| [ally_squad_manager.gd](../scripts/allies/ally_squad_manager.gd) | `AllySquadManager`: spawn, routing, chains, combos, auto-rally |
| [squad_ally.gd](../scripts/allies/squad_ally.gd) | `SquadAlly`: the per-ally body and per-frame AI (`_run_*`) |
| [squad_comms.gd](../addons/parallax_squad_ai/squad_comms.gd) | `SquadComms`: entry point for typed/spoken orders, LLM director |
| [squad_comms_hud.gd](../scripts/ui/squad_comms_hud.gd) | `SquadCommsHUD`: chat bar, push-to-talk, mark keys, subtitles |
| [enemy_ai.gd](../scripts/enemies/enemy_ai.gd) | Enemy side of taunt, threat table and fixation |

## 2. Roles and profiles

`AllySquadManager.load_profiles()` loads every `.tres`/`.res` in `res://data/allies/`, keeps those that are an `AllyProfile`, and sorts by `order`. `_spawn_squad()` creates one `SquadAlly` per profile (up to `max_allies`, default 6). Adding a fourth ally therefore needs only a new resource file; no code change.

Roles (`AllyProfile.role`) decide default recipients, combo halves and stand-in choice when someone is down:

| Ally | Role | Abilities | Signature skills (id) |
| :-- | :-- | :-- | :-- |
| Brannoc | vanguard | taunt, charge, bodyguard, revive | war_cry, shield_wall, ground_breaker |
| Sera | skirmisher | taunt, kite, lure, finisher, revive | shadowstep, fan_of_blades, smoke_bomb, flurry |
| Ivo | artillery | nuke, mine, revive | mirror_barrage, mending_light, mirror_ward, chain_arc |

An `AllyProfile` carries four groups of data:
- Body: `model_path`, `keep_props`, `borrow_props`, `tint`, `model_scale`.
- Stats: `max_health`, `move_speed`, `aggro_radius`, `attack_damage`, `attack_range`, `attack_cooldown`, `retreat_threshold`, `regen_per_sec`, `damage_taken_mult`.
- Abilities: `abilities` (strings checked by `has_ability()`), `skills` (an array of `AllySkill`), taunt and nuke tuning.
- Voice: `tts_voice` (OpenAI), `gemini_voice`, `tts_instructions`, and `voice_lines` (event name to an array of lines, read through `profile.line(event, fallback)`).

`AllySkill` is pure data (`effect`, `target_kind`, `cooldown`, `radius`, `power`, `duration`, `auto_use`, `aliases`). The behaviour of each `effect` lives in a matching `SquadAlly._skill_*` function, dispatched by `use_skill()`. `auto_use` (for example `swarmed`, `protect`, `cluster`, `engaged`, `ally_low`, `stunned_target`) is evaluated by `_auto_skills()` every 0.4 s, so a skill fires on its own when its condition holds and it is off cooldown. A ceasefire restricts autonomous use to the defensive conditions.

## 3. The command model

### 3.1 One schema

Parser output and LLM tool calls both produce a Dictionary:

```
{ "verb": String, "allies": ["all" | names], "target": String, "count": int, "text": String, "enabled": bool, ...verb-specific keys }
```

`AllySquadManager.issue()` wraps it with `SquadCommand.make(verb, dict, source)`, which stores the dictionary in `args`. `source` is one of `chat`, `voice`, `llm` (the manager receives `"chat+llm"`/`"voice+llm"` for LLM turns), or `auto`.

### 3.2 Verbs, priority, finite and stance

The authoritative table is `SquadCommand.VERBS`: `verb -> [priority, finite, is_stance]`.

| Priority | Value | Verbs |
| :-- | --: | :-- |
| AUTO | 0 | internal only |
| ORDER | 1 | follow, hold, attack, retreat, auto_engage, taunt, jump, dance, emote, say, status, stop, split, hit_and_run, hunt, destroy, interact, skill, surround, overwatch, strategy, position, rearguard, ranged, circle, face, chat |
| MISSION | 2 | peel, ambush, bodyguard, kite, nuke, revive, combo_kite_nuke, combo_charge_finish, combo_lure_detonate |
| PANIC | 3 | massacre, ceasefire, scatter |

- Finite: the order completes on its own (attack, kite, jump...). Non-finite orders run until replaced.
- Stance: a standing posture (follow, hold, retreat, split, overwatch, position, rearguard, massacre, ceasefire). Stances replace each other and are resumed after a finite order that interrupted them.
- `SquadCommand.make()` maps an unknown verb to `say`, and clamps `jump` count to `MAX_JUMPS` (12). `describe()` produces the short text used in the command log.

### 3.3 Routing and priority rules

`AllySquadManager._route(ally, cmd)` decides what happens when an order meets whatever the ally is already doing:

- Downed ally: ignored (`"is down"`).
- `massacre`/`ceasefire`: clear the queue and take over immediately.
- Nothing running: assign.
- Higher priority than the current command: preempt. A preempted mission or finite order is pushed to the front of the queue and resumes afterwards.
- Equal priority: queue behind a mission or a finite order (reported as `queued (mission lock)` for a mission); otherwise replace.
- Lower priority: a stance is replaced by an explicit order (and resumed after a finite one); a mission blocks and the new order queues.

`SquadAlly.assign()`, `enqueue()`, `clear_queue()` and `finish_current()` implement the state: `current` is the active command, `queue` holds up to 6 more. `enqueue()` inserts finite orders ahead of any stance. When `finish_current()` runs, the next queued command is assigned.

### 3.4 Batches and chains

Everything said in one message is one batch. `SquadComms` and `issue_commands()` call `begin_batch()` / `end_batch()`. Inside a batch, `issue()` records each ally's commands in `_batch`. On `end_batch()`, an ally with two or more steps gets a chain: the first step is assigned, the rest are queued in order, older finite orders wait behind the chain, and older stances are dropped.

For all steps except the last, stance verbs in `CHAIN_STEP_VERBS` (follow, hold, position, rearguard, overwatch, retreat) are converted into timed steps (`chain_step = true`, finite). `SquadAlly._run_command()` finishes such a step on arrival (plus 0.6 s) or after 6 s (3 s for other verbs). `hold` with `step_sec` ("wait 3 seconds") finishes when its timer passes. If an ally under a mission lock receives a chain, the whole chain waits behind the mission.

An LLM turn is one batch: each tool call in the response is one step, and calls for the same ally run in the order listed.

### 3.5 Recipients and stand-ins

`_recipients(c)` resolves names (`all`, `everyone`, `squad`, `team`, or ally names). With no names it uses verb defaults: `ROLE_FOR_VERB` (bodyguard to vanguard, kite to skirmisher, nuke to artillery, taunt and peel to vanguard, hit_and_run to skirmisher, destroy to vanguard), the nearest able ally for `revive`/`interact`/`hunt`, the leader for `say`, otherwise everyone.

If a named ally is down, `issue()` asks `_pick_for(ability, role, exclude, addressed)` for a stand-in (scored by role match, ability, whether it is mission-locked, retreating, and health), and the stand-in announces the substitution. If nobody can substitute the order is dropped and logged.

Instant verbs are resolved inside `issue()` and never reach the per-frame code: `say`, `status`, `auto_engage`, `stop`, `chat`, `split`, `strategy`, `skill`, and the three combo verbs.

### 3.6 Strategies

[squad_strategies.gd](../scripts/allies/squad_strategies.gd) is a data list (`LIST`). Each entry has `id`, `name`, `desc`, `aliases` (used by the offline parser) and `roles`, a map from role (or `any`) to a list of `{verb, args}` steps. `execute_strategy()` expands this onto the living squad: panic-locked allies are skipped, others have their queue cleared and get the steps assigned in order. Argument tokens are replaced at that point: `$target`, `$distinct`, `$weakest_distinct`, `$weakest_friend`, `$vanguard`, `$slot_angle`, `$line_spot`, `$behind_spot`, `$player_spot`. The vanguard then announces the plan. Adding a plan means adding one dictionary; the LLM sees `id`, `name` and `desc` through `SquadStrategies.describe_all()`, and the tool enum comes from `SquadStrategies.ids()`.

### 3.7 Combos

The three two-ally handshake combos (`kite_nuke`, `charge_finish`, `lure_detonate`) are started by `_start_combo()`. `COMBO_PARTS` maps each combo to two parts (for example kiter and nuker), each with a preferred ability and role. The manager coordinates via `combo_event()`, `_tick_combos()`, `_combo_coordinate()`, `_substitute()` and `_abort_combo()`. If a part's owner is unavailable it substitutes another ally, and if only one ally is left it falls back to a solo variant (`solo_kite_nuke`, and so on). The per-ally halves run in `SquadAlly._run_combo_part()`.

## 4. The offline parser

[SquadCommandParser.parse(text, ally_names, ctx)](../scripts/allies/squad_command_parser.gd) is a static function used whenever there is no API key, the mode disallows the LLM, or an API request fails. It never throws: unrecognised input becomes a `chat` command (if an ally was addressed) or a `say` command with `confused = true`.

Pipeline:
1. Lower-case the text; treat sentence ends and commas as clause boundaries.
2. `_normalize()` applies fuzzy name and vocabulary correction (Levenshtein, `_lev`).
3. `_split_clauses()` splits on sequencing words ("then", "after that", ";") and `_split_joined()` splits on joiners (`CLAUSE_JOINERS`) only when both sides carry their own instruction. Multi-word rule phrases containing "and" ("kite and nuke") are protected.
4. `_parse_clause()` picks the addressee (`_addressed()`), then the verb by scanning `RULES` in order (first match wins; panic verbs, then specialised phrases, then generic ones). It also tries `_match_skill()` (skill names and aliases from `ctx`) and `SquadStrategies.match_text()` before plain verbs; panic verbs always win.
5. Verb-specific arguments are filled in: `count` for jump, `spot` for position (`POSITION_SPOTS`), `step_sec` for hold, emote name, lure flag for kite, bodyguard/revive target, assist target (`ally:<name>`), chat topic.
6. Targets come from `_target_word()` (`TARGET_WORDS`) or, when the clause contains descriptors, `desc:<text>` for `WorldIntel.resolve()`. Pronouns ("it", "that one") reuse the last named target in the message. "everyone else" means every ally not yet mentioned.

Rule order matters because the first matching verb wins. Put narrow phrases before broad ones (the file already does this: combos before `kite`, `attack` late, `follow` after `hold`).

## 5. The LLM director and tool path

Online orders go through [SquadComms](../addons/parallax_squad_ai/squad_comms.gd). `submit_utterance(text, via)` is the single entry for chat and voice. If `SquadAIConfig.is_online()`, `_ask_llm()` builds a system prompt (`build_system_prompt()`) containing the live roster, skills, strategies, marked targets, the `WorldIntel` battlefield table, player state and recent events, then calls `client.chat_stream(messages, tools(), 0.7)`. Otherwise `_offline()` runs the parser and calls `AllySquadManager.issue_commands()`.

The tools exposed by `SquadComms.tools()` are `command_allies`, `use_skill`, `execute_strategy`, `start_combo`, `panic_order` and `say`. When the stream completes, `_on_chat_completed()`:
1. Opens a batch, then maps each call with `tool_to_command()` and calls `AllySquadManager.issue(cmd, via + "+llm")`. `say` calls become spoken lines through `_voice()`.
2. Excludes allies given a direct order from any squad-wide strategy in the same turn.
3. Closes the batch (chains form here), stores the exchange in the director history (capped at `HISTORY_MAX`), and emits `tool_called` and `log_entry`.
4. If the model produced no `say`, speaks the plain text or a canned acknowledgement. Orders with source ending `+llm` do not get a second canned ack from the manager.

`tool_to_command()` is the translation layer between tool actions and verbs. Aliases to know: `wait` becomes `hold` with `step_sec`; `take_aggro` becomes `taunt` with `area = true`; `sneak_attack` becomes `surround` with `side = rear`, `angle = 180`; `auto_engage_on/off` become `auto_engage`; `kite` with `lure_to_player` sets `lure = player`.

On a chat request failure `_on_request_failed()` notifies the player and re-runs the same text through the offline parser, so an order is never lost.

## 6. Per-frame execution

Each `SquadAlly._physics_process()` runs, in order: timers, downed handling, safe-position recording, regeneration, `_catch_up()` (teleport leash), embedded-in-geometry recovery, dash, stagger and timed-action processing (each returns early), `_check_self_preservation()`, `_auto_skills()` every 0.4 s, self-retreat, then the command. With no command it runs `_run_follow()`; otherwise it advances `cmd.timer` and calls `_run_command()`.

`_run_command()` first handles timed steps and chain steps, then dispatches on `cmd.verb`:

| Verb | Handler | Notes |
| :-- | :-- | :-- |
| follow | `_run_follow` | Formation slot; auto-engage within 4 m of the player |
| hold | `_run_hold` | Fixes a spot, fights within `engage_r` |
| retreat | `_run_retreat_order` | Falls back behind the player |
| attack | `_run_attack` | Resolves target once into `cmd.data["enemy"]`, then `_fight()` |
| taunt | `_run_taunt_cmd` | Single target or area (see section 8) |
| bodyguard | `_run_bodyguard` | Intercept threats near a ward, else hold a guard spot |
| kite / nuke / revive | `_run_kite`, `_run_nuke`, `_run_revive` | Phased (`cmd.step`) missions |
| massacre / ceasefire / scatter | `_run_massacre`, `_run_ceasefire`, `_run_scatter` | Panic stances |
| position / rearguard / ranged / circle | `_run_position`, `_run_rearguard`, `_run_ranged`, `_run_circle` | Movement and ranged stances |
| surround / peel / ambush / hit_and_run / overwatch | `_run_surround`, `_run_peel`, `_run_ambush`, `_run_hit_and_run`, `_run_overwatch` | Tactics used by strategies |
| hunt / destroy / interact | `_run_hunt`, `_run_destroy`, `_run_interact` | World errands |
| skill | `_run_skill` | Walks into range, calls `use_skill()` |
| jump / dance / emote / face | `_run_jump`, `_start_action`, `_run_emote` | Finish immediately |
| combo_* | `_run_combo_part` | Dispatches by `cmd.combo_part` |
| anything else | `finish_current("ok")` | |

Handlers share a pattern: resolve targets once and cache them in `cmd.data`, use `cmd.step` for phases, call `_move_to()`/`_fight()`, and end with `finish_current(result)` (which also emits `command_finished`). `assign()` resets `cmd.data` (except the rally flag), so anything that must survive an interruption belongs in `cmd.args` (for example `_run_hold` writes its spot back into `args`).

Fighting: `_fight(e, delta, hold_ground)` handles artillery (ranged bolts, no sword unless cornered or in massacre), distinct attack slots per ally (`slot_index`), and `_melee()` with per-role animation sets. Movement uses `_move_to()` with context steering, personal space around allies, the player and enemies, stuck detection and safe-spot recovery.

## 7. Follow, formation and leash

- Formation: `_formation_point(player)` picks one of six offsets by `slot_index`, relative to the player's facing, kept out of the over-shoulder camera line. `_run_follow()` scales speed with distance, matches a running player, and moves out of the camera lens quickly (`_camera_blocking_at`).
- Auto-engage in follow: only enemies within 4 m of the player are engaged, and the target is dropped beyond 5.5 m. Followers never chase across the arena. `auto_engage` can be toggled per ally by an order.
- Leash: `FOLLOW_LEASH` is 19.5 m. `_catch_up()` blinks (`_blink_to()`) an ally back to a safe spot near the player if it is too far, falls into a pit or is vertically trapped, unless the ally has a free leash.
- Free leash: `has_free_leash()` is true when the current or any queued command is anything other than `follow` or `ceasefire`. Such allies are not teleported back (except for pit rescue) and may roam the arena for an order. Remember this when adding a verb: any new verb gives its ally a free leash automatically.

## 8. Taunt, fixation and EnemyAI

Taunts are the squad's way of controlling where enemies go. The ally calls `EnemyAI.apply_taunt(source, bonus, lock_sec)`:
- `_do_taunt()` (single target) and the area branch of `_run_taunt_cmd()` use a 4.0 s lock. `_do_taunt(e, area=true)` also nudges nearby enemies within 6 m with a 2.5 s lock and large bonus.
- Locks of 3 s or more create fixation (`taunt_fixation`, enabled by default): the enemy ignores its home leash and lose-sight range and keeps chasing its taunter. Fixation ends when the taunter is down or untargetable, another entity taunts it, it is made to forget (smoke bomb), or the taunter stays more than 60 m away for 5 s (`FIXATION_BREAK_DIST`).
- Short nudges (under 3 s) never break an existing fixation, even from another taunter.
- Target selection in `_select_target()` honours the lock before the threat table; the lock also bypasses the enemy's chase leash and flee checks.

Practical consequence for ally design: a taunted enemy will follow the taunter anywhere, so pair a bait (`kite`, `taunt`) with attackers, and be careful when a taunter is far from the squad. `kite` with `lure = player` converts a taunt into a circling kite next to the player so others can strike.

## 9. Auto-rally

`AllySquadManager._tick_rally()` runs every physics frame and scans about every 0.3 s. A ward is the player (below `RALLY_PLAYER_HP`, 35 percent) or any ally (below `RALLY_ALLY_HP`, 40 percent), and a rally starts only if `_threats_on()` finds enemies targeting the ward or aggroed within `RALLY_DANGER_R` (7 m).

`_start_rally()` gives every other able ally a `bodyguard` command at ORDER priority with source `auto`, marked `rally = true` in both `args` and `data`. The interrupted command is pushed to the front of the queue so it resumes later. Allies are skipped if they are under a panic order, reviving, in a combo, already rallying, or already guarding that ward. `_update_rally()` ends the rally when the ward is above `RALLY_SAFE_HP` (55 percent), or no threat is within `RALLY_CLEAR_R` (9 m) for 2.5 s, or the ward is gone; it then removes rally commands and starts a 4 s cooldown for that ward. `rally_enabled` turns the system off. Because a rally command is ORDER priority and not a mission, a fresh player order still takes over.

## 10. Enemy marking

- Input: [squad_comms_hud.gd](../scripts/ui/squad_comms_hud.gd) registers `mark_enemy` (T or middle mouse) and `clear_marks` (X). Mark calls `WorldIntel.mark_enemy_at_aim()` (toggle: marks or unmarks the enemy under the aim, up to `MARK_AIM_MAX_DIST` 180 m, line of sight checked); X calls `clear_marks()`.
- Storage: `WorldIntel` keeps up to `MAX_MARKS` (4) marks (`M1`..`M4`); marking a fifth evicts the oldest. Each mark also creates a region of `MARK_REGION_RADIUS` (18 m) in which enemies are tagged `in_mark_region`; zones linger `MARK_REGION_LINGER_SEC` (10 s) after the marked enemy dies.
- Resolution: `WorldIntel.resolve(selector, asker)` understands `M1`..`M4`, `marked`, `marked group` (the region), `E3` style IDs, type words, superlatives and free descriptions. An empty or `marked_or_nearest` selector prefers the primary mark.
- Auto-targeting: `AllySquadManager.pick_enemy_for()` subtracts large distance bonuses for marked enemies (and smaller ones for region members), prefers enemies targeting the player or the ally, and penalises enemies another ally already holds so the squad does not stack on one target.
- The manager's `resolve_enemy()` adds `ally:<Name>` ("whatever Sera is fighting") and then defers to `WorldIntel.resolve()`.

## 11. How to add a new command verb, end to end

Suppose you add `guard_door`.

1. Declare it in `SquadCommand.VERBS` in [squad_command.gd](../scripts/allies/squad_command.gd): `"guard_door": [Priority.ORDER, false, true]`. Choose priority, finite and stance deliberately: a mission locks the ally, a stance resumes after interruptions. Add a case to `describe()` if the log text should be nicer.
2. Implement behaviour in [squad_ally.gd](../scripts/allies/squad_ally.gd): add `"guard_door": _run_guard_door(delta, player, cmd)` to `_run_command()` and write the handler. Cache resolved targets in `cmd.data`, keep anything that must survive interruption in `cmd.args`, use `cmd.step` for phases, and call `finish_current("reason")` on every exit path (including "target gone" and timeouts, using `_approach_timeout()`).
3. Route it in [ally_squad_manager.gd](../scripts/allies/ally_squad_manager.gd): if it needs a default ally, add it to `ROLE_FOR_VERB`. If it should act instantly without per-frame state, handle it in the `match verb` block of `issue()` (like `status`). If it is a stance that can be a middle step of a chain, add it to `CHAIN_STEP_VERBS`.
4. Teach the offline parser in [squad_command_parser.gd](../scripts/allies/squad_command_parser.gd): add a `RULES` entry (mind the order), add the verb to `TARGETED_VERBS` if it takes an enemy target, and add a `match` case in `_parse_clause()` for any extra arguments.
5. Expose it to the LLM in [squad_comms.gd](../addons/parallax_squad_ai/squad_comms.gd): add the action to the `command_allies` `action` enum in `tools()` and any new argument to its properties, extend `tool_to_command()` if the action name differs from the verb or carries arguments, and mention it in the system prompt rules if the model needs guidance.
6. Add voice lines: new event keys go in each `voice_lines` dictionary of `data/allies/*.tres`. `say_event(event)` falls back silently if a profile has no line, so missing lines are not fatal.
7. Test: run `--check-only` on every edited script (see [10_testing_and_workflow.md](10_testing_and_workflow.md)), add a parser case to [squad_ai_unit_test.gd](../tests/squad_ai_unit_test.gd), and exercise the behaviour in [squad_ai_windowed_test.gd](../tests/squad_ai_windowed_test.gd) or the friends regression suite.
8. Update `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md` and append a line to `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`, per the project rules.

## 12. Common pitfalls

- An unknown verb is rejected in `issue()` ("unknown verb") and the leader says it is confused; `SquadCommand.make()` would turn it into `say`. Always add the verb to `VERBS` first.
- The tool enum in `tools()` and the `VERBS` table are separate lists. A verb missing from the enum can never be produced by the LLM, only by the parser or a strategy.
- `assign()` clears `cmd.data` for non-combo commands. State stored there is lost on preemption; store resumable state in `cmd.args`.
- Every non-follow command grants a free leash. A verb that finishes immediately is fine, but a long-running verb that does not end will keep the ally from being teleported back to the player.
- Never leave a handler path without `finish_current()` or a state change; the ally will otherwise appear frozen on that command.
- Strategy steps go through the same routing rules as any command, so a strategy step with MISSION priority locks that ally.
- Rally commands are ORDER priority, marked `rally`. When changing `assign()` or `enqueue()`, keep the rally flag intact or helpers will not stand down.
- Inactive-realm or held enemies must be filtered with `_enemy_ok()` / `is_hittable_now()` when you write new target searches, or allies will chase phantoms.
