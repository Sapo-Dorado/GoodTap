Complete these todos: one by one. Plan carefully before proceeding.

1.  Improve the deck importer field / card search:
    a. We should support multiple printings. This will involve downloading from the full art version of scryfall https://data.scryfall.io/unique-artwork/unique-artwork-20260306100348.json. take a look at some examples here to understand how to select printing by set.
    b. Example input from moxfield with printings:
    1 Azorius Guildgate (RNA) 244
    4 Basilisk Gate (CLB) 346
    4 Brainstorm (DSC) 113
    4 Citadel Gate (PLST) CLB-349
    4 Counterspell (DSC) 114
    1 Guardian of the Guildpact (DIS) 10
    2 Heap Gate (CLB) 354
    1 Idyllic Beachfront (DMU) 249
    4 Island (SCD) 339
    4 Journey to Nowhere (CMD) 17
    4 Lórien Revealed (LTR) 60
    3 Outlaw Medic (OTJ) 23
    4 Prismatic Strands (C19) 69
    4 Sacred Cat (AKH) 27
    4 Sea Gate (CLB) 359
    2 Spell Pierce (DFT) 64
    4 Squadron Hawk (A25) 34
    4 The Modern Age / Vector Glider (NEO) 66
    2 Thraben Charm (MH3) 45

        SIDEBOARD:
        2 Arms of Hadar (CLB) 113
        4 Blue Elemental Blast (A25) 43
        2 Dispel (RTR) 36
        3 Dust to Dust (ME4) 11
        4 Red Elemental Blast (A25) 147

    c. Remember the previous logic that you added to search for cards before the / when resolving cards. Even for these cases we still need to process the printing
    d. We should allow people to modify the decks. There should be a way where you can click on the number and modify the amount (no popup just text over the number when you click it). Also an x button to remove the card entirely and right click menu to move between main deck and side board. To add a new card we can leverage a similar card search to what's used in the add token in the game board, for this it should just include no tokens. we should be able to click add card on both the main deck and sideboard
    e. we should improve this card search functionality (feel free to refactor to keep it clean now that we use it in different places). This card search should have a dropdown that lets you select which printing you want of the card. the preview should show the currently selected printing. Also let's show 20 cards that match instead of 15 and at the bottom say showing x out of y where x is the number of cards shown and y is the total number of cards that match the search.
    i. This token search doesn't work for double faced tokens update your logic for is_token to include double faced tokens take a look at undercity in the json for an example of this type of token
    f. There should be a dropdown at the top that lets you swap between seeing card list and seeing previews of the cards (in preview mode lets include the swap printings dropdown.)

2.  Lets support commanders. When editing the deck there should be another option in the right click menu (in addition to move to deck/sideboard) that says set as commander. this will swap the card with your current commander if there is one, otherwise it will make the card your commander. Commander section should only be shown when viewing the deck if there is a commander for the deck. when loading into a game if the deck has a commander, put it on the battlefield as part of loading (its not in the deck itself)
3.  When ending the game there should be an option to play again with sideboarding in addition to deleting the game. For sideboarding we should open a popup that has the deck and sideboard side by side and lets you swap cards between deck and sideboard. We should be able to swap some number of a single card not just the full set of that card. There will be a submit button and once both players submit their sideboard options the next game will start with the updated decks
4.  We need to decide who goes first for the first time we load into the game (not after sideboarding just the first time). This can be implemented by each player rolling 2 dice (two random numbers 1-6) then add them and put this result in the log. There should also be a modal at the beginning indicating who won the die roll.
5.  On the battlefield we should be able to see graveyard, exile and hand (back of cards) for the opponent too. Make it look like your side of the field. clicking should be on these zones rather than the word labels (same as your side)
6.  There is a glitch when dropping a card on the opponent's battlefield. We need to:
    a. make sure the card doesn't disappear when dropped in an invalid location
    b. allow players to drop cards on their opponents side of the field.
    c. Allow players to copy their opponents cards (allow for opponent cards can be its own category of action enablement. For now it should just let you copy)
7.  there is a bug where if you click an increment button too fast it doesn't register. We should make sure that each click of the button actually increments the count.
8.  The create game shouldn't allow creating games when you already have 10 games created. it should be greyed out with a message when you hover it if you have 10 games. There should also be an x button for each game on that screen that will allow you to delete the game with a modal confirming.
9.  I want to update the game join page to update when the oponnent opens the link it should show up on your side immediately
