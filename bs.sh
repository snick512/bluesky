#!/bin/bash

IDENTIFIER="tyclifford.com"
APP_PASSWORD=""

API_URL="https://bsky.social"
AUTH_ENDPOINT="$API_URL/xrpc/com.atproto.server.createSession"
POST_ENDPOINT="$API_URL/xrpc/com.atproto.repo.createRecord"
BLOB_ENDPOINT="$API_URL/xrpc/com.atproto.repo.uploadBlob"

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
  exit 0
fi

if [ "${#POST_TEXT}" -gt 300 ]; then
  zenity --error --text="Post too long! ${#POST_TEXT}/300 characters.\nPlease shorten your post."
  exit 1
fi

# Step 3: Ask for image file (optional)
IMAGE_FILE=$(zenity --file-selection \
  --title="Select an image to attach (or cancel to skip)" \
  --file-filter="Images | *.png *.jpg *.jpeg *.webp")

# Step 4: If image selected, compress and upload
if [ -n "$IMAGE_FILE" ]; then
  echo "[*] Compressing and uploading image: $IMAGE_FILE"

  EXT="${IMAGE_FILE##*.}"
  TMP_IMAGE="/tmp/bluesky_compressed.$EXT"

  if command -v convert &> /dev/null; then
    convert "$IMAGE_FILE" -resize 1024x1024\> -strip -quality 75 "$TMP_IMAGE"
  elif command -v ffmpeg &> /dev/null; then
    ffmpeg -i "$IMAGE_FILE" -vf "scale='min(1024,iw)':-2" -qscale:v 5 "$TMP_IMAGE" -y
  else
    zenity --error --text="Image compression tools (ImageMagick or ffmpeg) not found. Please install one to attach images."
    exit 1
  fi

  IMAGE_MIME=$(file -b --mime-type "$TMP_IMAGE")

  IMAGE_RESP=$(curl -s -X POST "$BLOB_ENDPOINT" \
    -H "Authorization: Bearer $ACCESS_JWT" \
    -H "Content-Type: $IMAGE_MIME" \
    --data-binary "@$TMP_IMAGE")

  BLOB_REF=$(echo "$IMAGE_RESP" | jq -c '.blob')
  rm -f "$TMP_IMAGE"

  if [ "$BLOB_REF" == "null" ] || [ -z "$BLOB_REF" ]; then
    zenity --error --text="Failed to upload image. Continuing without it."
    BLOB_REF=""
  fi
else
  BLOB_REF=""
fi


CURRENT_TIME=$(date --utc +%Y-%m-%dT%H:%M:%SZ)

# Step 5: Build the post payload
if [ -n "$BLOB_REF" ]; then
  # Payload with image embed
  read -r -d '' POST_DATA <<EOF
{
  "repo": "$DID",
  "collection": "app.bsky.feed.post",
  "record": {
    "\$type": "app.bsky.feed.post",
    "text": "$POST_TEXT",
    "createdAt": "$CURRENT_TIME",
    "embed": {
      "\$type": "app.bsky.embed.images",
      "images": [
        {
          "image": $BLOB_REF,
          "alt": "Image uploaded via Bash"
        }
      ]
    }
  }
}
EOF
else
  # Payload without image
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
fi

# Step 6: Send the post
POST_RESP=$(curl -s -X POST "$POST_ENDPOINT" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_JWT" \
  -d "$POST_DATA")

URI=$(echo "$POST_RESP" | jq -r '.uri')

# Step 7: Handle result
if [[ "$URI" != "null" && -n "$URI" ]]; then
  POST_URL="https://bsky.app/profile/${DID}/post/$(basename "$URI")"

  # Copy to clipboard if available
  if command -v xclip &> /dev/null; then
    echo "$POST_URL" | xclip -selection clipboard
  elif command -v pbcopy &> /dev/null; then
    echo "$POST_URL" | pbcopy
  fi

  zenity --info --text="✅ Post successful!\n\nURL copied to clipboard:\n$POST_URL"
else
  ERR_MSG=$(echo "$POST_RESP" | jq -r '.error // "Unknown error"')
  zenity --error --text="❌ Failed to post:\n$ERR_MSG"
fi
