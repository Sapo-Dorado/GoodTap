# Architecture Overview

This application should be constructed using Phoenix LiveView. Each user will
sign in using a username and password. This can just use the standard auth
generator provided by Phoenix.

## Pages

### Home Page (not signed in)

For now this should just have "Goodtap.in" in big text centered vertically
and horizontally

Under this text there should be a button that says Get Started! Which links to the
sign up page. This button should have a gradient and an animation when you hover over it.

### Home Page (Signed In)

There should be a list of active Games that the user is participating in.

At the top there should be a button to start a new game. When clicking this
button a new game should be generated and redirect to create game page.

### Create game page

there should be a setup screen to
select your deck and a link to invite your opponent. There should be a button to
copy this link to your clipboard.

There should be an indicator of whether your opponent has joined yet. When someone
clicks on the link they should show up as joined and once both players have selected
their deck the game should start. (this should use liveview to update in real time)

You can change your deck if the game hasn't started yet

### Sign Up / Login Pages

These can be basic for now

### Decks Page

This should have a list of decks that the user has created. When creating a deck the user
should be prompted to enter a link to their deck on Moxfield. Example (https://moxfield.com/decks/BwyK3VoaMUGqPvLprW5kUw)

<claude-note>For now this is the only flow that will be supported, but more will be added in the feature so keep the moxfield logic isolated
so other ways can be easily added in the future</claude-note>

### Game Page

The game will be very similar to untap.in. Each player will have a deck, a hand, a battlefield (majority of their space)
, a graveyard, an exile pile, and info which includes their life total
(this should also have the option to add an additional tracker, when adding a tracker let the player type the name of what they are tracking)

The life total and trackers should have + and - icons to adjust tbeir value and pressing shift while clicking either button does an increment of 5

The basic flow will be moving cards between hand, deck, battlefield, graveyard and exile.

When cards are in hand they can be dragged to the battlefield, deck, graveyard, exile, or back to hand. If the card is close to a zone (other than the battlefield) a ghost version of the card should appear in that zone and if the player drops the card it will go to that zone. For the battlefield if the player drops a card anywhere it should stay there.

When clicking on the deck, graveyard, exile there should be a pop up area at the bottom of the screen with an x on the top corner. This should show all the cards in the zone side by side and cards can be dragged out of the zone. If the card is not "known" to the player (in opponent's hand or in either deck if the card hasn't been seen) it should appear face down.

There should also be an end game button. When clicking it there should be a modal warning that the game won't be saved. If they confirm then delete the game and redirect both players to home

## Actions

In the game page the following actions should be available. I will provide a hotkey for each action, in addition to the hotkey, if the player right clicks
in a place where the action would be valid, the valid actions (and the corresponding hotkeys) will be shown in a menu to select.

Note: hotkeys will eventually be customizable so resolving their value should be an isolated component

Note: if something is valid for the top of the deck the menu that pops up should say (top of deck)

Tap
Hotkey: space
Valid for: card on battlefield
Effect: Card is rotated 90 degrees clockwise (if the card is already "tapped" go back to upright so this is a toggle)

Move to Graveyard
Hotkey: D
Valid for: card in hand, top card of deck, card in exile, card on battlefield
Effect: puts the card in the graveyard

Move to Exile
Hotkey: S
Valid for: card in hand, top card of deck, card in graveyard, card on battlefield
Effect: puts the card in exile

Flip Card
See /Users/nicholas/Documents/Stuff/Pauperfall/pauperfall for guidance on how to handle double faced cards
Hotkey: F
Valid for: card in hand, card on battlefield
If the card is single sided, toggle between main face and back, while the card is being dragged if it is face down only the back should be visible
For double faced cards toggle between front and back face
If the card enters graveyard, or exile this state is removed

Scry
No hotkey
Valid for: deck
User must specify a number then that many cards from the top of the deck will appear in a popup window. For each card the player can right click on it and send it to the top of the deck or the bottom or to graveyard or to exile

Draw
hotkey: numbers 1-9
Valid for: deck
Draws that number of cards to the players hand

Shuffle
Hotkey: V
Valid for deck
Shuffles the deck in a random order

Add counter
Hotkey: U
Cards on battlefield
This should add a "counter" to the card starting at 0 with a + and a - button (same rules as other counters like life total). Cards can have up to three types of counters.

Copy Card
Hotkey: K
Cards on battlefield
Make a "token" copy of the card, it should look the same but will vanish if put somewhere outside of the battlefield

Create token
hotkey W
valid for: clicking on battlefield
Will pop up a search window that allows you to type in a keyword and there should be an option to filter by tokens (these are a type of card from the json).
Creates a "token" copy of the card or token. see token rules above

## Cards

MTG_Cards.json contains all of the card info we need lets put this with the db seed file and load the relevant info from the cards into the database.
Store:

- Card Name
- Full Json entry for that card

When displaying a card, the image should be the the whole thing (aspect ratio 1.4/1) if the card is face up
If the card is face down (or in the opponent's hand) there should be a standard card back that is identical for all cards visible

## Database structure

Decks

- Name (string name of deck)
- owner (player id)
- cards (list of card ids)

Players (this will be generated by auth generator)

Games

- Host (player id who created the game)
- Opponent (player who joined can be null if a player hasn't joined yet)
- Game State (this should be an encoded version of the full game state this needs to include the positions of the cards on the battlefield to preserve state)
