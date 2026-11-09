# Tekkoh for iPhone

A daily journal, after the Hobonichi Techo: one page a day on cream grid
paper, the day's places, movement and photos in the margin, and a streak you
keep by writing every day. Built for iPhone and for iPhone Duo, where the
inside display opens it as a two-page spread.

Everything is encrypted on the phone with a key only you hold. The server
([tekkoh-berth](https://github.com/dps/tekkoh-berth)) keeps a copy it can't
read: a backup, and the way between your devices.

## What's on a page

- **Words**, on a 12 pt grid, saved as you type.
- **Places**: Core Location visits and significant moves, kept on the phone
  (encrypted) and named with MapKit, with a quiet map on the spread.
- **Movement** from Apple Health: steps, distance, flights, workouts.
- **Sunrise and sunset**, worked out on the phone for where you were.
- **Photos**: suggested from that day's camera roll, or picked; captions
  typed under each print; × to take one out.
- **The streak**: a vermillion hanko stamp on today's page, and the month
  index marks every day written. At 9:30 pm, if today is blank, a local
  notification says how long the streak is and that it ends at midnight.

## Layouts

| | |
|---|---|
| iPhone, Duo outside display | one page: date, margin notes, writing, photos |
| Duo inside, open flat or as a book | a spread: margin (date, map, places, movement, photos) left, writing right, the fold on the spine |
| Duo tabletop | writing on the raised half, the margin lying flat |

The fold comes from SwiftUI's `reservedRegions(kind: .division)`.

## Widget

**Today** (`Widget/`) shows the date and the streak.

| Size | What it shows |
|---|---|
| Small | the weekday in kanji, the day's number, the month, and the streak inside the ensō |
| Medium | the same as a spread: the date on the left, the streak inside an ensō on the right, the last seven days as beads |
| Lock Screen (circular, rectangular, inline) | the streak, with the date where there's room |
| StandBy | the small size |

The ensō stays pale until today's page is written. It turns grey once the streak has ended.

The app writes a small summary to the app group `group.io.singleton.tekkoh` on every save and sync: the streak and which recent days have a page, with no content. The widget rolls itself over at midnight. `Shared/` holds the code used by both the app and the widget.

## Agents

A personal agent can use the journal through the `tekkoh` command-line tool
(in tekkoh-berth, `cmd/tekkoh`). The agent sends you a one-time link
(`https://tekkoh.com/link#…`), which opens Tekkoh to approve it with
Face ID: no PIN is typed anywhere. (In a terminal, `tekkoh link --pin`
links as a browser does instead: username, PIN, and a code to scan.)
The app handles the link as a Universal Link (`applinks:tekkoh.com`) and as
`tekkoh://link#…`, both in `Linking.parse(url:)`. It can then read
and write, and leave a note on a day saying what it did for you. The note
shows in the margin, in indigo, apart from your own words. Linked agents
are listed in Settings with the browsers, and each can be signed out
there. See SECURITY.md before linking one.

## Offline first

The whole journal lives on the phone, sealed exactly as the server holds it,
so it reads and writes on a plane. Changes queue and sync when the network
returns (an `NWPathMonitor` and background refresh). If two devices change
the same day, their words are put one after the other with a divider rather
than merged; photos and places are combined; a removed photo stays removed.

## Keys

- A random 256-bit **journal key** in the Keychain, synced by iCloud
  Keychain to your own devices, readable after first unlock so places can
  be recorded in the background.
- **Each entry** sealed with its own AES-GCM key, itself sealed with the
  journal key; entry ids are an HMAC of the day, so they don't show dates
  (though when a page is uploaded roughly does).
- **Each photo** sealed with its own key, kept in its entry.
- **Signing in**: a token derived from the journal key (HKDF).
- **Your 6-digit PIN** brings the key back on a new phone. It's stretched
  (PBKDF2-SHA256, 600,000 rounds) into a verifier and a wrapping key; the
  server checks the verifier against an HMAC under a secret it keeps outside
  its database, releases the locked key only for the right PIN, and wipes it
  after 10 wrong ones. The verifier and locked key travel boxed to the
  server's built-in X25519 key, never readable on the way.

The same journal is on the web at
[tekkoh-web.cronbon.com](https://tekkoh-web.cronbon.com) (code in
tekkoh-berth's `web/`), linked from the phone in Settings, Link a browser.

[SECURITY.md](SECURITY.md) has the full design, how to check it, an
independent review's findings, and where the protection stops.

Usernames, not emails: there's nothing else to give.

## Building

Open `Tekkoh.xcodeproj` (Xcode 27, iOS 27.1+), or:

```sh
xcodebuild -project Tekkoh.xcodeproj -scheme Tekkoh -destination 'id=<device>' -allowProvisioningUpdates build
```

`Checks/run.sh` checks the crypto, merging, streaks and sun times on the
Mac, and the account, recovery and sync cycle against the live server with
a throwaway account.
