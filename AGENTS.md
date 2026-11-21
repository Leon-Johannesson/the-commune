# AGENTS.md — The Commune

Shared instructions for every AI coding agent working in this repo (ChatGPT/Codex, Claude Code, Cursor, etc.).
This file is the single source of truth. `CLAUDE.md` only imports it. Edit rules **here**, not in tool-specific files.

## Project

The Commune is a World of Warcraft addon for the **WoW: Forever** private client (`## Interface: 16001`).
It is a guild toolkit: item request board, guild crafts catalog, projects, PvP hitlist, Social Credits, and daily games (quiz, Wordle-style word game, aim trainer).

- Plain Lua 5.1 (WoW's embedded runtime) + the WoW client API. **No external libraries** (no Ace3, LibStub, etc.) and no build step.
- All addon code lives in `TheCommune/`. Install = copy that folder to `_forever_/Interface/AddOns/`, then `/reload` in game.
- In-game entry point: `/commune` (aliases `/thecommune`). Subcommands: `sync`, `debug`, `craftsdebug`, `summary`, `resize` (see `UI.lua`).

## Layout

| Path | Purpose |
|---|---|
| `TheCommune/TheCommune.toc` | Addon manifest. **Load order = the file list.** New `.lua` files must be added here in the right place. |
| `Core.lua` | Namespace (`TC`), helpers (`TC.Clean`, `TC.Integer`, `TC.NormalizeName`, `TC.DisplayName`), DB init, login/guild events. |
| `Sync.lua` | Guild addon-message transport (prefix `TheCommune1`, channel `GUILD`), send queue/throttle, request packets, `/commune debug`. |
| `GuildStorage.lua` | Per-guild storage keys and empty-realm migration/merge. |
| `GuildData.lua`, `GuildPages.lua`, `RecipeSearch.lua`, `CraftRequirements.lua` | Profession scans, crafts catalog, projects. |
| `Social.lua`, `SocialUI.lua`, `SocialExtras.lua`, `SocialLayout.lua`, `CreditSafety.lua` | Social Credits, wallets, daily games, shop, credit receipts/repair. |
| `HitSync.lua`, `HitlistPage.lua`, `HitAlert.lua`, `DeathPrompt.lua`, `PvP.lua`, `Deaths.lua` | Hitlist, nearby-enemy alert, death-recap prompt, honor/death stats. |
| `UI.lua`, `Theme.lua`, `Resize.lua`, `WindowPositions.lua`, `Summary.lua` | Main window, styling, resize, saved positions, login summary. |
| `QuizData.lua` (+ `QUIZ-SOURCES.txt`), `WordDictionary.lua` (+ `WORDLIST-LICENSE.txt`) | Static game data. |
| `TheCommune/README.md` | User guide **and version history** (newest version first). |

## Code conventions

- Every file starts with `local addonName, TC = ...` (or `local _, TC = ...`). Shared functions go on `TC` (`function TC.Foo()`); keep everything else `local`. **Never create new globals.** Only `TheCommune` (namespace), `TheCommuneDB` (SavedVariables) and the `SLASH_THECOMMUNE*` entries are global.
- Cross-module calls that might not be loaded yet are guarded: `if TC.Refresh then TC.Refresh() end`. Keep doing this.
- 4-space indentation. Match the surrounding style of the file you are editing. Some files are deliberately compact (`a=b` with no spaces, several statements per line). Don't reformat code you aren't changing; whitespace-only diffs make reviews and merges between collaborators painful.
- Comments explain *why* (client quirks, compatibility), not what.
- Lua 5.1 only: no `goto`, no integer division `//`, no `utf8` library, no bitwise operators.
- Wrap client APIs that may be missing or error on this client in `pcall` / existence checks (see `Safe(...)` helpers and `C_ChatInfo` checks in `Sync.lua`).
- Respect secret values: check `issecretvalue` before reading unit/combat data that may be restricted.
- Never call protected actions (targeting, secure frames, frame changes on secure templates) in combat. Check `InCombatLockdown()` first.

## Data and sync rules (most important — breaking these corrupts guild data)

1. **SavedVariables (`TheCommuneDB`) are user data.** Every schema change must be backward compatible with existing saves. Add fields with defaults (`x = x or {}`); never assume a field exists. Migrations must be idempotent: running them twice must not double-count anything, especially credits. Keep a recovery copy before destructive migration (see `TC.db.guildRecovery`).
2. **Wire protocol compatibility.** Guildmates run mixed versions. Packets are tab-separated, **max 254 bytes**, validated field-by-field on receipt (`TC.Decode`, `TC.Integer`, `TC.Clean`). Don't change the meaning of existing packet kinds (`R`, `D`, `Q`, `C*`, `PX`, `PH`, `PK`, `HL`, `HD`, `F*` …). Add a new kind or optional trailing field instead, and keep sending the legacy form when older clients need it (see `TC.Encode(..., legacy)`).
3. **Conflict resolution is revision-based.** The higher `revision` wins; on equal revisions a deletion (tombstone) wins. Never hard-delete synced records; mark them `deleted = true` with a bumped revision (`math.max(time(), old + 1)`).
4. **Untrusted input.** Everything from other players (addon messages, names, notes) is untrusted. Sanitize it with `TC.Clean(text, limit)`, which strips UI escape codes and truncates UTF-8 safely, and check permissions against the guild roster (guild master/officer). Never trust a sender's claim about its own rank.
5. **Names.** Always pass player names through `TC.NormalizeName`. This client sends `CAMWOW…` physical-realm suffixes and space-separated names. Use `TC.DisplayName` for display. Do not use byte-wise `string.lower` on names; it corrupts UTF-8. Use `TC.PlayerKey`.
6. **Credits are money-like.** Social Credit changes go through the existing wallet/receipt paths in `Social.lua` / `CreditSafety.lua`. Guild-master-only actions must stay guild-master-only.
7. Respect the send throttle in `Sync.lua`. Don't add direct `SendAddonMessage` calls; use `TC.QueueGuildPacket(key, message)`.

## Testing and verification

- There is no Lua toolchain or test suite in the repo yet. At minimum, make sure changed files are valid Lua 5.1 syntax (`luac -p file.lua` if Lua 5.1 is available).
- Real verification happens in game: copy the folder, `/reload`, check for Lua errors (enable `/console scriptErrors 1`), and use `/commune debug` for sync, credit and hitlist state.
- Sync changes need two clients or guildmates on different versions. Say clearly in your summary/PR what you could **not** verify in game.
- Never invent test results. If something wasn't run, say so.

## Releasing a version

When a change is user-visible, bump the version in **all three places** in the same commit:
1. `TheCommune/Core.lua` → `TC.version = "x.y.z"`
2. `TheCommune/TheCommune.toc` → `## Version: x.y.z`
3. `TheCommune/README.md` → the `# The Commune — x.y.z` title, plus a new `## <summary> (x.y.z)` section at the **top** of the version history describing what changed and why, in the same plain-prose style as existing entries.

Use patch bumps (0.4.16 → 0.4.17) unless the team agrees otherwise.

After each addon update, package the verified version as `TheCommune-<version>.zip` with `TheCommune/` at the archive root. Upload that exact ZIP to the [Versions thread under #commune-addon](https://discord.com/channels/1573065951283515482/1573664576703045703) with the version and a one-line summary of what changed. The project owner authorizes this release post. Use the existing thread and post once per release. Changes to repository instructions alone do not trigger an upload.

On the owner's Windows workstation, run `pwsh -File scripts/Post-Version.ps1 -ZipPath <path-to-zip> -Summary "Brief description of the change"` from the repository. It uses the Windows-encrypted webhook stored at `.local/discord-webhook.dpapi`, which is ignored by Git. Keep the raw URL out of files, commits, logs, and chat. Other machines need their own authorized local credential: run `powershell -ExecutionPolicy Bypass -File scripts\Set-DiscordWebhook.ps1` once on that machine and paste the URL at the hidden prompt. Windows PowerShell 5.1 also works (`powershell -File scripts/Post-Version.ps1 ...`) where `pwsh` is absent; keep `Post-Version.ps1` pure ASCII, because 5.1 reads this BOM-less file as Windows-1252 and a stray non-ASCII byte can terminate a string. If the upload fails or a credential is unavailable, report that the ZIP was not posted.

## Git and collaboration (two people, two different AI tools)

- Two developers work on this repo with different agents (ChatGPT/Codex and Claude Code). Assume the other person may have pushed since you started. **Pull/rebase before starting and before pushing.**
- Keep changes small and focused, one feature or fix per commit/PR. Don't make drive-by refactors, renames or reformatting of files you didn't need to touch.
- Commit messages: short imperative summary line (e.g. `Recover delayed guild membership and show character surnames`), with an optional body explaining why.
- Never commit SavedVariables, `WTF/`, logs, zips or backups (already in `.gitignore`), and never commit anything containing account names or real character data beyond what already exists.
- Don't edit `WordDictionary.lua` or `QuizData.lua` wholesale. Add entries surgically and keep licenses/sources files in sync (`QUIZ-SOURCES.txt`).
- Don't add tool-specific instruction files with conflicting rules. If a rule changes, update this file in its own commit so both agents pick it up.
- Line endings: Windows contributors have `core.autocrlf=true`. Don't commit line-ending-only changes.

## Things agents must not do

- Add dependencies, libraries or a build system without both developers agreeing.
- Change the addon-message prefix (`TheCommune1`), the SavedVariables name, or existing packet formats in a breaking way.
- Weaken permission checks, input sanitization, or credit safety logic.
- Use automation that breaks the game's Terms of Service (no botting, no automated targeting or attacks in combat).
