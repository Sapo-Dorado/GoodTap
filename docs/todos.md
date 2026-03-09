It is time to implement a new feature. This will require a significant refactor so come up with a comprehensive plan first.
Write it down then start implementing, marking off items as you complete them.

We will be adding multiplayer support:

# Starting a game

In the game creation page the host will have the option of updating the max number of players.
This defaults to 2. Players can join using the link until the max number of players are reached.
If a player tries to join when the lobby is full they should be sent back to the home page with a warning
about the lobby being full.

# Battlefield changes

The battlefield should look the same in that you only see one opponent's battlefield at a time. when there are more players
there should be a selector to toggle between which opponent's battlefield you are seeing. When you are looking at an opponent you will
see their health deck, hand, etc just like normal.

The toggle button for each opponent should show some stats about them which include their health and custom tags that they have on them

## Most significant difference

Now we treat the whole battlefield as a single grid. We need to adjust the logic a little bit when placing a card on an opponent's battlefield
If the card is centered on the opponent's battlefield we will need to track which oppoonent's battlefield it is on and only render it when
that opponent is the opponent that we are currently viewing. Note that this should also show when someone else is viewing that opponent's battlefield

# Other things

Now we can't just think about host and opponent since there are other players we will have to track them by player number. this will require some significant code refactor but the logic should be very similar

Things like die roll need to be adjusted for more players (we may have to make the modal have multiple rows of rolls when players exceed 2)
