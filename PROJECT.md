# ClawTalk - Voice Chat for OpenClaw

## Overview
Native iOS app for realtime voice conversations with your OpenClaw agent.
Lightweight alternative to ElevenLabs Conversational AI - uses STT + OpenClaw API + TTS pipeline.

## Status: v1.0 COMPLETE ✅
Built and deployed to iPhone in ~2 hours (2026-02-17).

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
    |   TTS (ElevenLabs, eleven_turbo_v2_5)
    |       |-- Voice: Botopus (U7vsLCpbWl9Lt8M1Gjtk)
    |       v
    |-- [Speaker] Play audio (skip button available)
```

## Features Completed

### v1.0 (2026-02-17) ✅
- [x] Push-to-talk voice chat
- [x] Hands-free VAD mode (auto-detect speech, 1.5s silence to send)
- [x] OpenClaw API connection (configurable URL + token)
- [x] Session routing to main session (shared with Telegram)
- [x] Streaming text response (SSE, word-by-word like ChatGPT)
- [x] STT: gpt-4o-mini-transcribe (half cost, better accuracy than whisper-1)
- [x] TTS: ElevenLabs eleven_turbo_v2_5 with Botopus voice
- [x] Whisper hallucination filter (Chinese spam, subtitle artifacts)
- [x] Manglish prompt hint (no auto-translation)
- [x] Chat history with auto-scroll (follows streaming)
- [x] Skip button to cancel TTS playback
- [x] Audio waveform visualization
- [x] Settings screen (API keys, server URL, voice selection)
- [x] App icon (purple octopus in speech bubble)

### v2.0 (Planned)
- [ ] WebSocket protocol (replace REST chat completions)
  - True cross-channel context (see Telegram messages from ClawTalk)
  - No session busy/timeout conflicts
  - Real-time events from Gateway
- [ ] On-device STT (Apple Speech Recognition) - offline capable
- [ ] Background audio (keep listening while app backgrounded)

### v3.0 (Future)
- [ ] Vision mode (camera snap + send as image to OpenClaw)
- [ ] **Meta Ray-Ban Smart Glasses Integration** - "Show Botopus this" camera capture
  - SDK: Meta Wearables Device Access Toolkit (developer preview)
  - Features: Photo/video capture, voice trigger, hands-free AI analysis
  - Flow: "Hey Meta, show Botopus this" → glasses capture → AI analyze → voice reply
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
| **Voice** | Botopus (U7vsLCpbWl9Lt8M1Gjtk) | - |
| **VAD** | OpenAI Realtime server VAD + local level metering | Included in STT |

## Project Structure
```
ClawTalk/
├── ClawTalk.xcodeproj
├── ClawTalk/
│   ├── App/
│   │   ├── ClawTalkApp.swift          # App entry
│   │   └── ContentView.swift          # Main UI router
│   ├── Views/
│   │   ├── ChatView.swift             # Conversation + controls
│   │   ├── ChatViewModel.swift        # State management + pipeline
│   │   ├── VoiceButton.swift          # Push-to-talk button
│   │   ├── WaveformView.swift         # Audio visualization
│   │   └── SettingsView.swift         # Config screen
│   ├── Services/
│   │   ├── AudioRecorder.swift        # Mic capture + realtime PCM chunking
│   │   ├── AudioPlayer.swift          # TTS playback
│   │   ├── WhisperService.swift       # Transcription utilities + hallucination filter
│   │   ├── OpenClawService.swift      # Chat completions (REST + SSE)
│   │   └── ElevenLabsService.swift    # TTS API
│   ├── Models/
│   │   ├── Message.swift              # Chat message model
│   │   └── Settings.swift             # App settings (@Observable)
│   └── Assets.xcassets/
│       └── AppIcon.appiconset/        # Purple octopus icon
└── README.md
```

## API Configuration
- **Server:** https://botopus-api.gbhome.my
- **Session Key:** agent:main:main (shared with Telegram)
- **Model:** openclaw:main
- **Streaming:** SSE (stream: true)

## VAD Settings
- Server VAD: threshold 0.5
- Prefix padding: 300ms
- Silence duration: 600ms
- Auto-resume listening after TTS playback

## Known Limitations
- **Session conflict:** When main session is busy (e.g., generating images), ClawTalk may timeout. Rare in normal use.
- **No cross-channel visibility:** ClawTalk messages not visible in Telegram and vice versa (fix: v2 WebSocket)
- **STT accuracy:** gpt-4o-mini-transcribe occasionally misheard words (e.g., "GB" -> "TV"), but LLM compensates with context
- **Whisper hallucination:** Filtered but not 100% - silence/noise can occasionally trigger false transcription

## Cost Estimate (per exchange)
- STT: ~$0.003/min (gpt-4o-mini-transcribe, half of whisper-1)
- LLM: Same as Telegram chat (varies by model)
- TTS: ~$0.015 per response (~50 chars avg)
- **Total: ~$0.02-0.04 per exchange**

## Git
- **Repo:** https://github.com/LowKey88/ClawTalk
- **Collaborator:** botopus-bot
- **Local clone:** /tmp/ClawTalk/

## Changelog
- 2026-02-18: Theme system fixes, smart echo detection, .gitignore, Meta Ray-Ban integration planned
- 2026-02-17: v1.0 complete - full voice loop, VAD, streaming, app icon
  - Commits: voice fix, session routing, VAD, hallucination filter, STT upgrade, streaming, skip button, auto-scroll, app icon

*Created: 2026-02-17*
*Last updated: 2026-02-18*
