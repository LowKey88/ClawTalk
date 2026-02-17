# 🐙 ClawTalk

Voice chat for [OpenClaw](https://openclaw.ai) agents.

Talk to your AI agent in realtime using voice — lightweight alternative to full conversational AI platforms.

## How It Works

```
Mic → Whisper STT → OpenClaw API → ElevenLabs TTS → Speaker
```

- **Push-to-talk** or **hands-free** mode
- Conversation history with chat bubbles
- Voice selection from ElevenLabs library
- Works with any OpenClaw VPS instance

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

## Cost

~$0.02-0.05 per exchange — same as texting your agent, plus tiny STT/TTS fees.

## License

MIT
