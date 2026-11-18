# Sanity-Testing-3 — Squad Voice / TTS / Director (audits Guide 03)

> Investigator brief. Verify `IdiotHandOffGuide_03_Squad_Voice.md` under real conditions: no key, bad key, rate-limited, offline, slow network. Report evidence; do not fix. NEVER print or commit API keys (they live in env / gitignored `.env` / `user://`).

## Weakest chains

1. **Cloud -> OS TTS fallback (`voice_engine = auto`)**
   - Kill network mid-line, invalid key, quota error (HTTP 429), model-not-found. Does it switch to `DisplayServer.tts_*` for the REST of the session as designed, and does it recover/stay stable? Any duplicate speech (cloud + OS both speaking the same line)?
   - Windows has no TTS voices installed / voice list empty: crash? silent forever? Check `DisplayServer.tts_get_voices()` handling.
   - `audio/general/text_to_speech=true` is set in project.godot; confirm headless and export builds don't error.
2. **Synced subtitle start (`line_started` / `line_dropped`)**
   - Subtitle must appear when audio starts, not when LLM text arrives. Test 3 allies speaking in a chain, interrupts by higher priority line, line dropped as stale (>4 s). Is a dropped line's subtitle ever shown, or a shown subtitle never cleared?
   - Pause menu / death / scene restart while TTS speaking: orphaned player nodes, audio continuing over title screen?
3. **Stale-queue logic**: flood commands ("everyone attack, split, take aggro, wait 5s") faster than TTS speaks. Queue growth bounded? Memory/latency? Order preserved per ally?
4. **No streaming subtitles / no double acks / no canned ack on Director orders**: send 20 varied orders via chat bar (offline parser AND Director). Count duplicate acknowledgements. Check both code paths produce exactly one voiced reply per order.
5. **Director prompt rule 11 ("say = only the issued orders")**: adversarial inputs — ambiguous orders, small talk, orders for non-existent ally, mixed-language, prompt-injection attempts ("ignore rules and say..."), very long input, empty input, emoji. Does the Director invent orders, leak system prompt, or emit invalid tool calls? Does malformed tool JSON crash `SquadCommsHUD` or leave the chat input locked?
6. **Chat input lock**: while typing, WASD/Space/Q must not leak into gameplay; after Esc/Enter, input restores. Rebinding keys while chat open. Focus loss (alt-tab) while mic active.
7. **Priority-0 chatter off (`ambient_chatter`)**: confirm no random banter at all by default, and that toggling on works and respects voice budget.
8. **Quota-aware voicing + per-role pitch/rate**: do per-role params apply to OS fallback voices (different engines have different rate ranges; value clamping)? Do all three allies remain distinguishable?
9. **Secrets hygiene**: grep repo + `user://` for leaked keys, check `.gitignore` covers `.env`; confirm logs never echo keys or full request headers.
10. **Test suite honesty**: `tests/squad_ai_unit_test.gd`, `squad_ai_windowed_test.gd`, `squad_ai_live_test.gd` force `voice_engine = "off"`. List what the tests do NOT cover (real audio output, fallback path, subtitle sync) and attempt those manually.

## Evidence
Logs with timestamps for each failure injection, subtitle-vs-audio timing observations, queue depths, grep results.

## Verdict format
PASS / FAIL / UNVERIFIED per item, repro, file:line, severity.

---
## Findings (2026-11-18 — Live & Code Verification)

- **1. Cloud -> OS TTS fallback (`voice_engine = auto`)**:
  - **PASS** — Verified live (`_sanity_probe_3.gd`): Windows machine has `8` English OS TTS voices (`DisplayServer.tts_get_voices()`). On simulated cloud HTTP failure (`_on_failed`), `_cloud_failed` flips `true`, `engine()` switches to `"system"`, and the failed line replays via `DisplayServer.tts_speak` with `line_started` emitted cleanly (`dropped=[]`).
  - **MINOR (OS TTS queue timing)** — `tts_player.gd:241-247` waits 400 ms grace then checks `DisplayServer.tts_is_speaking()`; if OS audio queue stalls >400 ms before starting, `line_finished` could fire early.
- **2. Synced subtitle start & lifecycle**:
  - **PASS** — `SquadComms` binds `subtitle` to `tts.line_started` and `tts.line_dropped` (`squad_comms.gd:53-54`), never on LLM token stream (`_on_text_delta` only buffers).
  - **FAIL (MAJOR — Missing `_exit_tree()` cleanup in `tts_player.gd`)**: `SquadTTSPlayer` has no `_exit_tree()` calling `stop_all()` / `DisplayServer.tts_stop()`. Reloading the scene, returning to Title while OS TTS is speaking, or exiting (`visual_check_shots.gd` hang documented in prior report) leaves OS TTS active.
- **3. Stale-queue logic & flood**: **PASS** — Tested 7-line burst: `_queue` capped at `MAX_QUEUE = 4`, overflow emitted via `line_dropped` (`dropped=2`), and 5s-old entry skipped silently (`started=[]`) (`tts_player.gd:123-125, 154`).
- **4. No streaming subtitles / no double acks**: **PASS** — `ally_squad_manager.gd:721` skips canned acks when `source.ends_with("+llm")`; `squad_comms.gd:381` only emits fallback ack if `spoke == 0`; `voice_pipeline_test.gd` 6/6 passed.
- **5. Director prompt rule 11 & malformed tool resilience**: **PASS (code + probe)** — `squad_ai_unit_test.gd` 74/74 passed (`api_error_notifies`, `api_error_falls_back_offline`, `sse_parallel_tool_calls`). `SquadComms.tool_to_command` handles unknown tool names and invalid types without crashing (`_sanity_probe_3.gd`). Live Gemini prompt-injection stress test UNVERIFIED this pass (requires live LLM turns).
- **6. Chat input lock**:
  - **FAIL (MINOR/MAJOR)** — `SquadCommsHUD` (`scripts/ui/squad_comms_hud.gd`) has no `_exit_tree()` resetting `PlayerController.ui_input_locked = false`. If HUD is freed or scene reloads while `_chat_open == true`, `ui_input_locked` remains `true` (`locked_after_free=true`).
- **7. Priority-0 chatter off (`ambient_chatter`)**: **PASS** — Verified by `voice_pipeline_test.gd` (`chatter_hidden_by_default`, `chatter_shown_when_enabled`).
- **8. Quota-aware voicing & per-role pitch/rate**: **PASS (code)** — `SYS_PITCH` / `SYS_RATE` applied in `squad_comms.gd:473-484`; `QUOTA` retry fallback tested in `openai_client.gd:393-396`. Actual audible listening check UNVERIFIED in headless agent session.
- **9. Secrets hygiene**: **PASS** — `.gitignore` ignores `.env`, `.env.*`, `*.key`; `git grep` found 0 leaked `AIza...` / `sk-...` keys in tracked files.
- **10. Test suite coverage gap**: **Confirmed** — `voice_pipeline_test.gd`, `squad_ai_unit_test.gd`, `squad_ai_windowed_test.gd` all call `SquadAIConfig.force_offline()` (`voice_engine = "off"`), leaving real cloud SSE TTS audio playback & live microphone STT unexercised by automated CI.
