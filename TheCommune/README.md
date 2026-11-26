# The Commune — 0.4.52

## Real level-ups and more reliable announcements (0.4.52)

The temporary Radio Lysander popup, example stats and preview command have been removed. The same portrait popup remains for real level-ups on every character, using live stat snapshots. Both the popup and announcements now handle PLAYER_LEVEL_UP and the modern PLAYER_LEVEL_CHANGED event, accepting only upward real-level changes from the latter and deduplicating the two event paths. Login, reload and temporary level scaling do not create a celebration.

Even-level guild announcements now wait until combat and the client's chat-messaging lockdown have ended. They use actual guild membership instead of requiring the addon's guild store to be ready. A short-lived pending send allows up to three attempts after explicit errors or rejections, expires after two minutes, and is cancelled if the guild changes. A nil return is treated as submitted, not retried for lack of an echo, to avoid duplicate chat. Old levels are not replayed after reload or joining a guild. Login refreshes the current-level baseline instead of retaining a stale higher level forever.

/commune debug now includes this character's latest announcement status. This cannot reconstruct an earlier missed message on someone else's client, and only the leveling player's addon sends their announcement, so that player needs the updated addon running. Offline checks cover both event paths, restrictions, retries and popups; live guild-chat delivery still needs verification.

## Level-up stat popup (0.4.51)

Every actual level-up now shows a movable, portrait-topped window in The Commune's dark ledger style. It compares max health, max mana when present, and Strength, Agility, Stamina, Intellect and Spirit, with gains in green. The portrait uses the client's player portrait. Stats unavailable on the client are omitted, and a missing old value is shown as a question mark rather than invented.

The addon keeps a live in-session snapshot and waits for the new level's stats before comparing. These are character totals including current equipment and effects, so equipment or buff changes at the same time can affect the differences. Duplicate level events are ignored, rapid levels coalesce, and the popup waits until combat ends before appearing. It closes after 20 seconds or with its close button; its dragged position is saved. Ordinary login/reload does not replay a level-up. The existing even-level guild-chat announcement is unchanged.

For this design preview, Radio Lysander alone gets a one-time automatic popup after login, clearly marked as example values, which stays until closed. On that exact character, /commune levelpreview can reopen the temporary preview outside combat. The preview changes no real stats or rewards and sends no chat or guild data. Other characters only receive real level-up popups.

## Modern item-link handler (0.4.50)

The request editor now also listens to ChatFrameUtil.InsertLink, the modern link path used by the installed Auctionator interface. The previous release listened only to legacy global functions, which that path can bypass. The new hook uses the existing item-only, focused-field and editable Requests-page checks. It is a secure post-hook and leaves the original function and return values intact. Auction item search is unchanged. Offline checks exercise the modern-only call path; linking still needs an in-game confirmation on Forever.

## Auction items in request search (0.4.49)

The request item search now learns names and IDs from available auction browse results, including the older auction-list API where supported. Opening the item field also checks current auction results, and arriving item information refreshes the suggestions. Learned items remain available in later searches; this is a local known-item search, not a complete game-wide item database.

Focus the request item field and Shift-left-click an item to insert its link. The request editor now also listens to the modified-item-click handler for auction interfaces that bypass the usual chat-link path. Only item links are accepted, and the handler requires the editable Requests page and focused item field; other fields and normal item interactions are left alone. Dropping an item, entering its ID, and typing an exact known name remain supported. Offline checks pass; the Forever auction interface still needs an in-game check.

## Solid, consistently layered windows (0.4.48)

Addon window backgrounds are now opaque. Independent windows use separated frame levels so labels and buttons from a window underneath cannot draw through one above it. Opening a window or clicking its background brings its whole frame group forward within its normal strata. Menus and embedded panels keep their parent-controlled layering. Saved positions and gameplay data are unchanged.

## Manage requests across your characters (0.4.47)

Characters sharing this account's SavedVariables can now edit, close and delete each other's existing requests. My requests includes your known alts, and selecting an alt's row keeps that character as the requester throughout saving and closing. New requests still belong to the currently logged-in character.

Log each alt in with The Commune on this WoW installation at least once so it is recognized locally. The local character registry controls editor access; received Social account claims do not grant permission. Requests remain scoped to the current guild, and separate installations do not automatically share this local ownership registry.

Alt edits retain their original owner and revision through the existing cache protocol. A small additive notification asks updated peers to refresh their cache after the normal sync cooldown; older peers can retrieve the changes on their next cache sync. No legacy request packet is sent under the editing alt's name. Saved request records and deletion tombstones remain compatible with previous versions. Offline two-client and editor checks pass; live in-game sharing still needs verification.

## Your daily results alongside the guild (0.4.46)

The quiz and Wordle guild lists now include a first row labeled You. The quiz row shows your daily answer tiles, including unanswered questions. Your Wordle row follows your guesses while playing and shows your completed result, including X/6 for a loss. Each new daily game starts fresh, and local rows come from your own saved progress rather than waiting for another client to send it back. Guildmates' sharing and credit awards are unchanged.

## Two death categories (0.4.45)

Unknown zone deaths now contribute to the displayed PvE count on both the floating panel and the Deaths page. The separate Unk column is removed, and tooltips explain that PvE includes older deaths and unidentified causes. PvP and overall totals stay the same. Original cause records remain intact in SavedVariables and sync, so refreshing or receiving the same data cannot add deaths twice.

## Compact zone death panel (0.4.44)

The movable zone death panel now uses a narrower frame, tighter rows and just the zone name in its title. The repeated total footer is removed; hover a player for their total and full breakdown. A scroll hint appears only when more than five guildmates have deaths in the zone.

The former question-mark column is labeled Unk. Hover the column headings for an explanation: unknown deaths include records from before the PvE/PvP split and deaths whose cause the client could not reliably identify. Existing totals and classification are unchanged. The full Deaths page remains available in /commune.

## Safer offline cache sharing (0.4.43)

Guild data continues to use the original record revision, never the time somebody relays it. Higher revisions win; at equal revisions, deletion wins. Direct owner snapshots take priority over conflicting cached copies at the same revision, and conflicting cache copies resolve consistently. Live and cached multipart snapshots assemble separately, and incomplete or inconsistent cache payloads are rejected.

Saved snapshots now keep local source and receipt metadata. A per-character, per-guild revision high-water mark remembers newer versions reported by guildmates, so the next local edit can advance beyond them after restoring an older save. Your own cached payloads are still not imported over your local data. These additive SavedVariables fields preserve existing saves and do not change the legacy packet formats.

Stale relays cannot roll displayed daily results back to an earlier day, rebind an account identity established directly by its player, lower cumulative honor/death counters, or erase newer professions. Lifetime game totals merge monotonically, completed daily answers remain protected, and unavailable inventory APIs leave the previous gear snapshot intact. Credit permissions and receipt rules remain in force.

These checks cannot recreate missing local history with certainty, and older addon versions still apply their own conflict rules. All guildmates should update. Offline regression checks cover revision conflicts, cache transfers, recovery migrations and existing features; mixed-version behavior still needs verification with two clients in game.

## Even-level guild announcements (0.4.42)

Gaining an even level now posts a single guild-chat message, for example: [The Commune] Ding! I just reached level 20! This applies to every even level your character gains while running the addon. Only the leveling player's client announces it, so other guildmates running The Commune do not repeat the message.

