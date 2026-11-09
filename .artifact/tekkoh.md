---
title: Tekkoh
date: 2026-11
category: product
tags:
  - ios
  - widget
  - security
  - open-source
url: https://tekkoh.com
links:
  source: https://github.com/arfct/tekkoh-ios
media:
  - src: landing.png
    caption: The landing page, with the Duo spread beside the promise of one page a day
    alt: A cream grid-paper web page headed "One page for each day", beside a foldable phone showing a journal spread with a map and a column of writing
  - src: duo-spread.png
    caption: A day on the iPhone Duo's inside display, margin left and writing right, the fold on the spine
    alt: A two-page journal spread on grid paper; the left page has a large 8, a map of Kyoto with a dashed route, places, step counts and two photos, the right page a few paragraphs of writing
  - src: margin.png
    caption: The margin of one page, with the day's places, movement and photos
    alt: A phone-sized journal page with the date, a 24-day streak stamp, a map of Kyoto, three visited places with times, step count and two photo prints
credits:
  - name: David Singleton
    url: https://github.com/dps
unconfirmed:
  - date
---

One page for each day. Tekkoh is a journal after the Hobonichi Techo: cream grid paper, a 12 pt grid for the words, and a margin where the day writes its own notes: the places you went, steps and workouts from Apple Health, sunrise and sunset, photos from that day's camera roll.

It is built for iPhone Duo, where the inside display opens as a two-page spread with the fold on the spine. The streak is a vermillion hanko stamp on today's page; a widget carries it to the Home Screen, Lock Screen and StandBy as a kanji date and an ensō that stays pale until the day is written.

Everything is encrypted on the phone with a key only you hold. The server keeps a copy it can't read, and a six-digit PIN brings the key back on a new phone. The journal reads and writes offline and syncs when the network returns. A web version and a command-line tool for personal agents share the same server. The app is not yet on the App Store.

Swift, SwiftUI, WidgetKit; Go server (arfct/tekkoh). 2026.
