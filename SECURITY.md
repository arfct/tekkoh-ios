# Tekkoh security

Tekkoh is a journal, so the bar is simple: nobody but you should be able to
read it, including whoever runs the server. This document says exactly how
that's done, how to check it, and where it stops. It covers this app and its
server, [tekkoh-berth](https://github.com/dps/tekkoh-berth).

## What we claim

1. **The server can't read your journal.** Words, photos, captions, places,
   activity and sun times are encrypted on your phone before they're sent.
   The server, its database and its backups hold only ciphertext.
2. **Only your devices hold the key.** It lives in the iPhone Keychain and
   iCloud Keychain, never on the server in a form it can use.
3. **Your 6-digit PIN brings it back on a new phone.** Nobody watching the
   network, and nobody with a copy of the database alone, can test PINs.
   The server allows 10 wrong tries, slower and slower, then destroys its
   copy. *This claim is weaker than the other three: see
   [Where it stops](#where-it-stops).*
4. **Nobody else's account can read or change yours.**

## How

### Keys

Everything comes from one **journal key** `K`: 256 random bits, made on the
phone when you start a journal.

| Derived | How | Used for |
|---|---|---|
| Sign-in token | `HKDF-SHA256(K, info: "tekkoh/auth/v1")` | Authenticating requests. The server stores its SHA-256. |
| Entry id key | `HKDF-SHA256(K, info: "tekkoh/entry-id/v1")` | Naming a day's entry, `base64url(HMAC-SHA256(key, "day:" + date)[0..<24])`, so ids don't show dates. |
| Places key | `HKDF-SHA256(K, info: "tekkoh/local/places/v1")` | The location log kept on the phone. |

### Entries

Each day's page is one JSON document: words, photos with their keys and
captions, places, activity, sun, and a **version** that counts up with every
save. It's sealed with its **own random 256-bit key** `E`:

```
k = AES-256-GCM(K, E,    aad: "tekkoh/entry-key/" + id)
c = AES-256-GCM(E, JSON, aad: "tekkoh/entry/" + id)
envelope = {"v": 1, "k": k, "c": c}
```

Every seal uses a fresh random 96-bit nonce. The associated data binds an
envelope to its id, and on download the phone checks that the id matches
the day inside, so a server can't move a page to another date or swap two.

**The server can't roll a page back or erase it.** The phone ignores a
version older than the one it has and puts its own back. The app never
deletes a page, so the phone treats any deletion from the server as forged
and puts the page back.

### Photos

Each photo is re-encoded as JPEG (at most 2048 px), which drops EXIF and GPS
data, then sealed with its **own random key** `P`:
`AES-256-GCM(P, jpeg, aad: "tekkoh/photo/" + photoID)`. `P` is kept only
inside the encrypted entry, so a photo can be read only by someone who can
read its page. Photo ids are random.

### On the phone

The whole journal lives on the phone so it works offline. It's stored as the
same envelopes and sealed photos the server holds, so nothing is written in
the clear. Thumbnails exist only in memory. The sync state file holds ids
and revision numbers, not dates.

Files use iOS Data Protection (*complete until first user authentication*),
as does the Keychain item, so places can be recorded in the background.

Face ID can lock the app. Whether or not the lock is on, the app-switcher
snapshot shows blank paper.

**Signing out of a phone** removes the journal from that phone but leaves
`K` in iCloud Keychain, because deleting it there would delete it from every
device. **Deleting the journal** removes it from the server and from the
Keychain everywhere.

### The PIN

The PIN has to work on a new phone that has nothing but your username. A
6-digit PIN has only a million possibilities, so stretching alone can't
protect the key. Recovery needs the PIN **and** a secret the server keeps
outside its database (`TEKKOH_SECRET`).

On the phone, at sign-up or when the PIN changes:

```
salt     = 16 random bytes
S        = PBKDF2-HMAC-SHA256(PIN, salt, 600 000 rounds, 32 bytes)
verifier = HKDF-SHA256(S, info: "tekkoh/pin-verifier/v1")
W        = HKDF-SHA256(S, info: "tekkoh/pin-wrap/v1")
blob     = AES-256-GCM(W, K, aad: "tekkoh/recovery/" + username)
```

`verifier` and `blob` are each enough to try every PIN offline, so **they
never travel readable**. The phone sends them in a box to the server's own
X25519 key, which is built into the app:

```
k   = HKDF-SHA256(X25519(eph, server), salt: eph ‖ server, info: "tekkoh/transport/v1/" + purpose)
box = AES-256-GCM(k, JSON, aad: purpose)       (a reply uses the same k, aad purpose + "/reply")
```

Each box is opened only inside the server process. Cloudflare's edge, which
ends TLS, sees only boxes. The server's key pair is derived from
`TEKKOH_SECRET`, and `GET /v1/transport-key` shows the public half.

The server stores:

```
MAC    = HMAC-SHA256(HKDF(SECRET, "tekkoh/verifier/v1"), username ‖ 0x00 ‖ verifier)
sealed = AES-256-GCM(HKDF(SECRET, "tekkoh/seal/v1/" + username), blob, aad: username)
```

To recover, the new phone fetches the salt, stretches the PIN, and sends the
boxed verifier. The server compares MACs in constant time under a row lock.

- **Right PIN:** the server returns the blob, boxed back, and the phone opens
  it with `W`. `W` never leaves the phone, so the server never holds `K` in a
  form it can use.
- **Wrong PIN:** the server counts it.

Limits on wrong PINs:

- **Backoff.** After the third wrong PIN, each further try must wait longer:
  1, 2, 4… up to 64 minutes. Ten tries take at least two hours.
- **Ten wrong PINs delete the stored key.** After that, only a device that
  still has `K` can open the journal. The app notices on its next launch and
  asks for a new PIN.
- **Rate limits.** Requests are limited per IP address, grouped by /64 for
  IPv6. Failed recoveries are also capped at 200 an hour across every
  account, so trying a few common PINs against many usernames runs out
  quickly.
- **Usernames can't be listed.** A username that doesn't exist gets the same
  answers as one that does: a stable fake salt and the same countdown.
- **The app refuses obvious PINs:**
  - repeats such as 111111;
  - runs such as 123456 or 890123;
  - repeated patterns such as 121212, 123123 or 123321;
  - keypad shapes;
  - the most common choices.

### Signing in

Requests carry `Authorization: Tekkoh <username> <token>`. The server stores
`SHA-256(token)` and compares in constant time. The token is derived one-way
from `K`, so it reveals nothing about the key. Berth's proxy redacts the
token from its logs: every logged request shows `"Authorization":["REDACTED"]`.

## The web app

[tekkoh-web.cronbon.com](https://tekkoh-web.cronbon.com) is the same
journal in a browser. Its code is in tekkoh-berth's `web/`. It uses the
same pages, crypto, merge rules and sync, through WebCrypto. The journal
key is held as non-extractable `CryptoKey`s, so even the page's own script
can use it but not read it out. Pages and photos are stored sealed in
IndexedDB, so the journal reads and writes offline.

**Linking a browser** needs your username, your PIN and your phone, and
all three must be the same journal's:

1. The browser asks for your username and PIN. It unlocks the journal key
   through the ordinary recovery path described above, with its boxed
   fields and its attempt limit, backoff and wipe.
2. It makes a one-time X25519 key pair, opens a five-minute slot on the
   server, and shows a QR code holding the slot and the public key, plus
   six digits.
3. In Settings, Link a browser, your phone scans the code and shows the
   same six digits. It then puts `{username, key}` in the slot, sealed to
   the browser's public key, so the server only ever holds the sealed box.
4. The browser opens the box and links only if:
   - the username matches;
   - the key from the phone is byte-for-byte the key the PIN unlocked.
5. It then gets its own **session token**. The server stores its hash, and
   the phone lists linked browsers and can sign any of them out. A session
   can read and write pages and photos, but can't change the PIN, delete
   the journal, or link and list browsers. A browser finds out it's been
   signed out on its next visit and wipes its copy.

**What the phone adds, honestly.** Matching the phone guarantees you've
linked the journal you meant to. It isn't a second lock: anyone with your
username and PIN could get the key through the recovery path directly, as
a new phone does. The protection against that is the PIN's attempt limit.

**The web is weaker than the app.** On a phone, the app you installed is
fixed. A web page is sent afresh on every visit, so whoever controls
tekkoh-web, or Cloudflare in front of it, could serve a version that sends
your key or your pages elsewhere. For the web, "the server can't read
your journal" becomes "the server promises not to". Every web-based
end-to-end encrypted service shares this. What's done about it:

- **A separate origin.** The app is served from its own origin, apart from
  the API, as static files with no build step, so what runs is what's in
  the repo.
- **A strict Content-Security-Policy.** Only that origin's own scripts run,
  with no inline code. The page may connect only to the API. It can't be
  framed, and it sends no referrer.
- **No outside code.** The one third-party script (a QR code generator,
  qrcode-generator 1.4.4, MIT) is vendored and makes no network calls.
- **A browser can't do lasting damage on its own.** A linked browser can't
  change the PIN or delete the journal, and the phone can revoke it.

A signed-out browser can't reach the server, but one that had been
tampered with could have kept a copy of the key. Signing out is a
convenience, not a defence against a compromised browser.

## How to check

All of these run from the repos, against the live server.

- **`Checks/run.sh`** checks:
  - the crypto: round trips, wrong keys failing, ciphertext that can't move
    between days, PIN verifier and unlock;
  - the PIN policy, the merge rules, version ordering, streaks and sun times;
  - a full cycle against the live server: sign-up with recovery fields
    boxed, a wrong PIN counting down, the right PIN returning the identical
    key through a boxed reply, encrypted sync, stale writes refused, and the
    account deleted.
- **`Checks/canary.sh`** runs on the server's Mac:
  1. It writes a page, a caption, a place and a photo, all full of a unique
     marker, through the app's own code.
  2. It searches for the marker in a fresh database dump (as SQL, with
     binary columns as hex) and in the server's and proxy's logs. It looks
     for the marker as text, as hex, and as base64 in all three alignments.

  Last run: not found in a 188-line dump or in 17,621 lines of logs.
- **The server's tests** (`go test ./...` in tekkoh-berth; set
  `TEKKOH_TEST_DATABASE_URL` to run them against Postgres too) check:
  - recovery material never appears in a request body;
  - boxes can't be tampered with or reused for another purpose;
  - the 10-try wipe and the backoff;
  - unknown usernames look like real ones;
  - a database with a different secret can't check a PIN or open a stored
    key;
  - accounts can't see each other's pages, and each journal numbers its own
    changes;
  - revisions;
  - a made-up `X-Forwarded-For` can't dodge the rate limit.
- **The web app's tests** (in tekkoh-berth, run with Node 22):
  - `web/tests/vectors.mjs` checks the browser crypto against vectors the
    app's Swift code made: the sign-in token, entry ids, sealed pages and
    photos, PIN stretching and unlocking, the linking box and the
    six-digit code. Then the Swift opens a page the browser sealed.
  - `web/tests/live.mjs` links a browser to a throwaway journal on the live
    server, playing the phone's part. It checks that:
    - a wrong PIN is refused;
    - the slot is collected only once;
    - a different journal's phone doesn't match;
    - a session can write pages but can't delete the journal;
    - a browser can sign itself out;
    - pages merge as they do in the app.
- **Watch the wire yourself.** Put the phone behind a TLS-intercepting proxy,
  such as mitmproxy with its certificate trusted on the device. Every body
  should be a page envelope, opaque photo bytes, or an `{eph, box}` pair:
  nothing readable, no PIN, no key.

## Where it stops

Read this part.

- **The PIN doesn't protect against the server's full state.** Someone who
  has both the database and `TEKKOH_SECRET` can try all million PINs offline.
  That means the live server, or a backup of it. Berth's backups hold both:
  - the local archive from `berth backup` holds them unencrypted;
  - the nightly off-Mac backup holds them encrypted.

  With 600,000 PBKDF2 rounds, one guess takes about 0.1 s on one core of a
  current Mac, and a GPU is far faster. So expect minutes to hours, not
  years. Only hardware that enforces the attempt limit (as Apple's and
  Signal's key escrow do) can fix this for a 6-digit PIN. Short of that, a
  memory-hard stretch (Argon2id) would slow GPUs down, and a long recovery
  phrase instead of a PIN would make the guessing hopeless.
- **The app you run is the root of trust.** A build that sent `K` somewhere
  would defeat all of this. iOS gives no way to confirm that an App Store
  binary was built from this source; building it yourself is the only way to
  be sure.
- **The server sees metadata:**
  - your username;
  - when you sync, and from which IP address (the proxy logs addresses and
    request paths, but not tokens or bodies);
  - how many pages and photos you have, and their sizes.

  Entry ids don't reveal dates, but a page is usually first uploaded on its
  own day, so the timing of uploads shows roughly which days you wrote.
  Page sizes aren't padded.
- **Someone else can wipe your PIN recovery.** Ten wrong guesses at your
  username delete the server's copy. The backoff stretches that to hours.
  Your journal is unaffected, and the app asks you to set a new PIN.
- **Your sign-in token never changes.** Anyone who obtained it could
  overwrite or delete your pages and photos on the server, but not read them.
  Your phone would put back any page it still has. Changing the token means
  changing the journal key.
- **Apple:**
  - your devices share `K` through iCloud Keychain, which Apple encrypts end
    to end;
  - place names come from Apple Maps, so the coordinates of places you visit
    go to Apple (not to Tekkoh) to be named.
- **Your phone:** once you've unlocked it after a restart, its data is
  readable to anyone holding it unlocked, and to malware on it. The Face ID
  lock hides the app's pages from someone who picks up your unlocked phone;
  it doesn't add encryption.
- **No formal proof or outside audit yet.** One independent review has been
  done (below). The recovery protocol is small enough to model in ProVerif
  or Tamarin. A cryptographer should read `Tekkoh/Core/Crypto.swift`,
  `Transport.swift`, `Journal.swift` and the server's `server.go` and
  `transport.go` before anyone trusts this with something that matters.

## Review history

**November 2026: an independent review of both repos.** Its findings, and
what's been done about each:

| Finding | Status |
|---|---|
| The PIN verifier and PIN-locked key travelled in plain request bodies, so Cloudflare, a proxy or the operator could test every PIN offline | **Fixed:** they're boxed to the server's built-in key. PINs set before the fix should be changed, and the app asks. |
| Common PINs could be tried against many usernames, and usernames could be listed | **Fixed:** obvious PINs are refused, failures have a global cap, unknown usernames look real, and rate limits use /64. |
| Anyone could silently wipe someone's recovery | **Mitigated:** backoff makes it hours, and the app asks for a new PIN when it happens. |
| Signing out deleted the key from every device through iCloud Keychain | **Fixed** |
| Rate limits trusted a client-supplied `X-Forwarded-For` | **Fixed** (a client on the same LAN as the server can still choose its own) |
| No quotas or body timeouts | **Fixed** |
| The server could roll back or erase a page | **Fixed:** a version inside the encryption, and deletions ignored |
| One change sequence across all accounts showed how much others wrote | **Fixed:** numbered per journal |
| Usernames in recovery requests went into proxy logs | **Fixed:** sent in the body |
| Dates stored in plain text in the sync state file on the phone | **Fixed** |
| The phone accepted any PIN-stretching settings the server sent | **Fixed:** at least 600,000 rounds and a 16-byte salt |
| The app-switcher snapshot could show a page | **Fixed** |
| Failed photo deletions were dropped from the queue | **Fixed** |
| Background sync could run a second copy of the journal | **Fixed** |
| Brute force by whoever holds the server's full state | **Open**, by design (see above) |

## Reporting a problem

Please open a private security advisory on this repository rather than a
public issue.
