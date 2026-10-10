# Setup (one time, on your own computer)

Everything Studio-related has to run where Roblox Studio runs, i.e. your PC/Mac.

## 1. Claude Code + this repo
1. Install the Claude desktop app (Claude Code needs a Pro plan or higher).
2. `git clone https://github.com/anjohn878-bit/rblx` and open the folder in Claude Code.
   The skills in `.claude/skills/` load automatically.

## 2. Roblox toolchain

**Quick way:** from the repo folder run
`powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1` (Windows) or
`bash scripts/setup-mac.sh` (Mac). It does all of the steps below and runs the checks.

Manual way:
1. Install [Rokit](https://github.com/rojo-rbx/rokit), then in the repo run `rokit install`
   (installs the pinned Rojo, Selene, StyLua and Lune versions).
2. Install the Rojo Studio plugin: `rojo plugin install`.
3. Python 3.11+: `pip install pytest pillow kaggle`.
4. Blender 4.2+ (add it to PATH), or `pip install bpy` with a matching Python version.
5. Check: `scripts/check.sh` (Mac/Linux/Git Bash) or
   `powershell -ExecutionPolicy Bypass -File scripts\check.ps1` (Windows) should print `ALL CHECKS PASSED`.

## 3. Connect Roblox Studio (MCP)
1. Studio → Assistant → `⋯` → **Manage MCP servers** → enable **Studio MCP server**.
2. Choose **Claude Code CLI** and copy the command shown.
3. In Claude Code: "I have an MCP running, use this to connect:" + paste the command.
4. Open a place, run `rojo serve` in the repo and click Connect in the Rojo plugin.

## 4. API keys — set them yourself, never paste them into chat
Set these as environment variables in **your own terminal**, not in the chat.

| Variable | Where to get it |
| --- | --- |
| `ROBLOX_API_KEY` | create.roblox.com → Creator Hub → All tools → Open Cloud → API keys. Grant **Assets API: read + write**. Restrict it to your IP if you can. |
| `ROBLOX_USER_ID` | The number in your Roblox profile URL (use `ROBLOX_GROUP_ID` for a group game instead). |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare dashboard → Workers AI (free tier). |
| `CLOUDFLARE_API_TOKEN` | My Profile → API Tokens → create one with the **Workers AI** permission. |
| Kaggle | kaggle.com → Settings → API → *Create New Token* → put `kaggle.json` in `~/.kaggle/`. Phone-verify the account so notebooks can use the GPU and internet. |

Windows (PowerShell, once each, then restart Claude Code):
```powershell
setx ROBLOX_API_KEY "..."
```
macOS/Linux: add `export ROBLOX_API_KEY="..."` to `~/.zshrc` / `~/.bashrc`.

## 5. Smoke test (ask Claude)
"Run the preflight from create-roblox-game and tell me what's missing."
