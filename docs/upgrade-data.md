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

Every file loads into the app immediately and is committed to the repo in one
go, so it is still there on the next load. The status line under the buttons
reports each file's row count and whether the commit succeeded.

## How the phone import persists

`POST /update-csv` on the Worker commits whatever it is given to one fixed
path, and it can't be told to write a second file. That doesn't block anything,
because every row already names its own class in the `inventory` column
(`PZ3`, `RN2`), so the four exports are spliced into one combined CSV, sent as a
single commit, and split back apart on load. `PNPZ_Data_PZ.csv` therefore holds
every class, and `csvUpgradeData` — which backs the Search tab, whose inventory
filter is written in PZ terms — keeps only the PZ rows.

Bytes are unchanged: the app was already fetching all four files, and now
fetches one of the same total size in a single request.

A class published as its own file still wins over whatever the combined export
carried for it, so the two routes mix safely — but don't leave a stale
`PNPZ_Data_PN.csv` lying around, because it will take precedence over a fresher
combined import.

### Optional: a file per class

If the Worker is ever taught to read the `fare_class`/`path` fields the app
already sends:

```json
{ "content": "departure_date,...", "fare_class": "RN", "path": "PNPZ_Data_RN.csv" }
```

```js
const ALLOWED = ["PZ", "PN", "RN", "IN"];
const fareClass = ALLOWED.includes(body.fare_class) ? body.fare_class : "PZ";
const path = `PNPZ_Data_${fareClass}.csv`;   // was hardcoded to PNPZ_Data_PZ.csv
```

...then set `WORKER_FARE_CLASS_ROUTING` to `true` in `index.html` and each class
commits to its own file instead. Tidier, and it keeps the Search tab's file
small, but nothing depends on it.

## Refreshing automatically

`.github/workflows/update-csv.yml` pulls all four and commits whatever it gets.
It is **manual-only** until proven to work — its `schedule:` block is commented
out so a runner that can't reach Seat Aero doesn't fail every four hours. Run it
from the Actions tab, and re-enable the cron once a run succeeds. It needs a repository secret `SEAT_AERO_SESSION` holding the
value of the `__Host-session` cookie from a logged-in seats.aero browser
session. PZ is required; PN/RN/IN are attempted independently and skipped if
Seat Aero won't serve them for the account.

### The real obstacle is Cloudflare, not the cookie

Seat Aero sits behind Cloudflare, and its app routes are protected by a WAF rule
that refuses clients it doesn't like — before the session cookie is ever
evaluated. From a datacenter IP:

| Request | Result |
|---|---|
| `GET /` | `200`, the real homepage |
| `GET /pnpz` | `403`, Cloudflare "Attention Required" |
| `GET /_api/pnpz?...` (no cookie) | `403`, Cloudflare "Attention Required" |

The export endpoint answers with a Cloudflare block page rather than a `401` or a
login redirect, and browser-shaped headers didn't change that. So a perfectly
valid cookie can still fail here: the request never reaches the application.
`fetch-pnpz.sh` detects this case by name so the log says "blocked by
Cloudflare" instead of blaming an expired session.

That result is from one datacenter's IPs. GitHub Actions runners are different
addresses, and the WAF may score them differently, so **it is worth one run to
find out** — the script refuses to overwrite anything unless it gets a real
export back, so a blocked attempt costs nothing but a red check. Set the secret,
trigger the workflow by hand, and read the log:

- `Wrote N rows to PNPZ_Data_PZ.csv` — it works; the schedule takes over.
- `BLOCKED BY CLOUDFLARE` — runners are refused too; see the fallbacks below.
- `Response is not a PNPZ CSV` — got through, but the cookie is stale. Re-paste it.

One caveat if it is blocked: when Cloudflare challenges a browser, what proves
the challenge was passed is a `cf_clearance` cookie, and that cookie is bound to
the IP and user-agent that earned it. Copying it out of your browser into the
runner won't work, because the runner has a different address. There is no
cookie you can paste that fixes an IP-level block.

### Fallbacks if the runner is blocked

- **Keep the manual flow.** Four downloads and one import, as above. It works
  because your phone is a real browser on a residential IP.
- **Pull from the Worker.** Cloudflare Workers egress from Cloudflare's own
  network rather than a datacenter range, so a `/refresh-all` endpoint that
  fetches all four with the cookie may be scored differently. Untested, and it
  could equally be refused, but it is cheap to try and the Worker already holds
  credentials.
- **Pull from a machine you own.** Anything on a residential connection — a
  cron on a home machine, or an iOS Shortcut — can fetch the four exports and
  POST them to the Worker's `/update-csv`, which is the same path the manual
  import already uses.

Session cookies expire whichever route you take, so the secret needs re-pasting
whenever it lapses.

## The Odds view

The third sub-tab on the UA Upgrades tab answers a different question from the
other two. Search and Hub Scan ask "where is there space right now". Odds asks
"how often does this pair show this class at all" — the read you want before
spending PlusPoints, not after.

Enter two airport codes and the dates you could travel, pick a class, and it
reports two rates over the same range, plus all four classes side by side, a
per-flight breakdown and a day-of-week pattern.

### What the percentages mean

**The export records only space that exists.** There is no row for a flight with
nothing open, so the file carries no zeroes and a rate needs a denominator the
data doesn't supply. That denominator is **the calendar days in the range you
enter**, which is why the range is a control rather than a fixed window.

| | Definition |
|---|---|
| Day rate | Distinct `departure_date`s on the pair meeting the seat minimum ÷ days in range |
| Flight rate | Distinct `(date, flight_number)` sightings ÷ (roster × days in range) |

The roster is the distinct flight numbers seen on the pair across any class
inside the range, and it is not seat-filtered — a flight showing one seat still
operates. It does count a seasonal flight the same as a daily one, so the flight
rate runs conservative on an irregular roster.

Both rates are printed with their raw fraction (`2 of 30 days`), because the
fraction is the part that can be checked.

### Why the range matters, and the coverage line

United loads upgrade space close in, so the export is heavily front-loaded:
roughly 850 rows/day for the coming month against ~50/day a year out. A rate
averaged over the whole file therefore mostly measures how far ahead United has
published, not how good the route is. EWR→LHR PZ reads 4.4% over the full 338
days and about 7% over any window you would actually book.

So every result carries a coverage verdict, scaled against the mean rows/day of
the export's first 30 days:

| Ratio | Verdict | Reading |
|---|---|---|
| ≥ 60% | Well covered | A low number is a real answer |
| 25–60% | Partial coverage | Still loading; true rate likely higher |
| < 25% | Sparse | Treat a low number as unknown, not as no |

This is what separates the two zeroes. EWR→LHR shows no PZ in either of these
windows, and they mean opposite things:

| Range | Rows/day | Verdict | Means |
|---|---|---|---|
| 2026-09-11 → 10-11 | 855 | Well covered | Densely observed, genuinely no PZ |
| 2027-06-01 → 06-30 | 89 | Sparse | Nothing published yet; no conclusion |

### Other behaviour worth knowing

- A pair that never shows the chosen class reports **Never** rather than 0%, and
  names what it does show — other classes on the pair, and the reverse direction
  if that does better, which it often does.
- An airport absent from the whole export is called out as a likely typo, since
  the file only covers United's own flights.
- A range outside the export's dates names the span the file actually holds.
- Bars in each table are scaled to that table's own maximum, not to 100% — these
  rates sit in single digits, so a bar drawn against 100% is flat on every row.
  The percentage beside it carries the absolute.
- Classes with no published export get a dimmed, inert chip rather than a 0%.
