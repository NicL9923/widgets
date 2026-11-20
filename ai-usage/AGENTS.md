# AI Usage

A KDE Plasma 6 panel widget and macOS menu bar app that show live Claude Code, Codex, and Grok
subscription usage. Shared rules live in the root `AGENTS.md`.

## Layout

- `src/ai_usage/` — the helper. `probes.py` shells out to the CLIs, `parsers.py` normalizes
  their output, `cache.py` applies the TTL, `cli.py` prints the JSON contract.
- `tests/` — pytest suites for the parsers and the cache, with fixtures captured from real
  CLI output in `tests/fixtures/`.
- `plasmoid/` — the Plasma applet package. `contents/ui/main.qml` owns polling and state;
  the representations and the config page live alongside it. `contents/icons/` holds the
  provider marks (Simple Icons and SVG Logos, both CC0) drawn inside the rings.
- `scripts/install.sh` copies the helper into `~/.local/share/ai-usage-widget` with a
  `~/.local/bin/ai-usage` launcher, and installs the applet via
  `kpackagetool6`.

## How Usage Is Read

Every probe is free — no tokens, no model calls:

- **Codex**: `codex app-server`, then the JSON-RPC method `account/rateLimits/read`.
- **Claude**: `claude --print /usage --output-format json`, with MCP disabled and stdin
  closed.
- **Grok**: `grok agent --no-leader stdio`, then the ACP extension method `_x.ai/billing`.
  The leading underscore is required — it is the protocol's namespace for unstable
  methods, and `x.ai/billing` alone answers "Method not found". `--no-leader` keeps the
  probe out of the shared leader process the interactive CLI attaches to, so polling can
  never disturb a running session.

Going through the vendor CLIs is a deliberate choice. The alternative — calling
`chatgpt.com/backend-api/wham/usage`, `api.anthropic.com/api/oauth/usage`, and
`cli-chat-proxy.grok.com/v1/billing` directly — means storing, reading, and refreshing
OAuth tokens ourselves against undocumented endpoints. Shelling out keeps auth entirely
inside the vendors' own tools. Do not "simplify" this by reading credential files.

## Implementation Standards

- **Parsers fail closed.** Claude has no structured usage output, so `parse_claude_usage`
  scrapes prose. Unrecognized or changed output must yield no windows, never a guessed
  number. A missing bar is recoverable; a wrong bar is not. The same applies to Codex and
  Grok. A window the provider reported but we cannot parse fails the whole reading; never
  return the remaining windows, because a dropped window reads as "no limit".
- **Absent is not zero.** Grok omits `creditUsagePercent` until a period has usage on it,
  and Grok's own TUI renders that omission as a confident "0%". We report no window and
  let the provider read as unavailable instead. Never substitute a default for a reading
  that did not arrive, and never derive a percentage from elapsed time in the window:
  Grok's pool is compute-weighted, so wall-clock tells you nothing about consumption.
- **Every probe path cleans up after itself.** `claude --print` writes a session transcript
  under `~/.claude/projects/<slugified-cwd>/` on every invocation. The probe runs in a
  throwaway cwd and removes only directories that did not exist before it ran.
- **One provider failing never blocks the other.** Probes run concurrently and each failure
  is captured into a `ProviderUsage` with an `error`, not raised.
- **Distinguish "cached" from "stale".** A cache hit inside the TTL is current data. Only a
  reading that was retried and failed to refresh gets the stale marker.
- Read every bucket in the Codex `rateLimitsByLimitId` map, not just the default one.
  Model-specific limits (e.g. GPT-5.3-Codex-Spark) only appear there, and hiding them
  understates how close an account is to being cut off.
- Add a happy-path and an edge-case test for new pure functions. The year-boundary cases in
  `tests/test_parsers.py` are the template for anything that infers missing data.

## Build and verify

- Helper smoke test, from `ai-usage/`: `PYTHONPATH=src python3 -m ai_usage --refresh --plain`.
- Install locally: `./scripts/install.sh`, then `systemctl --user restart plasma-plasmashell.service`.
- `.agents/tools/plasma-visual-harness.sh` renders the applet from a JSON fixture.

## Out of scope

- Credit balances and spend controls. The contract carries percentages only, so Grok's
  `prepaidBalance` and the absolute value of its on-demand cap are dropped; only the
  used/cap ratio survives. Representing balances needs a currency-denominated shape.
- Interactive PTY/TUI scraping. Driving a vendor's TUI through a pty is a legitimate way
  to *verify* a reading by hand — that is how `creditUsagePercent` was confirmed to be a
  0-100 scale — but it must never become how the widget reads one.
