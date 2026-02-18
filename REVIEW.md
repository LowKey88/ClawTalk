# ClawTalk Code Review (v2)

**Reviewed:** 2026-02-18
**Version:** v1.1
**Scope:** Full codebase — 14 source files, ~2,600 lines Swift

---

## Overview

ClawTalk is a native iOS voice chat app (Mic → STT → LLM → TTS → Speaker) built with Swift/SwiftUI. Clean separation between Views, Services, and Models, with an enum-driven state machine. Good foundation — but several runtime bugs and architectural issues need attention before wider use.

---

## What's Done Well

- **State machine** (`ChatState` enum) — single source of truth for display text, icon, and color across the entire UI. No scattered state checks.
- **`TTSChunkQueue` actor** — correct concurrency primitive for serializing TTS API calls. Chunks always play in order without manual locks.
- **Chunked TTS streaming** — speaking while the LLM is still generating. The punctuation-based chunking + 120-char max fallback is practical.
- **VAD implementation** — configurable thresholds (-25dB), silence timeout (1.5s), minimum speech duration (0.3s), and echo ignore period cover real-world edge cases.
- **Profile isolation** — per-profile messages, voice, URL, all cleanly keyed by profile UUID.
- **Bluetooth mic preference** — `preferBluetoothMic()` called before each recording. Good for headset/glasses users.
- **UI polish** — HandsFreeButton state transitions, date separators, context menus, error retry on tap, waveform visualizations.

---

## Critical / High Issues

### 1. `saveMessages()` fires on every streaming token (High — Performance)

**`ChatViewModel.swift:76-78`** — `messages` has a `didSet { saveMessages() }`. During streaming, `messages[messageIndex].content += token` triggers this for every token. Each call runs `JSONEncoder().encode(messages)` and writes to UserDefaults. On a typical response you get 50-200 tokens, each triggering a full JSON serialization + disk write.

**Impact:** UI jank during streaming, battery drain, unnecessary disk I/O.

**Fix:** Debounce saves — only save after streaming completes, or use a timer (e.g. save at most once per second).

### 2. `messageIndex` can crash if messages mutate during streaming (High — Crash)

**`ChatViewModel.swift:248`** — `let messageIndex = messages.count - 1` is captured once. But the user can delete messages via context menu or clear chat during streaming. If a message is removed, `messageIndex` points to the wrong message or crashes with index-out-of-bounds at line 295: `self.messages[messageIndex].content += token`.

**Fix:** Track the message by its `UUID` instead of index. Find it with `firstIndex(where:)` before each mutation.

### 3. No task cancellation — `stopAll()` doesn't cancel the pipeline (High — Bug)

**`ChatViewModel.swift:165-172`** — `stopAll()` stops the player and sets state to `.idle`, but the running `processAudio` Task at line 143/182 continues executing in the background. It will continue to call STT, LLM, and TTS APIs, then append messages and start playback after the user already pressed stop.

**Fix:** Store the `Task` handle, cancel it in `stopAll()`, and check `Task.isCancelled` at each pipeline stage.

### 4. API keys stored in plain UserDefaults (High — Security)

**`Settings.swift:37-44`** — OpenAI and ElevenLabs API keys in `UserDefaults`. Readable in device backups, visible to any process in the sandbox. Gateway tokens in `BotProfile` (line 11) have the same issue — they're JSON-encoded into UserDefaults with the profile array.

**Fix:** Use iOS Keychain via `SecItemAdd`/`SecItemCopyMatching`.

---

## Medium Issues

### 5. LLM only sees 1 message — conversation history always empty (Medium — Bug)

**`ChatViewModel.swift:243`** — `OpenClawService` is instantiated fresh every call. Its `conversationHistory` starts empty. The "last 20 messages" sent to the LLM (`OpenClawService.swift:26`) only contains the current message. The bot has no memory of the conversation.

**Fix:** Pass `viewModel.messages` to the service, or keep a single service instance per profile.

### 6. URLSession leaked on every streaming call (Medium — Memory Leak)

**`OpenClawService.swift:38-41`** — `URLSession(configuration: config)` is created per call and never invalidated. Each leaks a session with its internal connection pool and delegate queue. Over a 30-minute conversation with 20+ exchanges, this accumulates.

**Fix:** Create the session once in `init()` and call `session.finishTasksAndInvalidate()` in `deinit`.

### 7. `finishQueue()` races with fire-and-forget TTS tasks (Medium — Bug)

**`ChatViewModel.swift:281-285`** — `speakChunk()` uses `Task { await ttsQueue.enqueue(text:) }` (fire-and-forget). At line 348, `player.finishQueue()` runs after `sendMessageStreaming` returns. But the fire-and-forget TTS tasks from the streaming callback may still be in-flight. `finishQueue()` sees an empty queue and fires the completion callback early, cutting off the last chunks.

**Fix:** Track pending chunk count in `TTSChunkQueue`. Only call `finishQueue()` after all chunks are confirmed enqueued, or add an `isFinished` flag to `AudioPlayer` and defer completion.

### 8. Single recording file path — overwrite race (Medium — Bug)

**`AudioRecorder.swift:29-31`** — `recordingURL` always returns the same path (`clawtalk_recording.m4a`). When VAD delivers `audioURL` to the delegate, processing starts async (STT upload). If the hands-free loop restarts recording before STT reads the file, the new recording overwrites the file being uploaded.

**Fix:** Use unique filenames per recording, e.g. `clawtalk_\(UUID()).m4a`. Clean up after STT completes.

### 9. Hardcoded `"user": "syam"` in API requests (Medium — Security/Correctness)

**`OpenClawService.swift:31, 93`** — Hardcoded user identifier sent to the backend. Should come from profile settings or be derived from the device.

