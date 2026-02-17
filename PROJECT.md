# ClawTalk - Voice Chat for OpenClaw

## Overview
Native iOS app for realtime voice conversations with your OpenClaw agent.
Lightweight alternative to ElevenLabs Conversational AI - uses STT + OpenClaw API + TTS pipeline.

## Architecture
```
iPhone (ClawTalk App)
    |
    |-- [Mic] Record audio
    |       |
    |       v
    |   STT (Whisper API / on-device)
    |       |
    |       v
    |   Text prompt
    |       |
    |       v
    |   POST /v1/chat/completions (OpenClaw)
    |       |
    |       v
    |   Text response
    |       |
    |       v
    |   TTS (ElevenLabs API)
    |       |
    |       v
    |-- [Speaker] Play audio
```

## Two Modes

### Mode 1: Semi-realtime (Push-to-talk)
- Hold button to talk, release to send
- Walkie-talkie style
- Visual waveform while recording
- Simple, reliable

### Mode 2: Realtime (Hands-free)
- Voice Activity Detection (VAD) - auto detect speech
- Auto listen after response finishes
- Continuous conversation like phone call
- Toggle on/off

## Tech Stack

| Component | Choice | Cost |
|-----------|--------|------|
| **Language** | Swift (native iOS) | - |
| **Min iOS** | 17.0 | - |
| **STT** | OpenAI Whisper API | ~$0.006/min |
| **LLM** | OpenClaw API (chat completions) | Normal token usage |
| **TTS** | ElevenLabs API (text-to-speech) | ~$0.30/1000 chars |
| **VAD** | Apple Speech framework / WebRTC VAD | Free (on-device) |

## Features

### MVP (v1.0)
- [ ] Push-to-talk voice chat
- [ ] OpenClaw API connection (configurable URL + token)
- [ ] Whisper STT (API)
- [ ] ElevenLabs TTS (API)
- [ ] Chat history (text view of conversation)
- [ ] Audio waveform visualization
- [ ] Settings screen (API keys, server URL, voice selection)

### v1.1
- [ ] Hands-free mode (VAD)
- [ ] On-device STT (Apple Speech Recognition) - offline capable
- [ ] Conversation context (maintain chat history)
- [ ] Background audio (keep listening while app backgrounded)

### v1.2 (Optional)
- [ ] Vision mode (camera snap + send as image to OpenClaw)
- [ ] Widget (quick voice command from home screen)
- [ ] Apple Watch companion
- [ ] Shortcuts integration (Siri: "Talk to Botopus")

## Project Structure
```
ClawTalk/
├── ClawTalk.xcodeproj
├── ClawTalk/
│   ├── App/
│   │   ├── ClawTalkApp.swift          # App entry
│   │   └── ContentView.swift          # Main UI
│   ├── Views/
│   │   ├── ChatView.swift             # Conversation view
│   │   ├── VoiceButton.swift          # Push-to-talk button
│   │   ├── WaveformView.swift         # Audio visualization
│   │   └── SettingsView.swift         # Config screen
│   ├── Services/
│   │   ├── AudioRecorder.swift        # Mic capture
│   │   ├── AudioPlayer.swift          # Playback
│   │   ├── WhisperService.swift       # STT API
│   │   ├── OpenClawService.swift      # Chat completions API
│   │   ├── ElevenLabsService.swift    # TTS API
│   │   └── VADService.swift           # Voice activity detection
│   ├── Models/
│   │   ├── Message.swift              # Chat message model
│   │   └── Settings.swift             # App settings model
│   └── Resources/
│       └── Assets.xcassets
└── README.md
```

## API Endpoints Used

### 1. Whisper STT
```
POST https://api.openai.com/v1/audio/transcriptions
Content-Type: multipart/form-data
Authorization: Bearer <OPENAI_API_KEY>
Body: file (audio), model: "whisper-1"
Response: { "text": "transcribed text" }
```

### 2. OpenClaw Chat Completions
```
POST https://<openclaw-url>/v1/chat/completions
Authorization: Bearer <GATEWAY_TOKEN>
Content-Type: application/json
Body: { "model": "auto", "messages": [...] }
Response: { "choices": [{ "message": { "content": "response" } }] }
```

### 3. ElevenLabs TTS
```
POST https://api.elevenlabs.io/v1/text-to-speech/<VOICE_ID>
xi-api-key: <ELEVENLABS_API_KEY>
Content-Type: application/json
Body: { "text": "response text", "model_id": "eleven_multilingual_v2" }
Response: audio/mpeg (stream)
```

## Settings (User Configurable)
- OpenClaw URL (e.g. https://openclaw.hostname.gbnet.cloud)
- OpenClaw Gateway Token
- OpenAI API Key (for Whisper)
- ElevenLabs API Key
- Voice Selection (auto-fetch from ElevenLabs API, picker with preview)
- Mode: Push-to-talk / Hands-free

## UX Flow

### Push-to-talk
1. Open app → see chat history
2. Hold mic button → recording starts, waveform shows
3. Release → "Thinking..." indicator
4. STT transcribes → text appears in chat
5. OpenClaw processes → response text appears
6. TTS plays audio → speaker icon animates
7. Ready for next input

### Hands-free
1. Toggle hands-free mode ON
2. App listens continuously
3. VAD detects speech → starts recording
4. Silence detected → auto sends
5. Same flow as above
6. After TTS finishes → auto listen again

## Cost Estimate (per conversation)
- STT: ~$0.006/min of speech
- LLM: Same as Telegram chat (varies by model)
- TTS: ~$0.30/1000 chars (~$0.015 per response)
- **Total: ~$0.02-0.05 per exchange** (way cheaper than ElevenLabs agent)

## For OpenClaw VPS Customers
ClawTalk works with any OpenClaw VPS:
1. Install ClawTalk from App Store (future)
2. Enter OpenClaw URL + token (from `setup-api`)
3. Enter own OpenAI + ElevenLabs keys
4. Start talking!

## Timeline
- **Week 1:** MVP - push-to-talk, STT, chat completions, TTS
- **Week 2:** Polish UI, hands-free mode, settings
- **Week 3:** Testing, vision mode (optional), beta

*Created: 2026-02-17*
