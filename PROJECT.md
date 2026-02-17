# ClawTalk - Voice Chat for OpenClaw

## Overview
Native iOS app for realtime voice conversations with your OpenClaw agent.
Lightweight alternative to ElevenLabs Conversational AI - uses STT + OpenClaw API + TTS pipeline.

## Status: v1.1 ✅
Built v1.0 in ~2 hours (2026-02-17). Polished to v1.1 same night.

## Architecture
```
iPhone (ClawTalk App)
    |
    |-- [Mic] Record audio (+ VAD auto-detect)
    |       |
    |       v
    |   STT (gpt-4o-mini-transcribe)
    |       |
    |       v
    |   Text prompt
    |       |
    |       v
    |   POST /v1/chat/completions (OpenClaw, streaming SSE)
    |       |-- x-openclaw-session-key: agent:main:main
    |       |-- model: openclaw:main
    |       v
    |   Streaming text response (word by word)
    |       |
    |       v
    |   Chunked TTS (ElevenLabs, eleven_turbo_v2_5)
    |       |-- Voice: per-profile (default Botopus U7vsLCpbWl9Lt8M1Gjtk)
    |       |-- TTSChunkQueue actor (serialized, in-order)
    |       v
    |-- [Speaker] Play audio queue (skip/stop available)
```

## Features Completed

### v1.0 (2026-02-17) ✅
- [x] Push-to-talk voice chat
- [x] Hands-free VAD mode (auto-detect speech, silence to send)
- [x] OpenClaw API connection (configurable URL + token)
- [x] Session routing to main session (shared with Telegram)
- [x] Streaming text response (SSE, word-by-word)
- [x] STT: gpt-4o-mini-transcribe (half cost, better accuracy than whisper-1)
- [x] TTS: ElevenLabs eleven_turbo_v2_5
- [x] Whisper hallucination filter (Chinese spam, subtitle artifacts)
- [x] Chat history with auto-scroll
- [x] Skip button (integrated into mic button, orange forward icon)
- [x] Stop button (cancel any active operation)
- [x] Audio waveform visualization (red=recording, orange=speaking)
- [x] Settings screen (API keys, server URL, voice selection)
- [x] App icon (purple octopus in speech bubble)
- [x] Multi-profile support (per-profile: name/emoji/URL/token/voice)
- [x] Global API keys (OpenAI + ElevenLabs shared across profiles)
- [x] Per-profile chat history
- [x] Profile activation + switching (smooth transitions)
- [x] Echo cancellation (word overlap detection >40% = discard)
- [x] Force-send button (tap during recording to submit immediately)
- [x] Long press to copy messages
- [x] New Conversation button (with confirmation dialog)
- [x] Meta Ray-Ban Bluetooth support (HFP/A2DP mic+speaker routing)

### v1.1 (2026-02-17 night) ✅
- [x] **Chunked TTS serialization** - TTSChunkQueue actor ensures audio plays in correct order
- [x] **Audio session optimization** - prepareAudioSession() called once, not per-chunk
- [x] **Background audio playback** - continues playing when app minimized
- [x] **Auto-restart listening on foreground** - hands-free resumes when returning to app
- [x] **VAD silence timeout tuned** - 1.5s (industry standard sweet spot)
- [x] **Connection test fix** - HEAD request to /v1/chat/completions (fast, shows latency in ms)
- [x] **Auto-check connection** - tests on Settings open automatically
- [x] **Theme toggle fix** - stored property for @Observable + UIKit window.overrideUserInterfaceStyle
- [x] **NO_REPLY filter** - discards silent responses, removes empty message bubble
- [x] **Custom header** - replaced iOS toolbar (circle backgrounds) with custom HStack
- [x] **Empty state** - profile emoji + "Tap the mic to start talking"
- [x] **Date separators** - Today/Yesterday/weekday headers between messages
- [x] **Green dot indicator** - connection status next to profile name
- [x] **Modern wave dots** - sine wave animation with state colors + tinted bubble
- [x] **State colors** - green=listening, red=recording, purple=transcribing, blue=thinking, cyan=streaming, orange=speaking
- [x] **Instant scroll on state change** - no animation overshoot during transitions

### v2.0 (Planned)
- [ ] WebSocket protocol (replace REST chat completions)
  - True cross-channel context (see Telegram messages from ClawTalk)
  - No session busy/timeout conflicts
  - Real-time events from Gateway
- [ ] On-device STT (Apple Speech Recognition) - offline capable
- [ ] Background mic recording (VOIP entitlement - complex)

### v3.0 (Future)
- [ ] Vision mode (camera snap + send as image to OpenClaw)
- [ ] Widget (quick voice command from home screen)
- [ ] Apple Watch companion
- [ ] Shortcuts integration (Siri: "Talk to Botopus")

## Tech Stack

