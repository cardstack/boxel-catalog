import { CardDef } from 'https://cardstack.com/base/card-api';
import { Component } from 'https://cardstack.com/base/card-api';
export class Blank extends CardDef {
  static displayName = "blank";
}
//Make me a Deck Card, here are the details:
//	1	Edit mode: User can add any card from Boxel into the Deck Card via a field to select it. For now I'm not sure if this is a containsMany or a linksToMany, as while I need users to select a card from the workspace (linksToMany) I only need the data being displayed in Isolated View (containsMany).
//	2	Isolated View: Make a deck out of all cards added in Edit Mode, show the deck and have the totals below the deck, clicking the deck draws the top card of the deck, revealing the card in a Fitted format.
//	3	Have a button to shuffle the deck.
//	4	The Deck Card should store the sequence of the cards in the deck sequentially, so if there are 5 cards, have some way to record the data so that we know the position of each card
//	5	Users can have duplicates of the same card but the Deck Card must identify them uniquely (e.g: if added 2 "Author" cards in a total of 5 cards in deck at the top and the bottom, the Deck Card needs to know that "Author" at the top is different from "Author" at the bottom.
//The purpose of this card is to create a flexible component that will let users use Cards in workspace with code that recognizes card sequences.
