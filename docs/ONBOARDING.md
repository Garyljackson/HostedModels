# Pilot Onboarding — LLM Gateway

How to point your coding tool at the company LLM gateway. **5 minutes.**

> PoC stage (Australia East) — the model available now is **`gpt-5.4`** (Azure
> OpenAI `gpt-5.4`). Open-weight (Qwen) and Claude / Claude Code aren't available
> in Australia yet — see `docs/PRD.md` for the regional-availability details.

## 1. What you need from the platform admin

| Item | Example |
|------|---------|
| **Gateway URL** | `https://<gateway-host>` |
| **Your virtual key** | `sk-...` (personal — do not share; has your budget attached) |
| **Model name** | `gpt-5.4` |

The OpenAI-compatible base URL is the gateway URL **plus `/v1`**:
`https://<gateway-host>/v1`.

## 2. Configure your tool

Pick your tool. All of these route 100% through the gateway (in-tenant).

### Continue.dev (VS Code / JetBrains)

Add to your Continue `config.yaml` (`~/.continue/config.yaml`):

```yaml
models:
  - name: Gateway GPT
    provider: openai
    model: gpt-5.4
    apiBase: https://<gateway-host>/v1
    apiKey: <your-virtual-key>
```

### Cline (VS Code extension)

Settings → API Configuration:
- **API Provider:** `OpenAI Compatible`
- **Base URL:** `https://<gateway-host>/v1`
- **API Key:** `<your-virtual-key>`
- **Model ID:** `gpt-5.4`

### OpenCode  (verified end-to-end against the gateway)

**Install** — use the official **npm** package. (The WinGet `SST.opencode`
package is community-maintained, uses a stale publisher name, and isn't in the
official docs — avoid it. `npm`, the install script, and GitHub Releases are the
first-party options.)
```powershell
npm install -g opencode-ai      # needs Node.js LTS; don't use admin PowerShell
```

**1. Store your virtual key as an env var** (keeps the secret out of the config file):
```powershell
setx GATEWAY_API_KEY "<your-virtual-key>"    # then open a NEW terminal
```
For the current session only: `$env:GATEWAY_API_KEY = "<your-virtual-key>"`.

**2. Create the config** — globally at `%USERPROFILE%\.config\opencode\opencode.json`
(applies to every project) or `opencode.json` in a project folder:
```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "gateway": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Company LLM Gateway",
      "options": {
        "baseURL": "https://<gateway-host>/v1",
        "apiKey": "{env:GATEWAY_API_KEY}"
      },
      "models": { "gpt-5.4": { "name": "GPT-5.4 (gateway)" } }
    }
  },
  "model": "gateway/gpt-5.4"
}
```

**3. Run** `opencode` in a code project. It defaults to `gateway/gpt-5.4`; switch
models with `Tab` or `/models`. On first run, **skip** the built-in Anthropic/OpenAI
sign-in — we authenticate to the gateway with the virtual key, not a vendor key.

> **401?** `GATEWAY_API_KEY` isn't set in the terminal running opencode — open a
> fresh one after `setx`. If your OpenCode version doesn't interpolate `{env:...}`,
> put the key directly in `options.apiKey` (and don't commit that file).

### Claude Code — later phase (not yet available)

When Claude is added, Claude Code will use (see `TDD.md` §6.1):
```bash
export ANTHROPIC_BASE_URL="https://<gateway-host>"
export ANTHROPIC_AUTH_TOKEN="<your-virtual-key>"
export ANTHROPIC_MODEL="claude-opus-4-8"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-fast"
```

## 3. Check it works

Send a prompt from your tool (streaming should feel immediate). Or curl:

```bash
curl https://<gateway-host>/v1/chat/completions \
  -H "Authorization: Bearer <your-virtual-key>" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-5.4","messages":[{"role":"user","content":"Say hi"}],"stream":true}'
```

## 4. See your usage & budget

You have a monthly budget. Check spend vs budget any time (ask the admin for the
`mycost` helper or the self-service URL). Metadata only is recorded — **your
prompts and code are not logged or retained.**

## 5. Ground rules

- **Use only blessed tools** (Continue, Cline, OpenCode, Aider, Goose, Zed) so all
  traffic stays in-tenant. **Avoid** Cursor / Windsurf / Copilot for company code
  during the pilot — they route some data through vendor clouds.
- Your virtual key is personal; don't share or commit it.
- Report issues + fill the **weekly survey** — your feedback is part of the go/no-go.

## 6. Getting help

- Setup problems / key issues → platform admin (`<contact>`).
- Feedback / bugs → `<channel or form>`.
