# To Dos — Design

**Date:** 2026-11-04 · **Status:** approved in chat (approach A: visual rich-text notes)

## Intent
A lightweight to-do list inside the panel, so follow-ups from messages, mails and meetings don't get lost.

## Behaviour
- **Section** "To Dos" sits between Messages and Today. Header: title, count, **+** (new to-do), **show more / show less**.
- **Collapsed** (default): shows unchecked, not-snoozed to-dos. Height follows its content, capped at 30 % of the panel (45 % while a note is open). Messages and Today share the rest 2 : 1.
- **Expanded** (show more): the section takes 50 % of the panel; Messages and Today shrink to share the other half 2 : 1. Lists all to-dos (open first, then snoozed, then checked), with uncheck and a trash button per row.
- **Row:** checkbox (unchecked by default), one-line title, due badge, open-reference button when created from a card. Checking hides it from the collapsed view (it stays in the expanded list).
- **Clicking a row** opens it in place: an editable title, the note rendered with its formatting, and due/reschedule controls. Clicking the note switches to a 10-line rich editor with a toolbar: **Bold**, Underline, Color, Size, Link, List. "Done" leaves edit mode.
- **Due date:** optional. Due today: orange; overdue: red with a soft pulse-free glow; later: secondary.
- **Reschedule** uses the snooze options of notifications. A rescheduled to-do is hidden from the collapsed view until the time, then reappears; it is always listed when expanded.
- **"Create To Do"** in the right-click menu of every message, mail and meeting card. Title: Teams message text, mail subject, or meeting title. The to-do keeps a reference (kind + link) and opening it behaves like clicking the original card.
- **Animations:** spring for section resizing, row insert/remove, check/uncheck, opening notes, switching edit mode.

## Storage
`PersistedState.todos: [TodoItem]`. Notes are `AttributedString` encoded with the SwiftUI attribute scope (verified: bold, underline, colour, size and links survive a round trip). Old state files decode with an empty list.

## Calls made by me
- Lists are bullet characters ("• ") inserted at the start of the selected lines; there is no list attribute in rich text.
- Size choices: Small, Normal, Large, Title. Colours: red, orange, green, blue, purple, default.
- Reschedule hides only; it does not change the due date.