Logging in, installing, or reloading does not announce your existing level or replay earlier milestones. Duplicate events are ignored per character, and levels gained outside a guild are not announced later when joining one. If the client rejects a send, it is not repeatedly retried. Other guild sharing remains on the hidden addon channel.

## Copyable debug reports (0.4.41)

`/commune debug` and `/commune craftsdebug` now open a movable window holding the whole report in a selectable text box instead of printing it line by line into chat. The text is selected as soon as the window opens, so Ctrl+C copies all of it; Escape or the close button dismisses it. Scroll with the wheel or the bar on the right for reports longer than the window.

The report is read-only, so a stray keypress cannot change what you are about to paste. Nothing about what the reports contain has changed. If the window cannot be built for any reason, the report falls back to chat exactly as before, because a debug report is wanted most when something is already broken.

## Quiet reminders inside instances (0.4.40)

The login/new-post reminder stays hidden inside instances, including dungeons and raids. Entering an instance hides a reminder that was already open, and new requests or projects do not reopen it while you are inside. Unread notices remain saved and a deferred reminder can return after you leave. Logging in or reloading inside an instance follows the same rule.

Only the reminder is suppressed. `/commune`, its pages and games, guild sync, and the separate death/hitlist panels continue to work normally. `/commune summary` also waits until you are outside an instance.

## PvE and PvP deaths by zone (0.4.39)

The Deaths page now separates each guild character's PvE, PvP, Unknown, and Total counts for your current zone. The small movable panel shows PvE, PvP, and ? columns; hovering a row explains the counts and shows the total. Its position, dismissal, and enable/disable preference are retained.

New deaths are classified when a fresh, readable death recap identifies the fatal source: players count as PvP, observed player-controlled pets or guardians count as PvP, and confirmed NPC or environmental/self deaths count as PvE. An enemy target, a PvP flag, or being in a battleground is not enough on its own. If the client hides the source, the recap is unavailable, or a pet/vehicle's control cannot be established, the death stays Unknown. The zone is captured at death before releasing to a graveyard. Classification can fill in shortly afterward without increasing the total again.

Previously saved zone deaths have no cause information and remain in Unknown. Totals are preserved, including guildmates on older versions. The split starts with this update and shares through the usual guild sync and offline cache paths; guildmates need 0.4.39 to exchange cause details. Missing details from an older peer never erase a split already received.

## Shared daily quiz results and saved scores (0.4.38)

Daily Quiz now has a compact Guild today panel beside the questions. Each guild account shows its score and one tile per question: green + for correct, red x for wrong, and grey - for unanswered. Partial quizzes remain visibly unfinished. Six accounts fit at once; scroll over the panel for more, or hover a row for the full name and right/wrong/unanswered counts. No selected answers or answer text are shared. The main quiz, rewards, and daily reset are unchanged.

The addon also retains a dated score record for each guild account it receives, including the quiz's correct/answered/total counts, per-question outcomes, and Wordle result when available. These records survive daily resets and reloads and are retained without an automatic age cutoff. The history has no player-facing screen yet. Scores are account-wide within each guild, so alts do not create separate daily entries. Saved history can catch up through the existing offline cache-sharing system.

Guildmates need 0.4.38 or newer to publish exact quiz tiles and daily score history. Today's saved local answers are picked up when updating. Earlier remote days, missing players, and missed results are not invented; an absent result is not a failed quiz. As with other guild data, a score must reach an online peer before it can be cached and forwarded. SavedVariables reach disk on a normal reload/logout.

For future data work, the retained records are in each guild's `social.dailyScores[account][utcDay]`. A record includes `name`, `revision`, `total`, `answered`, `correct`, `colors` (0 unanswered, 1 wrong, 2 correct), and `wordleResult` (0 unfinished, 1–6 solved, 7 lost). `utcDay` is the Unix day number used by the daily games. Recording or receiving a score does not award credits or modify attempts.

## Guild deaths in your current zone (0.4.37)

The new Deaths tab in the main window, also opened with `/commune deaths`, lists guild characters with shared deaths in the zone or instance you are currently in. It follows your location automatically and shows each character's count, highest first. These are deaths from all causes recorded since 0.4.35, rather than historical lifetime zone totals. Offline characters appear when their records have been shared; missing records do not mean zero deaths.

A small movable panel shows the same current-zone counts while playing. It stays hidden where there are no shared deaths, shows up to five characters at once, and scrolls for the rest. The X dismisses it until you change zones. Uncheck Show zone panel while playing on the Deaths page to disable it, or re-enable it there. Its position and the panel preference survive reloads. Zone changes and new guild data update both views without opening the main window or playing a sound.

## Offline player information sharing (0.4.36)

Online guildmates can now forward their saved copies of another player's requests, profession skills and learned recipes, equipment, PvP/death statistics, and daily-game profile while that player is offline. Previously saved records work too; the original player does not have to log in again first. Radio and Arrow both need 0.4.36 or newer for Radio to forward Keyin's cached information to Arrow. Older versions continue to exchange their own updates normally.

Discovery runs at login and with Sync guild. Caches advertise revisions and checksums, the receiver requests only missing/newer or differing records at the same revision, and peers suppress duplicate offers. Normal updates and profession scans take priority over background cache traffic. Large records are fragmented within WoW's message limit, verified before processing, and retried on interruption. Stored ownership, independent revisions, request deletions, and existing officer/guild-leader checks remain intact. A cached copy is the last known snapshot; it cannot reveal changes that the offline player has not shared yet. Projects and the hitlist retain their existing forwarding paths.

The Crafts list also fills the available window height, with profession icons beside its row and filter names. Recipe details are available in the row tooltip. `/commune debug` includes cache discovery/request/application counts.

## Death counts by zone (0.4.35)

The addon now saves a per-character count of deaths from any cause in each zone or instance. It records the location when the character dies, then shares the counts through normal guild sync. Zone totals start with this release. The data is saved for a future display.

## A mixed five-question daily quiz (0.4.34)

Starting November 24 at 00:00 UTC, each daily quiz shuffles three Warcraft questions, one other gaming question, and one general trivia question. There are 28 new questions across the two new categories. The previous quiz and any answers already submitted carry through.

## Sharper daily quiz questions (0.4.33)

Replaced basic class and faction questions with expansion launches, raid openings, secrets, and Warcraft oddities. The quiz still has four questions per day. The November 23 UTC quiz keeps its original questions so answers already submitted that day still line up.

## Hero and Shame PvP stats (0.4.32)

PvP Stats tracks confirmed killing blows when the client exposes the attacker, victim, and their levels. Hero counts kills against players at least three levels higher, and Shame counts kills against players at least five levels lower. Use the new buttons to sort the guild by either stat. Previously recorded level gaps count too. Skinning recipes remain searchable through Crafts.

## Profession checkboxes and login patch notes (0.4.31)

Crafts shows profession checkboxes below the search bar. Check any combination, or clear every box to show all professions. The Crafter dropdown still filters to a guildmate or to recipes craftable by the guild. The login summary now includes a short note about the latest visible change.

## Craft filters (0.4.30)