| Component | Choice | Cost |
|-----------|--------|------|
| **Language** | Swift (native iOS, SwiftUI) | - |
| **Min iOS** | 17.0 | - |
| **UI Pattern** | @Observable (Swift 6 compatible) | - |
| **STT** | gpt-4o-mini-transcribe | ~$0.003/min |
| **LLM** | OpenClaw API (SSE streaming) | Normal token usage |
| **TTS** | ElevenLabs eleven_turbo_v2_5 | ~$0.30/1000 chars |
| **Voice** | Per-profile (default: Botopus U7vsLCpbWl9Lt8M1Gjtk) | - |
| **VAD** | Audio level monitoring (-25dB threshold) | Free (on-device) |

## Project Structure
```
ClawTalk/
├── ClawTalk.xcodeproj
├── ClawTalk/
│   ├── App/
│   │   ├── ClawTalkApp.swift          # App entry, audio session, appearance
│   │   └── ContentView.swift          # Main UI router
│   ├── Views/
│   │   ├── ChatView.swift             # Conversation + custom header + controls
│   │   ├── ChatViewModel.swift        # State management + voice pipeline
│   │   ├── VoiceButton.swift          # Push-to-talk button
│   │   ├── WaveformView.swift         # Audio visualization
│   │   └── SettingsView.swift         # Config, profiles, connection test
│   ├── Services/
│   │   ├── AudioRecorder.swift        # Mic capture + VAD + Bluetooth
│   │   ├── AudioPlayer.swift          # TTS playback + queue mode
│   │   ├── WhisperService.swift       # STT API + hallucination filter
│   │   ├── OpenClawService.swift      # Chat completions (REST + SSE)
│   │   └── ElevenLabsService.swift    # TTS API + voice listing
│   ├── Models/
│   │   ├── Message.swift              # ChatMessage model (Codable)
│   │   └── Settings.swift             # AppSettings + BotProfile (@Observable)
│   └── Assets.xcassets/
│       └── AppIcon.appiconset/        # Purple octopus icon
├── PROJECT.md                          # This file
└── README.md                           # Public readme
```

## Key Implementation Details

### Chunked TTS Pipeline
- Text split on punctuation (`.!?,;:-\n`), first chunk min 5 chars, force at 120 chars
- `TTSChunkQueue` actor serializes ElevenLabs API calls (prevents out-of-order playback)
- `AudioPlayer` queue mode: `startQueue()` → `enqueue()` → `finishQueue()`
- Audio session prepared once before queue starts (no per-chunk setup glitches)

### VAD (Voice Activity Detection)
- Threshold: -25dB (best balance for normal speech)
- Silence timeout: 1.5s
- Min speech duration: 0.5s
- Echo prevention: 1.2s ignore period after TTS + word overlap detection (>40% = discard)
- Bluetooth mic: `preferBluetoothMic()` called before each recording start

### State Machine
```
idle → listening → recording → transcribing → thinking → streaming → speaking → idle
                                                                          ↓
                                                              (hands-free: → listening)
```

### Theme System
- Uses UIKit `window.overrideUserInterfaceStyle` (SwiftUI `preferredColorScheme(nil)` unreliable)
- Stored property with `didSet` sync to UserDefaults (not computed, for @Observable tracking)

### Connection Status
- Green/gray dot in header, auto-checked on app launch + profile switch
- HEAD request to `/v1/chat/completions` with 5s timeout
- Settings page: auto-check + manual test with latency display (ms)

### Silent Response Filter
- NO_REPLY and HEARTBEAT_OK responses auto-removed from chat
- Empty assistant message bubbles hidden during thinking state

## Known Limitations
- **Background mic** - iOS kills microphone in background (privacy). Auto-restarts on foreground return.
- **Session conflict** - When main session busy, ClawTalk may timeout (rare in normal use)
- **No cross-channel visibility** - ClawTalk messages not visible in Telegram (fix: v2 WebSocket)
- **Toolbar circles** - iOS 16+ forces circle backgrounds; worked around with custom header

## Known Bugs Fixed
- Chunked TTS out-of-order (concurrent API calls) → serialized with actor
- Audio session glitch between chunks → prepare once
- Theme not updating (Light→System stuck) → UIKit window override
- Test Connection 404 → HEAD request to correct endpoint
- Empty gray bubble during thinking → hide when content empty
- Status bubble "drop down" → instant scroll on state change
- NO_REPLY showing as message → filter + remove

## Tested Devices
- iPhone (Syam's) - confirmed working
- Meta Ray-Ban glasses - Bluetooth mic+speaker confirmed, works from different rooms

## Cost Estimate (per exchange)
- STT: ~$0.003/min (gpt-4o-mini-transcribe)
- LLM: Same as Telegram chat (varies by model)
- TTS: ~$0.015 per response (~50 chars avg)
- **Total: ~$0.02-0.04 per exchange**

## Git
- **Repo:** https://github.com/LowKey88/ClawTalk
- **Collaborator:** botopus-bot
- **Local clone:** /tmp/ClawTalk/

## Changelog
- 2026-02-17 (day): v1.0 - full voice loop, VAD, streaming, profiles, echo cancellation, app icon (~30 commits)
- 2026-02-17 (night): v1.1 - chunked TTS fix, background audio, theme fix, UI polish, wave dots (~15 commits, f5e9f59→ff69b31)

*Created: 2026-02-17*
*Last updated: 2026-02-18*
