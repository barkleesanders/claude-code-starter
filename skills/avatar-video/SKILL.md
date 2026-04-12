---
name: avatar-video
user-invocable: true
description: Generates talking avatar videos by chaining image generation (nano-banana), voice synthesis (MiniMax Speech via fal.ai), and lip-sync animation (OmniHuman 1.5 or Infinite Talk via fal.ai). Use when asked to "create a talking avatar", "generate a video with speech", "make an avatar say something", "lip-sync", or any video generation task combining portrait + voice + animation.
---

# avatar-video

Full pipeline: **text script** → **portrait image** → **voice audio** → **lip-synced video**.

## /init - First-Time Setup

```bash
~/.claude/skills/avatar-video/scripts/setup.sh
```

This creates `~/.avatar-video/.env` with your `FAL_KEY`. Get one at https://fal.ai → Dashboard → API Keys.

nano-banana must also be installed (see `/nano-banana` skill).

## Quick Reference

### Full Pipeline (text → video)

```bash
# Premium quality (OmniHuman 1.5) — ~$3.68 for 30s
~/.claude/skills/avatar-video/scripts/generate-avatar.sh \
  "Hi, I'm your your app assistant. I'm here to help you navigate your VA disability claim." \
  --quality premium

# Budget quality (Infinite Talk) — ~$1.88 for 30s
~/.claude/skills/avatar-video/scripts/generate-avatar.sh \
  "Welcome to our service" \
  --quality budget
```

### Individual Steps

```bash
# 1. Generate portrait (uses nano-banana)
nano-banana "professional headshot of a woman, studio lighting, neutral background" -s 1K -o portrait

# 2. Generate voice (MiniMax Speech)
~/.claude/skills/avatar-video/scripts/minimax-tts.sh \
  "Hello, welcome to your app" \
  --voice Friendly_Person \
  --output speech.mp3

# 3a. Lip-sync with OmniHuman 1.5 (premium)
~/.claude/skills/avatar-video/scripts/omnihuman-lipsync.sh \
  --image portrait.png \
  --audio speech.mp3 \
  --output avatar-video.mp4

# 3b. Lip-sync with Infinite Talk (budget)
~/.claude/skills/avatar-video/scripts/infinitetalk-lipsync.sh \
  --image portrait.png \
  --audio speech.mp3 \
  --output avatar-video.mp4
```

## Orchestrator Options

| Flag | Default | Description |
|------|---------|-------------|
| `--quality` | `premium` | `premium` (OmniHuman) or `budget` (Infinite Talk) |
| `--engine` | auto | `omnihuman` or `infinitetalk` (overrides --quality) |
| `--voice` | `Friendly_Person` | MiniMax voice ID |
| `--voice-speed` | `1.0` | Speech speed (0.5-2.0) |
| `--image` | - | Skip image gen, use existing portrait |
| `--audio` | - | Skip voice gen, use existing audio |
| `--output` | `avatar-{timestamp}` | Output filename (no extension) |
| `--dir` | current directory | Output directory |
| `--image-prompt` | auto | Custom prompt for portrait generation |

## MiniMax Speech Voices

Built-in voices (pass to `--voice`):

| Voice ID | Description |
|----------|-------------|
| `Wise_Woman` | Mature, authoritative female |
| `Friendly_Person` | Warm, approachable (default) |
| `Deep_Voice_Man` | Deep, resonant male |
| `Calm_Woman` | Soothing, relaxed female |
| `Casual_Guy` | Informal, conversational male |
| `Lively_Girl` | Energetic, youthful female |

Custom voice cloning: provide a voice sample URL as `--voice <url_to_6sec_sample>`.

## Engine Comparison

| Feature | OmniHuman 1.5 | Infinite Talk |
|---------|---------------|---------------|
| **Cost** | $0.12/s (lip-sync) | $0.03/s (480p), $0.06/s (720p) |
| **30s video** | ~$3.60 | ~$0.90-$1.80 |
| **Max length** | 30s audio | 10 minutes |
| **Quality** | Best — full body motion, gestures | Good — solid lip-sync |
| **Resolution** | 720p/1080p | 480p/720p |
| **Best for** | Short premium content, ads | Long-form, bulk, prototyping |

## Full Pipeline Costs (30-second video)

| Step | Tool | Cost |
|------|------|------|
| Image | nano-banana (Gemini Flash) | ~$0.05 |
| Voice | MiniMax Speech 2.6 Turbo | ~$0.03 |
| Lip-sync (budget) | Infinite Talk 720p | ~$1.80 |
| Lip-sync (premium) | OmniHuman 1.5 | ~$3.60 |
| **Total (budget)** | | **~$1.88** |
| **Total (premium)** | | **~$3.68** |

## Cost Tracking

Every generation logs to `~/.avatar-video/costs.json`. View summary:

```bash
~/.claude/skills/avatar-video/scripts/generate-avatar.sh --costs
```

## API Keys

| Service | Key | Source |
|---------|-----|--------|
| MiniMax Speech, OmniHuman, Infinite Talk | `FAL_KEY` | `~/.avatar-video/.env` |
| nano-banana (image gen) | `GEMINI_API_KEY` | `~/.nano-banana/.env` |

All fal.ai services use a single key. Get one at https://fal.ai.

## Troubleshooting

- **"FAL_KEY not found"** — Run setup: `~/.claude/skills/avatar-video/scripts/setup.sh`
- **"Audio must be under 30s"** (OmniHuman) — Use Infinite Talk for longer audio, or trim script
- **Upload failed** — Check FAL_KEY is valid; fal.ai file upload requires auth
- **Queue timeout** — OmniHuman can take 2-5 min; the script polls automatically
- **nano-banana not found** — Install via `/nano-banana` skill init