Use the Profession and Crafter dropdowns alongside the Crafts search. Pick a guildmate to see the recipes they can make, or choose Craftable by guild to see recipes any guildmate can make.

## Less work during refresh and sync (0.4.29)

Crafts refreshes when recipe data changes and redraws once per resize step. Item search indexes exact names and ranks only the suggestions it needs. The login summary updates when requests, projects, or daily games change. Automatic board syncs send requests and projects without pushing another local profession snapshot. Login, manual sync, and replies to guildmates still support full catch-up. Guild membership and rank changes clear cached permissions before pending updates are checked.

A pass over the rest of the addon for the same kind of repeated work the Crafts tab had. Rank, level, class and surname each used to walk the entire guild roster and normalise every name, from checks the windows run on every refresh; there is now a single roster scan per roster change that all of them read. Guild rank permissions are asked for once per rank instead of once per check. The item box no longer re-normalises every learned item name on each keystroke.

The Crafts tab no longer stutters. It was rebuilding the whole recipe catalog on every refresh, asking the client for a spell name and a profession name for each of its a thousand-plus entries and working out guild availability for every row, and a refresh happens on each synced packet, each item-info event and once per frame while the window is resized. The catalog is now built once per change to guild data and filtered from that, and a recipe's availability is worked out only when its row is actually shown or hovered.

Crafts and Projects have the same scroll bar the Hitlist got, which matters most on Crafts where the catalog runs to over a thousand recipes. The bar moved into its own file rather than being copied, so all three pages share one implementation: drag the handle, or click the track to page toward the click.

Closing a request now actually closes it. It used to delete the record outright, which is why Include closed had nothing to show: the row list skips deleted records before it ever considers that checkbox. A closed request keeps its item, amount and purpose and appears whenever Include closed is ticked. Selecting one of your own closed requests turns the same button into Delete request, so removing it for good is still one click, just a deliberate second one.

Requests can now ask for gold. Type `gold` in the item field and set Target to the amount; the row shows what is still owed with a g after it. Gold is not an item, so it travels in the existing item field under a reserved value no real item can use, which keeps the request packet unchanged: guildmates on older versions still receive the request and simply name it as an unknown item.

The Hitlist has a real scroll bar beside its rows: drag the handle, or click the track to page toward the click. The handle's length shows how much of the list fits on screen. Its gutter is reserved even while the bar is hidden, so rows keep their width as entries come and go.

Armory slots now carry the item's rarity colour as a frame around the icon, so a character's quality spread reads at a glance instead of one tooltip at a time. Empty slots and items the client has not cached yet stay neutral grey until the colour is known. The Hitlist now says how much of the list you are looking at, so it is clear the rows continue past the last one on screen. The project description box no longer flickers between its own text height and its laid-out height while the window is being resized.

A new Armory tab shows any guildmate's equipment without inspecting them. Real inspection needs the player loaded and in range, so every client publishes its own equipped item IDs over the guild channel instead, and the tab renders the cached snapshot: pick a character on the left and their eighteen slots fill in on the right, with the live item tooltip on hover. Class and level come from the guild roster, so they never go on the wire, and equipped item level travels with the gear. Sharing is automatic for anyone on this version, the same way PvP and death stats already work.

## Minimap button (0.4.20)

Click the green C on the minimap to open or close The Commune.

## Less text on guild panels (0.4.19)

Trimmed repeated headings, footer tips, and always-visible instructions. The login summary takes less space when there are no new posts. New-post notices, guild sync status, error messages, and gameplay feedback stay visible.

Each row of the nearby-hitlist alert now carries the player's class icon, and hovering a row opens a tooltip with their class, level and every guildmate's note about them. The same notes are appended to the in-world unit tooltip, so hovering a listed enemy tells you why they are listed and who listed them.

Player labels now keep the surname when a guildmate's name reaches us without one. The addon reads the missing surname from the player's own published profile, or from the guild roster when exactly one guildmate carries that given name. The PvP list names the stored character key on any rows that would still read identically, so two characters called the same thing are never mistaken for one.

The guild board retries membership lookup while guild information loads. Missing guild realm data can reuse an unambiguous saved guild record. Character labels display given names and surnames where available.

Hovering over a listed opposing player adds a Hitlist line to the unit tooltip. The movable nearby alert shows multiple sightings at once with class and level when the client exposes them. Scroll to see more players. While out of combat, clicking a row targets its player if the addon can still identify them through an available unit token, such as a visible nameplate. The panel remembers its position.

Hitlist now has its own tab beside Projects. Crafts search supports output-item keywords such as bags, containers, swords, maces, axes, and shields. Results are limited to recipes already in the guildâ€™s Crafts catalog.

A dependency-free guild item request board for WoW Forever (interface 16001).











## Cursor resize, flight entertainment, aim trainer and credit recovery (0.4.13)

The resize handle now uses cursor deltas from the captured starting size instead of native StartSizing. Clicking the handle without moving leaves the size unchanged. Logical mouse movement accounts for effective UI scale, the top-left stays anchored, and resizing retains the existing minimum/screen limits without changing bounds on every click. Layout updates remain once per frame during the drag, and the final dimensions are saved on release.

The flight panel is now **The Commune - Flight Time Entertainment**. Its width is 352px and a single-score-row panel is about 112px tall; additional/wrapped score rows add only their measured height. Buttons open Daily Quiz, Daily Wordle and Aim trainer. Its independently saved movable position remains.

**Aim trainer** is a new Guild Fun tab, also available through `/commune aim`. Seven round targets stay on the field. Clicking a target replaces it in a different location, with spacing from other targets; clicks outside a circle count as misses. The panel shows hits, misses and accuracy. New round clears the current round but preserves lifetime hit/miss totals. Current round counters and normalized target positions are account-wide SavedVariables and survive reloads; positions fit the resized arena. This game awards no Social Credits.

Fixed a verified credit-storage split: GetGuildInfo can return an empty realm string, which Lua treats as a real value. That created `:GuildName` alongside `Realm:GuildName`, separating earned credits, known awards and other guild data. Empty realms now fall back to the client's realm name. On load, the ambiguous empty-realm record is merged into the matching real-realm guild. Independently earned/spent wallet totals and local outgoing counters are combined once. Received issuer counters are merged by maximum, avoiding duplicated incoming awards. The original source store/wallet are retained in `TheCommuneDB.guildRecovery` before migration. Existing request/project records use revision/tombstone rules, and known PvP totals are retained.

Added durable per-wallet receipts for known incoming awards/removals/transfers. Those credits remain even if the issuer's profile is temporarily missing. Stale profile snapshots cannot lower cumulative earned/spent fields, and incoming copies of your own profile cannot replace your local wallet. GM packets received before roster permissions are available are deferred and retried on roster update. If retained daily answers prove rewards are missing and this account has only one guild wallet, that exact gap is repaired once and recorded in `TheCommuneDB.creditRepair`. Multi-guild histories without clear attribution are not guessed. `/commune debug` now includes wallet and recovery details.

Prompts do not pause data recording or sync. Progress is updated in the SavedVariables table immediately while playing; WoW writes that table to disk on reload, logout or normal exit. The addon cannot force an uninterrupted per-action disk flush or guarantee changes since the last save survive a crash. Recovery/migration also reaches disk at the next normal game save. No prompt confirmation is required for unrelated progress to be recorded.

