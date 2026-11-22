# Word Duel

1v1 word-chain duel on a chess clock. Built from `Roblox Word Ladder Monetization.pdf`.

## Build and open

```bash
python3 build.py
```

Then open `WordDuel.rbxlx` in Roblox Studio and press Play.
Edit code in `src/`, not in Studio. Studio edits are overwritten on the next build.

## Layout

| Path | What |
|---|---|
| `src/ReplicatedStorage/Shared/Config.lua` | All tuning: clock, rewards, items, product ids, achievements |
| `src/ServerScriptService/Server/Match.lua` | Turn rules, clock, deadlock breaker, items, bot |
| `src/ServerScriptService/Server/Lobby.lua` | Level-bracket queue, King of the Table, friend tables, results/Elo |
| `src/ServerScriptService/Server/PlayerData.lua` | DataStore profile, XP, achievements, daily chest |
| `src/ServerScriptService/Server/Shop.lua` | Robux products, coin shop, belt, referrals |
| `src/StarterPlayer/StarterPlayerScripts/ClientMain.client.lua` | All UI |
| `src/ServerStorage/Words/` | Generated dictionary (do not edit; use `words_extra.txt` / `words_block.txt`) |

## Before publishing

1. Publish the place. In Game Settings > Security, turn on **Enable Studio Access to API Services**. Without it, nothing saves.
2. Create each Developer Product on the Creator Dashboard. Paste its id into `Config.Products`. Products with `id = 0` are free in Studio and disabled live.
3. The dictionary is Webster's 2nd (1934) plus generated `-s` forms. It has obscure words and some fake plurals. Swap in a better list with `python3 build.py --words list.txt`.
