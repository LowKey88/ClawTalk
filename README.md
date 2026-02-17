# 🐙 ClawTalk

Voice conversations with [OpenClaw](https://openclaw.ai) agents.

Talk to your AI agent in realtime using voice — lightweight alternative to full conversational AI platforms.

## How It Works

```
Mic → STT → OpenClaw API (streaming) → TTS → Speaker
```

- **Push-to-talk** or **hands-free** (VAD) mode
- Streaming text response (word-by-word, like ChatGPT)
- Conversation history with auto-scrolling bubbles
- Skip button to cancel TTS playback
- Voice selection from ElevenLabs library
- Whisper hallucination filter
- Works with any OpenClaw instance

## Screenshots

*Coming soon*

## Requirements

- iPhone (iOS 17.0+)
- Xcode 15.0+
- OpenClaw server with API enabled (`setup-api`)
- OpenAI API key (for Whisper STT)
- ElevenLabs API key (for TTS)

## Setup

1. Clone this repo
2. Open `ClawTalk.xcodeproj` in Xcode
3. Build & run on iPhone
4. Enter your OpenClaw URL + token in Settings
5. Add API keys
6. Pick a voice
7. Start talking! 🎤

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift (SwiftUI, iOS 17+) |
| STT | gpt-4o-mini-transcribe |
| LLM | OpenClaw API (SSE streaming) |
| TTS | ElevenLabs (eleven_turbo_v2_5) |
| VAD | On-device audio level monitoring |

## Cost

~$0.02-0.04 per exchange — same as texting your agent, plus tiny STT/TTS fees.

## License

MIT

---

<p align="center">
  Powered by <a href="https://www.gbnetwork.my"><strong>GB Network Solutions</strong></a><br>
  Deploy your own AI agent with <a href="https://www.gbnetwork.my/ai/openclaw-vps/">OpenClaw VPS</a>
</p>