Checks include constant seven-target state, hit/miss persistence, updates while a death prompt is open, repeated resize clicks without movement, cursor scaling, migration against a copy of this installation's actual SavedVariables, repeat migration without double credit, durable receipts, conservative reward repair and roster-deferred GM adjustments, plus the existing regression suite. Native drag feel and appearance still need an in-game check.

## Compact flight panel, hitlist sharing and death prompt (0.4.12)

The flight reminder uses a compact header/button area and sizes its score section to the actual text height. With one short score row it is about 134px tall, rather than reserving 250px. More accounts or wrapped score text add only the space needed. The saved movable position is retained.

Hitlist sharing now includes owner-labelled cache snapshots, so another addon user can pass on a cached entry while the original author is offline. Entries retain their original author and display capitalization. Deletion markers travel with snapshots; revision checks prevent old snapshots resurrecting a known removed entry. Owner aliases are normalized at load. Cooperative guild cache sharing is not a cryptographic authorship system; the normal UI still restricts editing to the author and removal to the author/officers. Officer deletion records carry their actor and receiving clients check that actor's roster permissions.

Fixed a reproducible Windows Lua issue where byte-wise string.lower corrupts UTF-8 player names (for example Ã…ngstrÃ¶m), potentially blocking the send queue with malformed bytes. Player-key folding now preserves UTF-8, with ASCII and common Latin accented case folding. Existing hit targets are rebuilt from their display names where possible. Snapshot chunks preserve UTF-8 boundaries and stay below the addon-message limit. The old owner-sent packets remain for compatibility, but everyone needs 0.4.12 for cache relay. There is a **Sync hitlist** button; opening Hitlist also queues a normal guild query and republishes the cache. `/commune debug` reports hitlist cache queued/received/applied/rejected counts and per-owner active totals.

After an opposing player kills you, a small movable prompt offers **Add to hitlist** or **Dismiss**. It reads the permitted Death Recap API and retries briefly while the recap fills in. It requires a readable Player GUID on the fatal recap event, nonnegative overkill, a recent timestamp and an exact GUID match to an observed opposing player's full name/faction. NPC/environment deaths, unidentified or secret killers, unobserved full names and unknown pet owners are skipped. Existing guild hitlist entries do not prompt again. Nothing is added automatically: the Add button creates your own entry with the note Killed me and queues it for guild sync. The prompt position is saved independently, and Escape/X/Dismiss can close it.

