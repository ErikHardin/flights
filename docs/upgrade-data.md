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
