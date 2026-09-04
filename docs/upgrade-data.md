# United upgrade data

## The four exports

| File | Class | Cabin |
|---|---|---|
| `PNPZ_Data_PZ.csv` | PZ | Polaris |
| `PNPZ_Data_PN.csv` | PN | GS Polaris |
| `PNPZ_Data_RN.csv` | RN | Premium Plus |
| `PNPZ_Data_IN.csv` | IN | Award Polaris |

Each comes from the same Seat Aero endpoint with a different `fare_class`:

```
https://seats.aero/_api/pnpz?fare_class=PZ&origin_region=Anywhere&destination_region=Anywhere&csv=true
```

The request is authenticated by the `__Host-session` cookie, so it only works
from a logged-in browser or with that cookie supplied as a header.

Only PZ is required. The Hub Scan table renders a column per class that has a
published file and names the missing ones underneath, so the app degrades
cleanly while some are absent.

## Refreshing by hand (works today)

Triple-tap the results count on the UA Upgrades tab to reveal the admin row.

1. Tap **⬇ PZ**, **⬇ PN**, **⬇ RN**, **⬇ IN** in turn. Each jumps to Safari and
   downloads that class using your logged-in Seat Aero session. Four taps,
   because Seat Aero has no multi-class export and iOS hands one download per
   trip to Safari.
2. Tap **📂 Load CSVs** once and select all four together. Each file is filed by
   the class its rows declare, so the picker order and the filenames don't
   matter.

Every file loads into the app immediately. Whether it is also committed to the
repo depends on the Worker — see below.

## Persisting all four (needs a Worker change)

`POST /update-csv` on the Worker currently derives no filename from the request,
so it writes every upload to `PNPZ_Data_PZ.csv`. Sending a PN export to it would
overwrite the PZ data. The app therefore refuses to push anything but PZ while
`WORKER_FARE_CLASS_ROUTING` is `false`.

The app already sends the target on every upload:

```json
{ "content": "departure_date,...", "fare_class": "RN", "path": "PNPZ_Data_RN.csv" }
```

Teach the Worker to honour it, rejecting anything not on the allowlist so the
endpoint can't be used to write arbitrary paths:

```js
const ALLOWED = ["PZ", "PN", "RN", "IN"];
const fareClass = ALLOWED.includes(body.fare_class) ? body.fare_class : "PZ";
const path = `PNPZ_Data_${fareClass}.csv`;   // was hardcoded to PNPZ_Data_PZ.csv
```

Then flip `WORKER_FARE_CLASS_ROUTING` to `true` in `index.html` and all four
uploads will commit to their own files.

## Refreshing automatically

`.github/workflows/update-csv.yml` pulls all four every four hours and commits
whatever it gets. It needs a repository secret `SEAT_AERO_SESSION` holding the
value of the `__Host-session` cookie from a logged-in seats.aero browser
session. PZ is required; PN/RN/IN are attempted independently and skipped if
Seat Aero won't serve them for the account.

`.github/scripts/fetch-pnpz.sh` verifies each response really is a PNPZ export
before overwriting anything, so an expired cookie (which returns HTTP 200 with
an HTML login page) leaves the last good data in place rather than destroying
it.

Session cookies expire, so this needs the secret re-pasted whenever it lapses.
