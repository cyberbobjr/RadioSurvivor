*Français : [Configurer le fournisseur d'IA](../fr/08-fournisseur-ia.md)*

# AI provider configuration

The bridge talks to any provider compatible with the **OpenAI Chat Completions API**: it sends
`POST <OPENAI_BASE_URL>/chat/completions` with `Authorization: Bearer <OPENAI_KEY>`.

## The three settings

| Setting | Meaning |
|---|---|
| `OPENAI_KEY` | Your API key. |
| `OPENAI_BASE_URL` | API address **without** `/chat/completions`, for example `https://api.openai.com/v1`. |
| `OPENAI_MODEL` | Model name at that provider. |

All three are required, except with `--offline` (no AI at all, the voices echo you).

They are read from the **environment variables** of the same name, otherwise from a **`.env` file**: by default
`.env` next to `radio_bridge.py` (copy `.env.example`), or the file given by `--env PATH`. An environment variable wins
over the file. Format: one `NAME=value` per line, `#` for a comment, `export ` accepted.

```
OPENAI_KEY=<your key>
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_MODEL=<model name>
```

## Optional caps

Two more settings, read the same way (environment variable first, then the `.env` file), cap the cost of every AI
call. Leave them out to keep the defaults.

| Setting | Default | Accepted | Meaning |
|---|---|---|---|
| `LLM_MAX_TOKENS` | `16000` | whole number from 256 to 131072 | Token cap of every attempt (`max_tokens`, or `max_completion_tokens` on the retry), reasoning included. |
| `LLM_MAX_PROMPT_CHARS` | `128000` | whole number from 16000 to 2000000 | Characters of a whole prompt; beyond, the call is refused (`prompt_too_large`). |

A value that is not a whole number, or is out of bounds, is ignored: the bridge logs `Invalid LLM_...` and keeps the
default. The effective caps are shown at startup (`LLM caps: ...`). Too low a token cap empties the answers of a
model that reasons before answering; too low a prompt cap silences voices with a long history.

```
LLM_MAX_TOKENS=8000
LLM_MAX_PROMPT_CHARS=128000
```

## Choosing a provider

Any provider or local server exposing an OpenAI-compatible `/chat/completions` endpoint can be tried: OpenAI,
DeepSeek, OpenRouter, Mistral, or a local server such as Ollama or LM Studio. Take the exact base URL and model name
from your provider's documentation. A local server usually needs no key: put any non-empty value in `OPENAI_KEY`.

Tips:

- Some voices answer in a JSON structure (actions such as a map mark or a mission). The bridge asks for the JSON mode
  of the API and retries without it, or without `temperature` and with `max_completion_tokens` instead of
  `max_tokens`, if the provider refuses a parameter. Every attempt is capped at 16 000 tokens (`LLM_MAX_TOKENS`), and an answer emptied
  by that cap is not retried.
- A prompt longer than 128 000 characters (`LLM_MAX_PROMPT_CHARS`) is never sent: the bridge logs `prompt_too_large` and the voice answers
  with static.
  Small local models follow the format less reliably; their answers are then reduced to plain speech.
- One call must finish within **60 s** (all retries included). A slow model or an overloaded provider gives
  "Only static..." and `bridge error timeout`.
- Check your setup with `python radio_bridge.py --test "Hello?"` before playing.

## Cost and quotas

- Every radio message accepted by the server is **one AI call** (up to two or three when the provider refuses a
  parameter or returns an empty answer). Spontaneous calls of the voices, the evening bulletin, the last pages, NPC
  dialogues and NPC initiatives are calls too.
- In-game limits: the sandbox option **`MaxPerHour`** (60 by default, all players together; `0` = unlimited, avoid
  on a public server), `PlayerCooldown` (10 s), at most 8 pending radio requests, an optional `budget=` per voice in
  its sheet, and fixed caps of 60 NPC dialogues and 12 biographies per real hour. See [Sandbox options](09-sandbox-options.md).
- Usage is appended to `<exchange folder>/token_usage.jsonl` (or `--usage-log PATH`): UTC date, model, input, output
  and total tokens, session totals. A missing counter is `null`. The bridge estimates no price: multiply by your
  provider's rates.
- **Set a monthly spending limit at your provider.** It is the only limit that holds even if an option is set wrong.

## Keep the key secret

- Never paste the `.env` file, the key or a `--debug` log in a comment, a ticket or on Discord. The bridge banner only
  shows `API key: configured (hidden)`.
- On a server, keep the file outside the bridge, game and exchange folders, readable by the bridge account only.
- If the key leaks, revoke it at the provider and create a new one.
