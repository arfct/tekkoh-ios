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
    caption: The landing page at tekkoh.com, with a Duo spread beside the heading "One page for each day"
    alt: A cream grid-paper web page headed "One page for each day", beside a foldable phone showing a journal spread with a map and a column of writing
  - src: duo-spread.png
    caption: One day on the iPhone Duo's inside display, with the margin on the left page, the writing on the right and the fold between them
    alt: A two-page journal spread on grid paper; the left page has a large 8, a map of Kyoto with a dashed route, places, step counts and two photos, the right page a few paragraphs of writing
  - src: margin.png
    caption: The margin of one page, with a map of the day's places, their arrival times, the step count and walking distance, and two photos
    alt: A phone-sized journal page with the date, a 24-day streak stamp, a map of Kyoto, three visited places with times, step count and two photo prints
credits: [dps]
unconfirmed:
  - date
---

Tekkoh is a daily journal for iPhone, modelled on the Hobonichi Techo. It gives each day one page of cream grid paper, with the writing set on a 12-point grid. The margin of each page lists the places visited that day, the steps, distance and workouts from Apple Health, the times of sunrise and sunset, and photos from that day's camera roll.

On iPhone Duo the inside display shows a two-page spread, with the margin on the left, the writing on the right and the fold on the spine. A vermillion hanko stamp on today's page shows the streak of days written. A widget for the Home Screen, Lock Screen and StandBy shows the date, with the weekday in kanji, and the streak inside an ensō. The ensō is pale until today's page is written.

Entries are encrypted on the phone with a key kept in the Keychain, and the server stores a copy it cannot decrypt. A six-digit PIN restores the key on a new phone. The journal reads and writes offline and syncs when the network returns. A web version and a command-line tool for personal agents use the same server. The app has not been released; tekkoh.com reads "Coming to the App Store".

Swift, SwiftUI, WidgetKit, with a Go server. 2026.
