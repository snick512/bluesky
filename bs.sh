#!/bin/bash

IDENTIFIER="tyclifford.com"
APP_PASSWORD=""

API_URL="https://bsky.social"
AUTH_ENDPOINT="$API_URL/xrpc/com.atproto.server.createSession"
POST_ENDPOINT="$API_URL/xrpc/com.atproto.repo.createRecord"

# Step 1: Authenticate
echo "[*] Authenticating..."
RESPONSE=$(curl -s -X POST "$AUTH_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d "{\"identifier\":\"$IDENTIFIER\",\"password\":\"$APP_PASSWORD\"}")

ACCESS_JWT=$(echo "$RESPONSE" | jq -r '.accessJwt')
DID=$(echo "$RESPONSE" | jq -r '.did')

if [ "$ACCESS_JWT" == "null" ] || [ -z "$ACCESS_JWT" ]; then
  zenity --error --text="Authentication failed. Please check your credentials."
  exit 1
fi

# Step 2: Get post text via GUI
POST_TEXT=$(zenity --entry \
  --title="Bluesky Post" \
  --text="Enter your post text (max 300 characters):" \
  --width=800)

if [ -z "$POST_TEXT" ]; then
  #zenity --info --text="No post text entered. Exiting."
  exit 0
fi

if [ "${#POST_TEXT}" -gt 300 ]; then
  zenity --error --text="Post too long! ${#POST_TEXT}/300 characters.\nPlease shorten your post."
  exit 1
fi

CURRENT_TIME=$(date --utc +%Y-%m-%dT%H:%M:%SZ)

# Step 3: Prepare post payload
read -r -d '' POST_DATA <<EOF
{
  "repo": "$DID",
  "collection": "app.bsky.feed.post",
  "record": {
    "\$type": "app.bsky.feed.post",
    "text": "$POST_TEXT",
    "createdAt": "$CURRENT_TIME"
  }
}
EOF

# Step 4: Send the post
POST_RESP=$(curl -s -X POST "$POST_ENDPOINT" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_JWT" \
  -d "$POST_DATA")

URI=$(echo "$POST_RESP" | jq -r '.uri')

# Step 5: Handle result
if [[ "$URI" != "null" && -n "$URI" ]]; then
  POST_URL="https://bsky.app/profile/${DID}/post/$(basename "$URI")"

  # Try to copy to clipboard (Linux: xclip, macOS: pbcopy)
  if command -v xclip &> /dev/null; then
    echo "$POST_URL" | xclip -selection clipboard
  elif command -v pbcopy &> /dev/null; then
    echo "$POST_URL" | pbcopy
  fi

  #zenity --info --text="✅ Post successful!\n\nURL copied to clipboard:\n$POST_URL"
else
  ERR_MSG=$(echo "$POST_RESP" | jq -r '.error // "Unknown error"')
  zenity --error --text="❌ Failed to post:\n$ERR_MSG"
fi