### 10. Audio session configured in 3 places with different options (Medium — Bug)

Audio session is set up in:
- `ClawTalkApp.swift:39` — uses `.mixWithOthers`
- `AudioRecorder.swift:41` — no `.mixWithOthers`
- `AudioPlayer.swift:63` — no `.mixWithOthers`

The last call wins. `AudioRecorder.setupAudioSession()` runs in `init()` and overrides the app-level configuration, removing `.mixWithOthers`. Then `AudioPlayer.prepareAudioSession()` overrides again before each playback. This creates inconsistent audio behavior.

**Fix:** Configure the audio session once in the App struct. Remove the duplicate setup calls from AudioRecorder and AudioPlayer.

### 11. Code duplication: `retryLastMessage` copies 90 lines from `processAudio` (Medium — Maintainability)

**`ChatViewModel.swift:442-537`** — The entire streaming + chunked TTS pipeline is duplicated. The retry version also misses `resumeListening` behavior and `lastSpokenText` echo tracking differences. Any bug fix needs to be applied in two places.

**Fix:** Extract into a shared `sendToAgent(transcript:settings:resumeListening:)` method.

---

## Low Issues

### 12. `isConfigured` computed property has side effects (Low — Code Smell)

**`Settings.swift:114-126`** — Reading `isConfigured` can mutate `activeProfileID` (line 118). A getter with side effects causes unpredictable behavior with SwiftUI's observation system, which may re-evaluate this property at unexpected times.

**Fix:** Move the auto-select-first-profile logic into `init()` or a dedicated method.

### 13. Thread safety: `audioLevel` written from background, read from MainActor (Low — Data Race)

**`AudioRecorder.swift:193-197`** — `updateMeters()` runs on `DispatchQueue.global(qos: .userInteractive)` and writes `audioLevel`. `ChatViewModel`'s `startLevelTimer()` reads it from `@MainActor` context. No synchronization.

**Fix:** Make `audioLevel` reads/writes atomic, or dispatch the write to MainActor.

### 14. `DateFormatter` created on every call (Low — Performance)

**`ChatView.swift:297-308`** — `dateSeparatorText(for:)` allocates a new `DateFormatter` each invocation. `DateFormatter` is expensive to create. During scroll, this is called per visible message.

**Fix:** Use a `static let` formatter.

### 15. `WaveDots` timer runs indefinitely even when off-screen (Low — Resource Waste)

**`ChatView.swift:479`** — `Timer.publish(every: 0.05)` starts on init and never stops. When `StatusBubble` is not visible (state is `.idle`), the `WaveDots` view is not rendered — but if SwiftUI keeps the view alive in the hierarchy, the timer keeps firing at 20Hz.

### 16. `sendMessage` (non-streaming) is dead code (Low — Cleanup)

**`OpenClawService.swift:78-109`** — Never called anywhere. Remove or mark as future use.

### 17. Force-unwraps on URL construction (Low — Crash Risk)

**`OpenClawService.swift:16, 79`**, **`WhisperService.swift:11`**, **`ElevenLabsService.swift:19, 47`** — `URL(string:)!` will crash on malformed input. User-provided URLs (from profile settings) can contain spaces, non-ASCII characters, etc.

**Fix:** Use `guard let url = URL(string:) else { throw }`.

### 18. No timeouts on STT/TTS requests (Low — UX)

**`WhisperService.swift`** and **`ElevenLabsService.swift`** use `URLSession.shared` defaults (60s timeout). For a real-time voice app, 15-20s would be more appropriate to fail fast.

### 19. Hallucination filter hardcodes language assumption (Low — Correctness)

**`WhisperService.swift:77-81`** — The Latin character ratio check (<30% = discard) assumes English/Malay speakers. Users speaking Arabic, Hindi, Thai, or other non-Latin scripts would have legitimate transcriptions silently discarded.

### 20. Unused `Combine` imports (Low — Cleanup)

**`AudioRecorder.swift:3`**, **`AudioPlayer.swift:3`**, **`ChatView.swift:2`** — `import Combine` not used.

### 21. `startSpeakingTimer()` is `internal` — should be `private` (Low — Encapsulation)

**`ChatViewModel.swift:395`** — All other timer methods are `private`. This one is exposed unnecessarily.

### 22. Echo detection too aggressive with common words (Low — False Positives)

**`ChatViewModel.swift:425-440`** — 40% word overlap using raw word sets. Short sentences with common words ("I think so", "that is good") can easily hit 40% overlap with unrelated responses. No stop-word filtering.

---

## Summary

| Category | Count |
|---|---|
| Critical / High | 4 |
| Medium | 7 |
| Low | 11 |
| **Total** | **22** |

### Top 5 Priorities

1. **Debounce `saveMessages()`** — JSON encoding on every streaming token is the most impactful performance fix
2. **Track messages by UUID, not index** — prevents crashes during streaming if user interacts with messages
3. **Cancel tasks on `stopAll()`** — prevents ghost API calls and state corruption after user stops
4. **Pass conversation history to LLM** — the bot currently has no memory between exchanges
5. **Store API keys in Keychain** — required for any public release

### Architecture Assessment

The state machine, actor-based TTS queue, and chunked streaming pipeline show good iOS engineering. The main structural issue is that `ChatViewModel.processAudio()` is a 150-line monolith that handles STT → echo detection → LLM streaming → chunked TTS → queue management → error recovery in one method. Extracting the LLM+TTS pipeline into its own class would solve the duplication with `retryLastMessage` and make cancellation/testing easier.

For a v1.1 personal project, this is solid work. The issues above are ordered by impact — fixing the top 5 would make it production-ready.
