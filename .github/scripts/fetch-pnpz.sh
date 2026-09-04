#!/usr/bin/env bash
# Download one Seat Aero PNPZ fare-class export.
#   usage: fetch-pnpz.sh <fare_class> <destination_file>
# Writes the destination only when the response is a real export, so a failed
# or logged-out request leaves the last good data in place.
set -euo pipefail

FARE_CLASS="$1"
DEST="$2"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# -w writes to stdout, never into -o, so capture it here. Reading the status
# back out of the downloaded body instead matches the last digits of the last
# CSV row ("...,PZ2" -> "2") and fails every time, however good the download.
HTTP_CODE="$(curl -s -w '%{http_code}' \
  -H "Cookie: __Host-session=${SEAT_AERO_SESSION}" \
  "https://seats.aero/_api/pnpz?fare_class=${FARE_CLASS}&origin_region=Anywhere&destination_region=Anywhere&csv=true" \
  -o "$TMP")"

echo "HTTP $HTTP_CODE for fare class $FARE_CLASS"

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
