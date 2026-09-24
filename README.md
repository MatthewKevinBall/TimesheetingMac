# Job Timer

A small macOS menu bar + floating timer for tracking hours per job, so filling in Spacecamp at the end of the day isn't guesswork.

## Build & install

```sh
./build.sh           # builds build/JobTimer.app
./build.sh install   # also copies it to /Applications and launches it
```

Requires Xcode / Swift 6 and macOS 14+. You can also open `Package.swift` in Xcode to edit and run.

## Using it

- **Menu bar**: shows the current job and elapsed time. Click it to switch jobs, add a note, or create a job.
- **Floating timer**: always-on-top pill you can drag anywhere. Click the job name to switch, ■ to stop, ⋯ for more.
- **⌥⌘T** anywhere: quick switcher. Type to filter, ↑↓, Return. Type a new name to create a job. Start with the job number (`4521 Acme website`) and it's saved as the job code.
- **Timesheet** (menu bar → Timesheet): per-job totals rounded to 15-minute blocks, notes, and **Copy Summary** (⇧⌘C) for pasting into Spacecamp. Edit or delete entries, and assign untracked gaps to a job.
- **Started earlier**: forgot to start the timer? Use "Started earlier" under the current timer to backdate it.

## Reminders (Settings tab)

- **Update your timesheet**: Mon–Fri at 4:00 pm (time adjustable). Click the notification to open the timesheet.
- **Away detection**: after 5 min idle (or sleep/lock), asks whether to keep or remove the away time.
- **No timer running**: nudges you after 15 min of activity with no timer, during work hours.
- **Still working on…?**: every 2 hours on the same job.

## Automation

The app responds to `jobtimer://` URLs, so it can be driven from Shortcuts, Raycast, a Stream Deck, etc.:

```sh
open "jobtimer://start?job=4521"   # start first job matching "4521"
open "jobtimer://stop"
open "jobtimer://switch"           # open quick switcher
open "jobtimer://timesheet"
```

## Data

Stored as JSON at `~/Library/Application Support/JobTimer/data.json`, with a daily backup (last 30 days) in `Backups/`.
