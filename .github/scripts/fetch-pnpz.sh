#!/usr/bin/env bash
# Download one Seat Aero PNPZ fare-class export.
#   usage: fetch-pnpz.sh <fare_class> <destination_file>
# Writes the destination only when the response is a real export, so a failed,
# blocked or logged-out request leaves the last good data in place.
set -euo pipefail

FARE_CLASS="$1"
DEST="$2"
URL="https://seats.aero/_api/pnpz?fare_class=${FARE_CLASS}&origin_region=Anywhere&destination_region=Anywhere&csv=true"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'

fetch_once() {
  # -w writes to stdout, never into -o, so capture it here. Reading the status
  # back out of the downloaded body instead matches the last digits of the last
  # CSV row ("...,PZ2" -> "2") and fails every time, however good the download.
  #
  # Seat Aero sits behind Cloudflare, and its app routes are far more willing to
  # answer something that looks like the browser the session cookie came from,
  # so send the headers a real navigation would.
  curl -s --compressed -w '%{http_code}' -o "$TMP" \
    -H "Cookie: __Host-session=${SEAT_AERO_SESSION}" \
    -H "User-Agent: ${UA}" \
    -H 'Accept: text/csv,text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
    -H 'Accept-Language: en-US,en;q=0.9' \
    -H 'Referer: https://seats.aero/pnpz' \
    -H 'Sec-Fetch-Dest: document' \
    -H 'Sec-Fetch-Mode: navigate' \
    -H 'Sec-Fetch-Site: same-origin' \
    -H 'Upgrade-Insecure-Requests: 1' \
    "$URL"
}

HTTP_CODE=""
for ATTEMPT in 1 2 3; do
  HTTP_CODE="$(fetch_once || echo 000)"
  echo "attempt $ATTEMPT: HTTP $HTTP_CODE for fare class $FARE_CLASS"
  [ "$HTTP_CODE" = "200" ] && break
  [ "$ATTEMPT" -lt 3 ] && sleep $(( ATTEMPT * 5 ))
done

# Cloudflare blocks before Seat Aero ever sees the cookie, so this failure means
# "this runner is not allowed to ask", not "the session expired". Name it, so a
# bad cookie is never blamed for a WAF block.
if grep -qi 'Attention Required\|cf-error-details\|Cloudflare Ray ID' "$TMP" 2>/dev/null; then
  echo "BLOCKED BY CLOUDFLARE (HTTP $HTTP_CODE) — the request never reached Seat Aero."
  echo "The session cookie is irrelevant here; this runner's IP or client is refused."
  echo "See docs/upgrade-data.md for the options."
  exit 1
fi

if [ "$HTTP_CODE" != "200" ]; then
  echo "--- first 500 chars of response ---"
  head -c 500 "$TMP"; echo
  echo "Request failed — leaving $DEST untouched"
  exit 1
fi

# An expired session answers 200 with an HTML login page, so confirm the body
# really is the export before overwriting known-good data with it.
if ! head -1 "$TMP" | grep -q '^departure_date,'; then
  echo "Response is not a PNPZ CSV (session cookie expired?) — leaving $DEST untouched"
  echo "--- first 500 chars of response ---"
  head -c 500 "$TMP"; echo
  exit 1
fi

ROWS=$(( $(wc -l < "$TMP") - 1 ))
if [ "$ROWS" -lt 1 ]; then
  echo "Export had no data rows — leaving $DEST untouched"
  exit 1
fi

cp "$TMP" "$DEST"
echo "Wrote $ROWS rows to $DEST"
