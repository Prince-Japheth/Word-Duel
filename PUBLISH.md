# Publishing Word Duel

These are the steps that need your Roblox account. Everything else is built and tested in Studio.

## 1. Publish (private first)
1. Open `WordDuel.rbxlx` in Studio.
2. File > Publish to Roblox. Keep the experience **Private** for now.
3. Game Settings > Security: turn on **Enable Studio Access to API Services**. Saving and leaderboards then work in Studio too.

## 2. Create the Robux products
Creator Dashboard > your experience > Monetization > Developer Products. Create one product per row below, then paste each product's ID into the `id = 0` field of the matching row in `src/ReplicatedStorage/Shared/Config.lua` (`Config.Products`). Then run `python3 build.py` and reopen the place, or ask Claude to push the change into Studio.

| key     | Name            | Price (R$) |
|---------|-----------------|-----------:|
| Help3   | 3 Helps         | 49   |
| Help10  | 10 Helps        | 129  |
| Skip3   | 3 Skips         | 49   |
| Time5   | 5 More Time     | 49   |
| Double1 | 1 Double-Shift  | 79   |
| Double5 | 5 Double-Shifts | 299  |
| Slot2   | Belt Slot 2     | 399  |
| Slot3   | Belt Slot 3     | 899  |
| Slot4   | Belt Slot 4     | 1499 |

While a product still has `id = 0`, a live server shows it as **SOON** and blocks it. Studio grants it for free so you can test.

## 3. Test with real servers
- Start a test purchase in Studio. Studio purchases are free test purchases and don't charge Robux.
- Test > Clients and Servers > 2 players. Play ranked, King of the Table and a friend table between the two windows.
- Leave and rejoin the published game to confirm your coins, level and items saved.
- Play on a phone: the on-screen letter keyboard replaces the system keyboard.

## 4. Store page and rating
- Fill in the **Experience Questionnaire** (Creator Dashboard > Audience). It's required for the age rating.
- Upload an icon (512x512) and 2 to 3 thumbnails (1920x1080). Screenshots of the lobby and a match work well.
- Write a description, e.g. *"1v1 word duel on a chess clock. Change one letter, make a real word, beat the clock."*

## 5. Go public
Set the experience to Public. Watch the first sessions for crude or archaic words that get through, and add them to `words_block.txt`.

## Studio test hooks
`ServerStorage.WordDuelTest` exists only in Studio. In a live game it does nothing, and it's what the automated tests drive.
