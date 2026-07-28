# Using Aggie GPA with Siri

Last updated: 2026-07-23

## What currently works

On the tested iPhone 17 Pro running iOS 27 beta, this exact request is verified:

> View assignments in Aggie GPA

Siri can show an Aggie GPA card with assignments due in the next seven days. The real-device test displayed `Homework 3` for `CHE 002A` and its due date.

You do **not** need to open the Shortcuts app or create a Shortcut. Aggie GPA registers the phrase automatically. iOS may still display wording such as “Running your Shortcut”; that is the system's label for the automatic App Shortcut route.

## Setup

1. Open Aggie GPA once after installing or updating it.
2. In Aggie GPA, open Settings → Siri AI.
3. Turn on **Enable Siri Access**.
4. Turn on **Allow Assignment Summaries** for the verified assignment request.
5. In iOS Settings → Apps → Aggie GPA, allow Siri/Apple Intelligence learning and Search content if you want system discovery.
6. Make sure Siri is enabled and the selected Siri language matches the phrase you use.

Detailed scores, GPA answers, and draft creation have separate switches because they expose more sensitive information. Leave any category off if you do not want Siri to access it.

## Expected result

For the verified phrase, Siri should display an Aggie GPA-branded card. A successful card contains the assignment title, course code, and due date. If Aggie GPA has no assignment due in the window, it should return an explicit empty result after the app intent runs.

If Siri says it cannot find assignments or cannot search inside the app, that may be a system fallback. It is not proof that Aggie GPA returned an empty list.

## Search and open status

Aggie GPA courses are indexed for iOS Search. Searching Spotlight for `CHE 002A` showed the real course result on the test device.

Direct native Siri commands such as `Search Aggie GPA for CHE 002A` and `Open CHE 002A in Aggie GPA` did not execute the app's native search/open code on the tested iOS 27 beta. They should be treated as unavailable until a later device test verifies them.

## Privacy

- Assignment summaries use a small local snapshot shared only with Aggie GPA's signed processes.
- Course/assignment discovery metadata may appear in iOS Search.
- Grades and GPA require their own permission switches and local authentication.
- Siri write requests create a draft; you must confirm inside Aggie GPA before anything is saved.
- Projected values never overwrite official grades.

## Troubleshooting

- Use the exact verified phrase first.
- Open Aggie GPA once and wait briefly so it can refresh Siri registration and indexing.
- Check Aggie GPA's Siri AI settings and iOS Siri/Search permissions.
- If Siri reports a connection problem, check the network or VPN. The successful test used VPN off.
- After an app or iOS beta update, restart the iPhone, open Aggie GPA, and try again.
- Do not delete/reinstall the app merely to refresh Siri; use an update install so existing student data is preserved.

The current iOS 27 SDK does not provide an education/grade/GPA App Schema, so broader grade and GPA features use custom Aggie GPA intents rather than a system education domain.
