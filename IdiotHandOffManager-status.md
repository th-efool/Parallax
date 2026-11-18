# IdiotHandOffManager Status Ledger — CORRECTED 2026-11-18 11:40

> The earlier "verified" marks were wrong. The manager marked items verified on worker reports alone and ran no checks.
> Steps 9–22 were dispatched with paraphrased or invented payloads instead of the guide's verbatim Find/Replace blocks.
> Statuses below come from `git diff`, `--check-only`, and grep (2026-11-18 11:37). Investigation brief: `plan/Sanity-Testing-6.md`.

| Item | Status | Evidence |
| :--- | :--- | :--- |
| S01 ObjectiveTracker defer | implemented, unverified | diff present |
| S02 Warden P1/P2 + dmg | implemented, BUG | `_damage_scaled` removed by manager → EnemyAI._ready() now multiplies Warden 28 → 39 (double-scaled) |
| S03 HEALTH_SCALE 3.25 | implemented, unverified | combat_rules_test not run |
| S04 AttackHitbox scale | implemented, unverified | diff matches guide |
| S05 TTS/HUD exit_tree | implemented, unverified | |
| S06 WorldIntel hittable filter | implemented, BROKEN | calls `intel.is_camera_visible()` which does not exist (Step 15 camera scan never landed) |
| S07 windowed test fix | implemented, unverified | |
| S08 flow timing | partial | player_controller guard landed; feel test only moved spawn, other Target 3+ edits unknown |
| S09 GoreFX | deviated | tween on `emitting` bool, not guide's `set_emitting.bind(false)` |
| S10 vis-range / shadows | BROKEN | `colosseum_greybox_builder.gd` parse error (`VISIBILITY_RANGE_MODE_IGNORE`) → GrandJourneyBuilder fails → level can't build; `leaderboard_store.gd` parse error (`get_rendering_info("shadow_quality")`) |
| S11 warnings | partial | |
| S12 TTS prompt leak | deviated, unverified | |
| S13 bypass auto-clear | implemented, unverified | `_auto_clear_bypassed_stages` + `force_solve_bypass` present |
| S14 ranges/dmg/mobs | partial | +50% mobs, Hall/Chamber ranges, .tres changes NOT applied; DAMAGE_SCALE applied with no once-guard |
| S15 camera targeting / pull | NOT DONE | RANGE_M still 40, no `_scan_camera_visible`; `_catch_up` got a wrong camera-frustum early-return |
| S16 HUD contrast/+20% | deviated, unverified | |
| S17 regen | NOT DONE | only an unused export var; 3× retreat regen still at squad_ally.gd:576 |
| S18 2-checkpoint rewind | deviated, BUG | no enemy/trigger/gate reset, history not cleared on restart, `receive_alert(null,…)` |
| S19 enemy visuals | deviated | flat black override on name match; names don't match node names |
| S20 skeleton revive | BROKEN | `_die` awaits then returns: never really dies/revives, encounter never clears |
| S21 regression test | NOT DONE | 30-line stub |
| S22 MEMORY sync | written, inaccurate | docs describe behaviour that does not exist |
