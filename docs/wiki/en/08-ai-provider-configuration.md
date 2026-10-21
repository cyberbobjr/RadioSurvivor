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

## Choosing a provider

Any provider or local server exposing an OpenAI-compatible `/chat/completions` endpoint can be tried: OpenAI,
DeepSeek, OpenRouter, Mistral, or a local server such as Ollama or LM Studio. Take the exact base URL and model name
from your provider's documentation. A local server usually needs no key: put any non-empty value in `OPENAI_KEY`.

Tips:

- Some voices answer in a JSON structure (actions such as a map mark or a mission). The bridge asks for the JSON mode
  of the API and retries without it, or without `temperature`/`max_tokens`, if the provider refuses a parameter.
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
