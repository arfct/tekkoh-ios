---
title: Tekkoh
date: 2026-11
category: product
tags:
  - ios
  - widget
url: https://tekkoh.com
links:
  app_store: https://apps.apple.com/app/id6832421132
  source: https://github.com/arfct/tekkoh-ios
media:
  - src: landing.png
    caption: The landing page at tekkoh.com, where a Duo spread sits beside the heading "One page for each day"
    alt: A cream grid-paper web page headed "One page for each day", beside a foldable phone showing a journal spread with a map and a column of writing
  - src: duo-spread.png
    caption: One day across the iPhone Duo's inside display, with the margin on the left page, the writing on the right and the fold between them
    alt: A two-page journal spread on grid paper; the left page has a large 8, a map of Kyoto with a dashed route, places, step counts and two photos, the right page a few paragraphs of writing
  - src: margin.png
    caption: The margin of one page, with the stamp of a 24-day streak, a map of the day's places and their arrival times, the step count and walking distance, and two photos
    alt: A phone-sized journal page with the date, a 24-day streak stamp, a map of Kyoto, three visited places with times, step count and two photo prints
credits: [dps]
---

After the Hobonichi Techo, Tekkoh gives each day one page of cream grid paper, on an iPhone. The writing is set on a 12-point grid, and the margin is filled in from the phone: the places visited that day and a map of them, the steps, distance and workouts from Apple Health, the times of sunrise and sunset, and photos from that day's camera roll.

On iPhone Duo the inside display opens a day as a two-page spread, shown in the second image, with the margin on the left page, the writing on the right and the fold on the spine. A vermillion hanko stamp on today's page gives the streak of days written. At 9:30 pm, if the page is still blank, a notification states the length of the streak and that it ends at midnight. The widget sets the weekday in kanji and the streak inside an ensō, which is pale until today's page is written and grey once the streak has ended.

Entries are encrypted on the phone with a key kept in the Keychain, and the server stores a copy it cannot read. A six-digit PIN restores the key on a new phone, and after ten wrong PINs the server wipes its locked copy of the key. The journal reads and writes offline; when two devices have changed the same day, their words are put one after the other with a divider between them. A web version and a command-line tool for personal agents use the same server. Version 1.0 is on the App Store, for iOS 27.1 or later.

Swift, SwiftUI, WidgetKit, with a Go server. 2026.