The game API is documented in [Blizzard's DeathRecap definitions](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/DeathRecapDocumentation.lua); the [native recap UI](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_DeathRecap/Blizzard_DeathRecap.lua) treats the first recap event as the death-causing entry. No protected combat-log event subscription is added.

Checks cover direct empty-note sharing, cached relay with offline original author, owner/capitalization preservation, officer tombstones, stale replay, UTF-8 packet boundaries, the new sync control, confirmation/dismissal of a recap-identified enemy, exclusion of NPC/unknown killers and dynamic flight height, plus the existing regression suite. Live guild delivery and death recap availability still need an in-game check.

## Unguilded alts and explicit close control (0.4.11)

An unguilded character now sees a clear join-a-guild state instead of an editable personal board. Guild tabs, Guild Fun and sync are disabled, the request form is hidden, and automatic summary/flight/hitlist notifications are paused. Daily-game shortcuts show that state rather than consuming account-wide attempts or earning credits into an unguilded wallet. Existing guild caches, personal drafts, account identity and daily progress remain stored. Joining a guild re-enables the normal board and summary without a reload; leaving one returns to the disabled state and closes guild popups.

The main X button now directly hides its own window, with an explicit click handler and a higher frame level than page content. It works on Requests, Guild Fun and the no-guild screen. Closing still saves geometry through the existing handlers, and the window can be reopened normally.

Automated checks include an unguilded first login, disabled controls and absent guild popups, shortcut safety, live join/leave transitions, data retention and explicit close clicks across pages, alongside the existing regression suite. In-game mouse interaction still needs confirmation.

## Remembered windows and total deaths (0.4.10)

The main window (including Guild Fun), login bubble, flight panel and hitlist alert now save independent positions. Moving one does not relocate the others. Positions are saved on drag completion, hiding/closing and logout, then restored when that window is created after reload/login. Existing main/bubble positions are migrated from their earlier settings. Main size and resize-lock preferences are retained. The flight panel and hitlist alert are draggable with the left mouse button and stay clamped to the screen. Open panels may coexist at their own positions; their normal show/close rules still apply.

PvP Stats now includes **Deaths** for each character, covering PvP, PvE and other causes. It reads the game's total-deaths statistic (GetStatistic 60), including pre-addon history when available. Native formatted numbers such as 1,234 are accepted, unavailable/secret reads preserve a cached lifetime total, and death events trigger an immediate read plus a delayed read for the game to update its statistic. Lifetime totals are not blindly incremented, preventing the same death being counted once locally and again in the game's statistic.

If no lifetime statistic is available, the addon counts observed PLAYER_DEAD events once per life. Such counts have an asterisk in the list, and selecting the character explains that they are tracked since the addon rather than lifetime. Releasing as a ghost does not create a second death. Totals and their source are saved per character and sent as versioned guild packets; duplicate/stale packets do not add deaths again. Update guildmates to 0.4.10 for death totals. The use of statistic 60 on Forever is also documented in [DeathSound's own Forever release notes](https://www.curseforge.com/wow/addons/deathsoundcustom/files/9574736); no code/assets from that addon are included.

Checks cover independent window positions across close/drag/logout/cold reload, movable flight controls, formatted historical death counts, delayed statistic updates, missing-stat fallback, duplicate death-event suppression, death source labels and stale network packets. The existing request/craft/project/game/sync tests also pass.

## Removed unused media (0.4.9)

Removed the unused Media folder and banner helper. Window headings use text.

## Honor totals, shared Wordle boards and GM credit controls (0.4.8)

PvP rankings now import the game's **lifetime honorable kills** through GetPVPLifetimeStats on login, honor/kill updates and periodic checks. These totals include historical credit and are shared per character. They are labelled separately from **observed killing blows**, because honorable kills can include shared/group credit. No historical victim-level breakdown is invented, and these totals are not added to the observed count. Cached totals are retained if an API read fails. The main ranking uses lifetime honorable kills where available; the shame ranking still uses observed 10+ lower-level kills. The protected modern combat-log subscription remains disabled. [Blizzard's generated player API definitions](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/PlayerScriptDocumentation.lua) document the lifetime-honorable-kill return value.

Wordle's right side now shows small colour-only grids for other guild accounts that solved today's word. Names and guess counts identify each board; no guessed letters or answer text is transmitted. Six miniature boards fit at once; scroll over that area to browse more. A solved board is republished when its author syncs, including a puzzle completed before this update if its saved guesses are available. Only today's boards display. Update guildmates to 0.4.8 and sync to exchange them.

New Wordle wins award **5 credits on guess 1, 3 on guess 2, 2 on guess 3, and 1 on guesses 4â€“6**. Losses award zero, and repeated submissions/syncs never award again. Completed games from earlier versions retain the 2 credits they actually earned; the new scale applies to new wins. Quiz rewards remain automatic and unchanged.

The Social Credits tab now offers **Add credits** and **Remove credits** instead of transfers/officer awards. Only the actual guild master (native guild rank 0) can make manual balance changes, including to their own account. Ordinary officers cannot adjust balances. The amount range is 1â€“99999, with deductions limited to the recipient's cached balance so the UI does not intentionally overdraw it. Additions/removals use separate monotonic cumulative counters and update through guild sync. Receiving clients validate GM status against their own roster; an unknown/unavailable permission fails closed until a later sync. Legacy transfer/award records remain in balances, but new manual packets from non-GMs are rejected. Automatic quiz/Wordle rewards remain available to everyone. This is still a friendly local SavedVariables economy, not server-backed anti-cheat.

Resizing now pins the frame's top-left before bottom-right sizing, limits growth to the remaining screen space and coalesces changes to one layout pass per frame during a drag. Hidden request/craft/project pages are no longer rebuilt while resizing Guild Fun. The final geometry is saved on release, and a page switched back into view lays itself out at the current size. Fonts and game control sizes remain fixed.

Automated checks cover old features plus all six reward tiers, historical HK import/update, board payloads without letters, current-day filtering, native GM gating including forged ordinary-officer packets, self-adjustments, duplicate syncs and resize anchoring/layout coalescing. Live server data and the feel of dragging still need an in-game check.

## Tight summary spacing (0.4.7)

Removed excess space below the login summary status. The bubble is 122px tall for a single status line and grows only enough to fit both new-request and new-project notices.

## Compact summary and credit alignment (0.4.6)

Removed the login summary flavour line and grey footer and reduced its height to 144px. Request/project counts, daily buttons and new-post notices remain. Social Credits no longer shows the Recipient label; its amount field aligns with the first account row and the transfer/award buttons sit below it. Recipient selection still uses the highlighted account row.

## Restored text headings (0.4.5)

The original text headings replace the stone banner throughout the addon. Summary, flight and alert windows return to their compact pre-banner header sizes; the main status line returns below the text title. The recent responsive layouts and field/button styling are retained.

## Fixed-size text, centered games and ledger/stone theme (0.4.4)

Guild Fun now uses a normal 1x content frame. Resizing changes available space, positions, column widths and visible list rows, while retaining font sizes and control heights. Quiz and Wordle are centered inside the main window's content area. The fun navigation is centered too. Wordle uses fixed 40px tiles with 4px gaps and fixed-height keyboard keys, so the entire game fits at the supported 760x550 minimum without scaling down its letters. Larger windows add breathing room rather than magnifying controls. Existing saved main-window size, position and resize lock are retained.

Quiz question text, answers, result and navigation are centered. The difficulty label (including Normal) is hidden; question selection and answers are unchanged. The grey daily-quiz footer, initial Choose one answer prompt and Wordle footer are removed. Hitlist and Guild Scores introductory text is removed, as is the Guild Scores explanatory footer. Actual quiz result explanations, invalid-word messages and PvP availability status are retained.

The joke shop controls and equipped-title suffix are hidden. Existing purchases, balances and title data remain stored for possible later use. Ordinary transfers and officer awards still work.

Searches and form fields now use pale parchment, dark ink, subtle borders and padded text, based on the Guild Ledger preview. Action buttons use the muted bronze/grey stone palette and a restrained bevel/gradient, based on Carved Stone. The same styling is used across Requests, Crafts, Projects, Guild Fun, summary buttons and flight actions. Windows use a warmer dark background. Native text-entry behavior, focus, item-name suggestions, item links and drag/drop remain. Wordle's transparent row input and coloured letter/keyboard feedback retain their game-specific appearance.

Automated checks exercise the old request/craft/project/sync features, direct Wordle input, responsive geometry for all six fun pages at minimum/default/large sizes, fixed scale and tile/key sizes, centering, removed text and the shared theme. Actual in-game appearance still needs confirmation after `/reload`.

## Stone banner headers (0.4.3)

The approved horizontal stone banner now replaces the text title in the main window (including its Guild Fun pages), login summary and flight reminder. The hitlist alert also uses a compact copy. The banner is bundled as a native RGBA TGA texture and retains its aspect ratio. The summary and flight panels have extra header space so the logo does not overlap controls or messages. Existing main-window size/position/lock preferences and saved data are preserved.

Textbox/button alternatives are previews only; the current controls are retained pending a style choice. Preview concepts: Quiet dark (muted flat fields), Carved stone (inset slate fields), and Guild ledger (warm parchment writing surfaces). This version changes branding and the space it needs, rather than applying a broader visual redesign.

## Wordle tiles and blocked-action fix (0.4.2)

Wordle now has a centered six-row, five-column board, plain square tiles and a clickable QWERTY keyboard. Typing goes directly into the active row. A transparent native EditBox sits over that row and sends the typed letters to the tiles, with normal Backspace/arrow-key editing. Click the active row to focus it, type five letters and press Enter; on-screen ENTER and DEL work too. Invalid words leave the row available for correction. After a valid guess the input moves to the next row; completed games lock typing. Tile and key colours follow the usual green/gold/grey feedback. Escape releases keyboard focus; leaving/hiding the game releases it too. Existing daily attempts, rewards and statistics are retained.

The likely source of the Blizzard-only-action popup was 0.4.1's attempt to register COMBAT_LOG_EVENT_UNFILTERED. Protecting that call with pcall catches Lua errors but does not prevent Blizzard's ADDON_ACTION_FORBIDDEN UI. This version never attempts the combat-log registration on modern clients, clients exposing secret-value APIs (including Forever), or unknown builds. Only an explicitly identified pre-12 client without secret APIs can take the legacy tracking path. Registration is gated before the protected action, rather than tested by calling it.

**Automatic PvP kill/level-gap tracking is consequently unavailable on Forever for now.** The board, cached totals and guild sharing remain, and the status label explains the limitation. No generic honour/assist totals are substituted for confirmed killing blows, and no victim levels are guessed. Existing PvP data is preserved. A different supported source is needed before automatic tracking can be restored on this client. [Blizzard-generated combat event restrictions](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/CombatLogDocumentation.lua) and [another addon's own release notes documenting the same Forever registration issue](https://www.curseforge.com/wow/addons/soundboard-for-wow/files/9484045) support this diagnosis; the supplied screenshot did not include an exact function/stack trace.

If this addon encounters another ADDON_ACTION_FORBIDDEN or ADDON_ACTION_BLOCKED event, it records the function, addon version and timestamp in TheCommuneDB.lastBlockedAction. `/commune debug` prints the last recorded blocked function. This does not suppress Blizzard's warning and does not change the taint-log CVar or other game settings. Old entries identify their originating addon version.

The selected stone logo has also been regenerated as a wide horizontal plaque with **The Commune** on one line. The preview is `outputs/guild-icon-options/the-commune-wide-stone.png`, with its imagegen prompt in WIDE-PROMPT.txt. It is a standalone image; addon art is not replaced automatically.

## Same-window Guild Fun and PvP (0.4.1)

**Guild fun** now replaces the contents of the existing main window. **Back to guild** at the top right restores your previous Requests/Crafts/Projects tab. There is one movable/resizable main window with the same saved dimensions, location and resize-lock preference. Fun content scales to fit that window. Daily slash commands and the login/flight shortcuts use this same window too.

Open **PvP Stats** under Guild fun, or `/commune pvp`.

- The main ranking sorts by **confirmed killing blows** credited to your character or its current pet. Groupmates' killing blows, assists, NPC deaths and ordinary death messages do not increase your count. Repeated copies of the same death event are suppressed. A later genuine kill of the same player can count again.
- **Within Â±2 levels** includes victims two below, one below, equal, one above and two above your level at the time of the kill.
- **Higher** means victims at least three levels above you.
- Lower-level victims are separated into **3â€“5 below**, **6â€“9 below**, and **10+ below**. **Show shame list** ranks characters by their 10+ lower kills.
- Select a character row for the **exact level-gap histogram**, such as `-2: 4` (four victims two levels below) or `+3: 1` (one victim three levels above). Unknown-level kills have their own count.

Victim levels come from exposed target, mouseover and visible-nameplate unit data, matched to the exact player GUID. Observations expire after 30 seconds and are refreshed for visible units. Missing/skull/secret levels are never inferred from names or appearance. Your current level is used at the death; future level-ups do not reclassify earlier kills. Combat data that the client restricts is skipped. The PvP page displays when combat tracking is unavailable/restricted, rather than claiming complete coverage. No restricted API is bypassed. Combat API restrictions are declared in the [Blizzard-generated API definitions](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/CombatLogDocumentation.lua).

PvP totals start with this version while the addon is running; previous lifetime kills cannot be reconstructed. Stats are lifetime **per character**, preserved across reloads and shared on the same paced guild channel. Exact-gap counters converge when packets arrive out of order; repeated syncs do not add kills. Guildmates need 0.4.1 to exchange and view these stats. No Social Credits are awarded for PvP kills.

The separate guild-icon preview options are in `outputs/guild-icon-options`, with their generation prompts. They have not been installed into the addon pending your choice.

## Guild fun and item names (0.4.0)

Use **Guild fun** beside the main tabs, or the commands below. All guildmates need 0.4.0 and a `/reload` to use the new shared features. Existing requests, projects, recipe data and window preferences are preserved. The summary bubble is now 264 x 184 to fit daily game buttons; its saved position is retained.

- `/commune quiz`: four multiple-choice Warcraft questions per account per day. The 52-question bank includes silly, serious, historical and four very hard questions. First answers are final; correct answers award **1 Social Credit** each. Answers include a short explanation. Historical questions use their stated expansion/era, rather than Forever's altered mechanics. Reference links are in QuizData.lua and QUIZ-SOURCES.txt.
- `/commune wordle`: a shared daily five-letter word, six guesses, coloured feedback and used-letter display. Repeated letters are counted correctly. A win awards **2 Social Credits** once. Solutions include common English words and Warcraft-flavoured words; accepted guesses use the bundled English dictionary plus these solutions. WORDLIST-LICENSE.txt covers the dictionary.
- `/commune credits`: view balances, send **1â€“5** credits per transfer, and buy addon-only joke titles for **2â€“3** credits. Guild leaders and the same officer ranks authorized for projects can award **1â€“5** credits per action. Repeat equip of an owned title is free. A small local history records rewards, purchases, transfers and incoming credits. Credits have no gold value and do not modify game currency, items or character titles. No automatic PvP, kill or request-completion rewards are added.
- `/commune hitlist`: add an opposing-faction player's **full first and last name**, a note, or use an enemy target. Each member has 20 entries and can change/remove their own entries; officers can remove anyone's. Alerts are a private closeable popup plus a sound, enabled by default and toggleable in the hitlist. Detection uses the target, mouseover and currently visible nameplates. It cannot scan a whole zone, guarantee a distance or detect hidden players. A player must currently be detected as the opposing faction to trigger an alert; typing a name does not reveal that player's faction. Repeat alerts have a 60-second per-player and 5-second global cooldown. Secret/unavailable unit information is skipped.
- `/commune scores`: lifetime guild account scores: quiz correct/answered, Wordle wins/completed games and credit balances. One account has one row, identified by the first character that used this feature. Scores are cached and update through addon sync.

**Daily reset is 00:00 UTC**, shared by all guild clients. Quiz choices, attempts and Wordle guesses are saved account-wide in TheCommuneDB: switching characters or reloading does not give another set of attempts. Lifetime game statistics are account-wide too. The credit wallet is shared by your characters **within each guild**, with rewards credited to the guild you are in when earning them. SavedVariables are local to this WoW account/installation; they are not a server-backed cross-computer account service.

The login bubble now includes **Quiz n/4** and **Wordle To do/Done** buttons. Clicking either opens the game and dismisses the bubble. On a flight path, a closeable panel shows unfinished dailies and cached guild scores. It opens once per flight, stays closed after dismissal until the next flight, and disappears on landing. Completed dailies still leave the score panel available on the next flight.

Requests accept **item names, links, numeric IDs and dragged items**. Try `Copper Ore`, or type `copper` and select an icon/name suggestion. Exact known names resolve automatically; a partial name must be chosen from suggestions. Duplicate names require choosing a specific result. The index starts with common materials and grows from bags, requests and item information exposed by the client. It is not a complete Forever item database: an unknown/custom item still needs an ID, link or drag first. Client item names take precedence over English starter names.

Shared social profiles, transfers, hitlist entries and removals use the existing paced hidden guild channel. Duplicate/replayed transfers use cumulative counters, so syncing does not pay twice. Your own social data is published on sync; other people's cached scores and hitlist entries remain visible locally while they are offline. New edits still need an online overlap with their author (or the officer issuing a removal); there is no external service. Social Credits and quiz results are a friendly trust-based game, not an economy protected against deliberate SavedVariables editing. Ordinary syncs do not manufacture credits.

The weekly gamble remains on the backburner.

## Bubble navigation and remembered resizing (0.3.2)

Clicking **Requests** or **Projects** in the login bubble opens that tab in the main window and dismisses/acknowledges the bubble, just like its close button. A genuinely new later post can still reopen it.

Main-window resizing is **enabled by default**, with the bottom-right grip visible. **/commune resize** still toggles between unlocked and locked. Your chosen lock state is saved together with size and position, so the next login/reload restores them. Existing installations without a saved lock choice start unlocked. No saved-data reset is required.

## Compact windows and quiet synchronization (0.3.1)

The main window defaults to **820 x 600** UI units, and the login bubble is **264 x 128**. Existing saved main-window dimensions are reduced by about 8% once, respecting minimum sizes; later manual resizing is retained without further automatic shrinking. Main/bubble background opacity is reduced from 97% to 87%, and the project description background is slightly lighter. Text and icons remain fully opaque.

Unknown acquisition-source wording is hidden. Known skill requirements and **Skill requirement unknown** remain visible. Exact skill requirements are not exposed for every Forever recipe; observed recipe fields, requirement text and relevant trainers can fill some gaps.

Recipe scans stay local until another The Commune user is detected in the current guild session. A guildmate without the addon does not cause a full recipe exchange. Discovery queries and small request/project updates still use the hidden guild channel. Once an addon peer appears, normal snapshot sharing resumes.

Outgoing messages are spaced at least one second apart. WoW's AddonMessageThrottle/ChannelThrottle responses now trigger quiet retries, longer pacing and backoff rather than repeated chat warnings. Real non-throttle failures remain in status/debug output and print at most once per minute. Slow snapshot transfers are retained while chunks continue arriving. **/commune debug** shows peer detection, send spacing and throttle counts. This respects game limits; it does not bypass them or guarantee instantaneous delivery.

## Login summary and new posts (0.3.0)

A small closeable bubble opens on login showing the number of **active request posts** and **active guild projects**. These are post counts, not the summed quantities of all requested items. The totals start from your cache and update as guild messages arrive. Click Requests/Projects to open that tab, and drag the bubble to move it; its position is saved. **/commune summary** reopens it.

The bubble separately shows **1 new request**, **2 new projects**, etc. Newly received posts from other characters count as new until you close the bubble. Closing acknowledges the current new-post counts. Repeated syncs and quantity/progress edits do not create new-post notifications; genuinely new posts received after dismissal reopen the bubble. Completed/deleted posts leave the active/unread counts. Your own new posts update totals without notifying you about your own action.

History is saved separately per guild and character. Existing cached posts form a quiet baseline the first time this feature loads. Request creation markers distinguish a new request reusing the same slot from an edit; legacy request packets are also sent so older addon versions can still display requests. Update all guildmates to 0.3.0 for reliable new-post detection, especially when a slot is reused for the same item. Projects use their stable project ID. New means newly discovered by your client, not a server-wide unread feed; offline posts still depend on someone actually sharing them through the existing guild sync system.

## Crafting requirements (0.3.0)

Uncraftable recipe rows now show the best available guild candidate's unmet requirements. Selecting or hovering a recipe shows per-member details, using each member's last shared profession rank:

- **Skill 225/250 (needs +25)** shows current skill versus the actual required skill. If the profession cap is also too low, the detail adds **Raise profession cap from 225 to at least 250**.
- For a confirmed **trainer-taught** recipe, insufficient skill is shown first; once the skill is sufficient, the advice becomes **Train recipe at a profession trainer**.
- For a confirmed **non-trainer** recipe, both a skill shortage and **Recipe missing** are shown when both apply.
- A missing recipe at sufficient skill shows the acquisition requirement without inventing a skill shortage.
- Unscanned recipe knowledge and unavailable numeric skill requirements are labelled explicitly. Unknown-source wording is hidden. Absence from a filtered scan is not proof a member is missing a recipe.

Requirements are captured from explicit client recipe fields, localized profession-requirement text/recipe tooltips, and visible trainer services that can be mapped to a recipe. **Opening an appropriate trainer can enrich the directory**, including its exact required profession skill where available. Trainer discovery does not change the game's filters or buy/train anything. Crafting difficulty colours, triviality thresholds, and the crafter's maximum skill are never used as guessed recipe requirements. Some Forever recipes expose no numeric requirement or source, so this is not a complete external recipe database.

Skill/source metadata shares with guildmates. Reopen your professions and visit relevant trainers after updating to collect what your client exposes. Learned recipes remain guild-craftable when any known skill requirement is met; materials, tools, location, cooldowns, and other game restrictions are still separate from recipe knowledge.

Version 0.2.0 adds **Requests**, **Crafts**, and **Projects** tabs. Existing requests, acquisition tracking, resizing, and saved data are retained. All guildmates should update to this version and `/reload` for the new shared data.

Version 0.2.1 repairs empty Forever profession scans by reading **GetFilteredRecipeIDs**, the recipe list used by Blizzard's profession UI, when GetAllRecipeIDs is absent or empty. Empty GetProfessionSpells results no longer replace cached recipes. Visible recipe entries supply learned flags; filtered scans merge only the entries actually observed. Scans wait during source changes, reject linked/NPC views, check recipe profession membership when available, and read matching child/parent/name information. List-update events scan promptly and schedule a short follow-up.

After updating, `/reload`, **keep Blacksmithing (or another profession) open**, clear the profession window's search/filters, and press **Scan professions**. Enable learned/unlearned views to expose more of the catalog. **/commune craftsdebug** prints API availability, returned entry counts/errors, matched open-profession information, and the current scan status. No saved-data reset is needed.

## Crafts: I can make that

Open **Crafts** (or **/commune crafts**). Search by recipe, profession, or crafter. Recipes with at least one confirmed guild crafter sort first. **Craftable by guild only** hides entries with no confirmed crafter. Selecting a recipe lists the members who know it. Craftable means recipe knowledge; it does not promise materials, a tool/station, or an available cooldown.

Each player's addon scans that player's own professions on login, profession/skill changes, and recipe learning. **Scan professions** runs another scan. **Open each profession window once** so the client exposes its full recipe list where supported. It does not inspect another character's private spellbook from your computer. Linked or guild profession views are not mistaken for your own recipe knowledge.

The catalog merges recipe IDs exposed by scanned professions, including visible unlearned recipes through GetFilteredRecipeIDs or all exposed IDs where GetAllRecipeIDs exists. Nonempty learned recipe sets can also be scanned through GetProfessionSpells. Thus the directory can show **No confirmed crafter**, not just known recipes. **It is a discovered catalog, not a guaranteed complete database of every Forever recipe**: unopened/unsupported professions and recipes the client never exposes may be missing. No external recipe database or copied addon database is bundled. Full authoritative scans replace learned flags; filtered scans update observed flags and preserve hidden entries. Explicit unlearned entries and confirmed dropped professions stop listing the old crafter. Unknown/unavailable/empty scan data does not erase cached knowledge.

Recipe data shares through the existing hidden guild channel, using compact IDs and complete snapshots; partial snapshots never replace an older complete one. Large scans may take longer than an item request to share. Requests/projects have queue priority. Guild sync/login/vendor triggers resend your own profession snapshots. Offline directory entries reflect the most recently shared scan, not a live server check; the same online-overlap limitation still applies.

## Guild projects

Open **Projects** (or **/commune projects**). Everyone can browse and search goals. Characters whose guild rank has **officer privileges**, plus the guild leader, can create, edit, update progress, and close projects. This uses the guild permission flag for officer privileges, not a single rank name or a top-two-ranks assumption, so multiple officer ranks work. If a high rank cannot edit, check its officer-privilege setting in WoW's guild rank controls. Missing roster/permission data leaves editing unavailable until it can be verified; incoming writes are also checked against the actual sender's guild rank.

Click **New project**, enter a title, a target quantity, completed/received amount, and a description. Optionally drag an item onto the item field or paste an item link / numeric ID. An item is optional so goals can also be general, such as helping six guildmates get mounts. The description can explain units and collection arrangements. This first version supports one target (and at most one item) per project, with up to 50 active projects.

Any authorized officer can manage a project, including one created by another officer. Progress is **manually confirmed by an officer**, separate from personal loot tracking, to avoid counting the same copper both in personal bags and toward a communal delivery. The project is complete when progress reaches the target. **Include completed** shows those goals; **Close project** removes a goal and publishes a deletion record.

Project edits use revisions, deterministic conflict resolution, and stale-editor checks. A project changed while you were editing must be selected again before saving. Closing a project cannot be undone by replaying an older snapshot. Officers share cached projects during guild sync; ordinary members receive/cache them but cannot publish edits or relay project state as if they were officers. A guild officer must overlap online to initially receive current project data. There is no external server.

## Use

Open **/commune** or **/thecommune**. Click **New request** and drag an item from your bags onto the item icon, or paste an item link / numeric ID. New requests default to **1** item. Enter a target quantity, optional purpose, and delivery instructions, then click **Save request**.

Use the **Requests** tab (or **/commune requests**) to return to personal material requests.

Select your own request to edit it, correct its **Received** quantity, or **Close request**. Eligible acquisitions now increase Received automatically. Once Received reaches Target, it leaves the active board and tooltips. Requests have no expiry. The optional craft field, expiry controls, Always accepting setting, and In my bags tab have been removed.

Existing quantities and received counts are retained. On the owner's next load, old expiry, craft, and ongoing settings are cleared and revisioned for guild sharing. Old expired requests that are still stored and not completed/deleted can therefore become active again. Legacy protocol fields remain for compatibility, but new requests use no expiry, no craft, and a finite target.

Use **All requests**, **My requests**, and search to browse the board. Scroll for more. **Include closed** shows completed requests that have not been explicitly deleted or had their slot reused. Each character can have 20 active requests.

## Window layout and resizing

Request rows show the item's own icon beside its name. The bottom editor uses matching field heights and aligned columns, with equal-width Purpose/Delivery fields and Target/Received fields. A dark background improves readability.

Sizing is unlocked by default. Drag the bottom-right handle to adjust width and height. **/commune resize** toggles the resize lock and grip visibility. The table shows more rows when taller, and columns and editor fields adjust with the width; text is not scaled. The default size is 820 by 600 UI units, with a minimum of 760 by 550 unless the current screen is smaller. Maximum bounds are limited by the screen.

Dragging the window moves it. Size, position, and your resize lock choice are remembered in SavedVariables and restored after reload/login. Opening a vendor still synchronizes guild data without opening the board.

## Tooltips and sharing

Requested items gain The Commune tooltip lines showing who needs them and the remaining amount. Purpose and delivery instructions are included when provided. Other addons replacing standard tooltips may need compatibility work. The tooltip is a reminder and does not block selling.

Guildmates running the addon exchange hidden addon messages on the GUILD channel; nothing is posted to guild chat. Requests are shared automatically when saved. Login, opening a vendor, **Sync guild**, and **/commune sync** also request updates from online users. Vendor sync is quiet and works with the board closed. All sync triggers share a 30-second cooldown to avoid flooding. Messages are sent gradually, so delivery may take a few seconds.

Requests you already received are cached for offline display, scoped to guild and realm. Each character only publishes their own requests; there is no cache relay or central server. You must overlap online with a requester to initially receive their requests. No companion app is used.

Only the owner can edit their requests. Eligible loot/mail progress is tracked automatically on the owner's client; Received remains editable for corrections. Character names are shown without realm suffixes, while virtual-realm identity is retained internally. Forever's alternate guild sender name is normalized and old duplicate aliases are merged, preserving newer revisions and deletion records.

## Automatic progress (0.1.5)

Example: a request has Target 100 and Received 0. Mine and loot 10 copper while this version is running, and Received becomes 10, leaving 90 needed. The local board updates as acquisitions are observed, and revisioned progress is queued for guild sharing automatically. Vendor/manual/login sync also shares the current progress. Ordinary bag totals are never used to retroactively fill a request.

### What counts

- Actual self-loot messages emitted by the game for mining, herbalism, fishing, body loot, containers, and bonus loot. The item must match an existing active request. Localized client formats are used; Forever's plain item-name loot messages are resolved against your own requests where possible.
- Attachments collected from replyable player mail sent by another character, including COD attachments once collected.
- Auction purchases collected from mail identified by the game as a buyer invoice.

Mail requires a pickup action through the standard TakeInboxItem / AutoLootMailItem APIs, a decrease in eligible inbox attachments, and a matching increase in carried items. Merely opening mail, clicking Take, getting a success event, or buying an auction without collecting its delivery is insufficient. Standard open-all helpers using those APIs are supported. Failed or ambiguous deliveries are deliberately skipped rather than guessed. Closing the mailbox before the item gain can be confirmed may require a manual correction.

### What does not count

- Items already owned before creating the request or installing this version.
- Bank, reagent-bank, warband/account-bank, or guild-bank withdrawals; bag sorting, stacking, splitting, and equipment changes. Bag changes alone never create progress.
- Self-mail from the current character or known alts. Each character running this version is remembered in this installation's SavedVariables. **Log each alt in once before collecting its mail on another character.** The mail API does not expose the sender's account ownership, so an alt never seen by this installation cannot be identified automatically. Short ambiguous sender names matching a known own character are conservatively excluded.
- Returned player mail, expired/cancelled/unsold auction returns, sale gold, system/restoration mail, and unidentified mail.
- Sending mail to someone else. Their request changes on their client only when they collect an eligible delivery; both players need 0.1.5 for automatic tracking.
- Vendor purchases/buybacks, crafting results, quest reward/pushed-item messages, trades, or another player's loot messages. These acquisition paths remain manual in this version.
- Repeated bag/inbox events for the same pickup, failed pickups, and ignored duplicate loot chat line IDs.

Progress is cumulative, not a live stock reservation: selling, mailing, consuming, or depositing credited items does not increase the request again. Each acquired unit is allocated once, in request-slot order, if you have multiple active requests for the same item; it never reduces a guildmate's request just because you acquired the item. Progress is capped at each target. An open editor refreshes Received automatically unless you are entering a manual correction.

The source checks are conservative. Loot messages are suppressed while bank, mailbox, or vendor interactions are active and briefly after closing them, so a genuine unrelated loot gain in that interval may need a manual correction. Unknown or inaccessible acquisition information is not inferred. **/commune debug** includes the session's tracked quantities and last credited source.

## Installation and updates

Place **TheCommune** in `_forever_/Interface/AddOns/`. Enable it in the AddOns list. After updating an installed version, type **/reload** on both computers. A first installation during an active game session may require restarting WoW for discovery.

SavedVariables are managed by WoW on logout/reload. Keep TheCommuneDB to retain requests and revisions; no data reset is required. Guild changes isolate the board; former members' cached requests are not automatically pruned.

## Troubleshooting and testing

The status below the title reports guild sync activity. **/commune debug** prints version, guild identity, prefix registration, the advisory restriction flag, queued messages, sent/received/applied counts, and the last send result. Actual GUILD send results govern retries with backoff; successful API acceptance alone does not prove peer delivery.

1. Create a request and confirm it defaults to 1; hover the item in your bags.
2. Have a guildmate update and reload; open a vendor and wait for synchronization (up to the shared cooldown).
3. Confirm your friend sees one request with your character name.
4. Edit or close the request and confirm the other board updates.
5. Log out normally and back in to verify persistence.

Offline Lua 5.1 checks cover the existing request/progress rules plus four isolated guild clients sharing profession catalogs and projects, learned/unlearned recipes, sorting/filtering, snapshot reordering, forgotten recipes/professions, guild leader and multiple officer ranks, rejected member writes, delayed roster availability, concurrent officer edits, deletion replay, UTF-8 descriptions, editor forms, tabs, and responsive layouts. Actual Forever profession availability, guild permissions, localized acquisition events, rendering, and server delivery still require in-game testing. No screen automation is used.
