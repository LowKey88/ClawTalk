# ClawTalk Code Review

**Reviewed:** 2026-02-18
**Version:** v1.1
**Scope:** Full codebase (14 source files, ~2,600 lines Swift)

---

## Overview

ClawTalk is a native iOS voice chat app — Mic → STT → LLM → TTS → Speaker — built with Swift/SwiftUI. The architecture is clean for a v1.1 project: clear separation between Views, Services, and Models, with a well-designed state machine driving the UI.

---

## What's Done Well

### Architecture
- The `ChatState` enum-driven state machine is solid. Each state maps to a display string, icon, and color — single source of truth for the entire UI.
- `TTSChunkQueue` as a Swift `actor` is the correct concurrency primitive. It serializes TTS API calls so audio chunks always play in order without manual locking.
- Profile isolation (per-profile messages, voice, URL) is cleanly implemented via `messagesKey` derived from the profile UUID.

### Audio Pipeline
- Chunked TTS streaming (speak while LLM is still generating) is a meaningful UX optimization. The chunk-on-punctuation + max-length fallback at 120 chars is a practical approach.
- VAD with configurable thresholds, silence timeout, min speech duration, and echo ignore period covers the common edge cases.
- Bluetooth mic preference (`preferBluetoothMic()`) called before each recording is a good detail for headset users.

### UI/UX
- The `HandsFreeButton` that changes icon/color based on state (ear → arrow-up → stop) is intuitive.
- Date separators, context menus (copy/delete), error retry on tap — these are polished touches.

---

## Issues Found

### 1. Security: API Keys in UserDefaults (High)

**`Settings.swift:37-44`** — API keys (OpenAI, ElevenLabs) are stored in plain `UserDefaults`. This is readable by any process with the same sandbox, visible in iTunes backups, and not encrypted at rest.

**Recommendation:** Use Keychain Services via `SecItemAdd`/`SecItemCopyMatching`, or a wrapper like `KeychainAccess`. Gateway tokens in `BotProfile` (`Settings.swift:11`) have the same issue since they're encoded to UserDefaults with the profile array.

### 2. Security: Hardcoded User Identity (Medium)

**`OpenClawService.swift:31`** — `"user": "syam"` is hardcoded in the request body. Should come from settings or be derived from the device/profile.

### 3. Bug: New URLSession Created Per Streaming Call (Medium)

**`OpenClawService.swift:38-41`** — A new `URLSession(configuration: config)` is created every call to `sendMessageStreaming`, and is never invalidated. Each call leaks a session (and its internal connection pool/delegate queue).

**Fix:** Create the URLSession once in `init()` and reuse it, or call `session.finishTasksAndInvalidate()` after the stream completes.

### 4. Bug: Conversation History Not Synced With Persisted Messages (Medium)

`OpenClawService` is instantiated fresh on every `processAudio` call (`ChatViewModel.swift:243`), which means `conversationHistory` starts empty each time. The last 20 messages sent to the LLM will only include messages from the current session — not the actual conversation history.

**Fix:** Pass the existing `messages` array when building the API payload, or keep a single `OpenClawService` instance on the ViewModel.

### 5. Bug: Race Condition in Streaming Token Callback (Medium)

**`ChatViewModel.swift:287-317`** — `sendMessageStreaming` calls `onToken` from the URLSession byte stream, which spawns `Task { @MainActor in ... }` for each token. These `Task` blocks are not guaranteed to execute in order.

**Fix:** Use an `AsyncStream` or accumulate tokens in the service and deliver them on MainActor in a serial loop.

### 6. Bug: `finishQueue()` May Complete Prematurely (Medium)

**`AudioPlayer.swift:39-49`** — `finishQueue()` checks `!isPlaying && queue.isEmpty` at the moment it's called. But TTS chunks are enqueued asynchronously via `TTSChunkQueue`. If the last `ttsQueue.enqueue()` hasn't completed yet, it will see an empty queue and fire completion early.

**Fix:** Add an `isFinished` flag and defer completion to `audioPlayerDidFinishPlaying` only after both the flag is set and the queue is empty.

### 7. Code Duplication: `retryLastMessage` (Low-Medium)

**`ChatViewModel.swift:442-537`** — Duplicates ~90 lines from `processAudio` (the entire streaming + chunked TTS pipeline).

**Fix:** Extract into a shared method like `sendToAgent(transcript:settings:resumeListening:)`.

### 8. Thread Safety: AudioRecorder Meter Updates (Low)

**`AudioRecorder.swift:176-182`** — The level timer runs on a global dispatch queue and writes `audioLevel` (non-atomic), while the same property is read from `@MainActor` code.

**Fix:** Mark `AudioRecorder` as `@MainActor`, or make `audioLevel` access thread-safe.

### 9. `isConnected` Check Accepts 4xx (Low)

**`ChatView.swift:286`** — `(200...499)` minus 401/403 considers 404, 422, etc. as "connected". A 404 could mean the endpoint path is wrong. Consider also excluding 404.

### 10. UserDefaults for Chat History (Low)

**`ChatViewModel.swift:114-116`** — Long conversations will bloat UserDefaults, which is loaded entirely into memory at launch. Should eventually move to file-based storage.

### 11. Missing `Sendable` Conformance (Low)

Several closures cross isolation boundaries without `@Sendable`. Will produce warnings/errors under Swift 6 strict concurrency checking.

---

## Minor Suggestions

- **Force-unwrap on URL** (`OpenClawService.swift:16, 79`): `URL(string:)!` will crash on malformed input. Use `guard let` + throw.
- **Unused `Combine` imports** in `AudioRecorder.swift:3` and `ChatView.swift:2`.
- **`startSpeakingTimer()` access level** (`ChatViewModel.swift:395`): Should be `private` like `startLevelTimer()`.
- **WaveDots timer runs indefinitely** (`ChatView.swift:479`): `Timer.publish` never stops off-screen.
- **Echo detection** (`ChatViewModel.swift:439`): 40% word overlap is aggressive. Common words ("the", "a", "is") could trigger false echoes. Consider filtering stop words.

---

## Summary

| Category | Count |
|---|---|
| Security issues | 2 |
| Bugs | 4 |
| Code quality | 3 |
| Minor / style | 5 |

The app's core architecture is sound — the state machine, actor-based TTS queue, and chunked streaming pipeline show good iOS engineering. The main areas to address are: **Keychain for secrets**, **fixing the URLSession leak**, **syncing conversation history with the LLM**, and **deduplicating the retry logic**.

For a v1.1 personal project, this is solid work.
