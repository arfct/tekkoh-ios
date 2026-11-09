---
title: Tekkoh
date: 2026-11
category: product
tags:
  - ios
  - widget
url: https://tekkoh.com
links:
  source: https://github.com/arfct/tekkoh-ios
media:
  - src: landing.png
    caption: The landing page, with the Duo spread beside the heading "One page for each day"
    alt: A cream grid-paper web page headed "One page for each day", beside a foldable phone showing a journal spread with a map and a column of writing
  - src: duo-spread.png
    caption: A day on the iPhone Duo's inside display, margin left and writing right, the fold on the spine
    alt: A two-page journal spread on grid paper; the left page has a large 8, a map of Kyoto with a dashed route, places, step counts and two photos, the right page a few paragraphs of writing
  - src: margin.png
    caption: The margin of one page, with the day's places, movement and photos
    alt: A phone-sized journal page with the date, a 24-day streak stamp, a map of Kyoto, three visited places with times, step count and two photo prints
credits: [dps]
unconfirmed:
  - date
---

Tekkoh is a daily journal for iPhone, modelled on the Hobonichi Techo: one page for each day, on cream grid paper with a 12 pt grid. A margin on each page fills in with the places visited that day, steps and workouts from Apple Health, sunrise and sunset, and photos from that day's camera roll.

It is built for iPhone Duo, where the inside display opens as a two-page spread with the fold on the spine. A vermillion hanko stamp on today's page shows the streak. A widget shows the date as kanji and an ensō on the Home Screen, Lock Screen and StandBy; the ensō stays pale until the day's page is written.

Entries are encrypted on the phone with a key held only by the user. The server stores a copy it cannot decrypt, and a six-digit PIN restores the key on a new phone. The journal reads and writes offline and syncs when the network returns. A web version and a command-line tool for personal agents use the same server. The app is not yet on the App Store.

Swift, SwiftUI, WidgetKit; Go server (arfct/tekkoh). 2026.
