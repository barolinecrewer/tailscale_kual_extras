#!/bin/sh

TAILSCALE=/mnt/us/extensions/tailscale/bin/tailscale
AUTH_KEY=/mnt/us/extensions/tailscale/bin/auth.key
OAUTH_SECRET=/mnt/us/extensions/tailscale/bin/oauth.client_secret
OAUTH_TAGS=/mnt/us/extensions/tailscale/bin/oauth.tags
LOG=/mnt/us/extensions/tailscale/bin/tailscale_start_log.txt

eips_log() {
    echo "$1" >> "$LOG"
    eips 0 22 "$(printf '%-50s' "$1")" 2>/dev/null
}

echo "[$(date)] Starting Tailscale..." > "$LOG"
eips_log "Reconnecting to Tailscale..."

# Try reconnecting without re-authenticating first (works when the node is
# already registered and key expiry is disabled).  A timeout prevents hanging
# indefinitely: on a fresh/reset node tailscale up prints a login URL and
# waits forever rather than returning an error.
if timeout 15 "$TAILSCALE" up --ssh >> "$LOG" 2>&1; then
    eips_log "Tailscale connected!"
    exit 0
fi

eips_log "Reconnect failed, trying registration..."

read_first_line() {
    sed -n '1{s/[[:space:]]*$//;p;}' "$1" 2>/dev/null
}

OAUTH_SECRET_VALUE=$(read_first_line "$OAUTH_SECRET")
OAUTH_TAGS_VALUE=$(read_first_line "$OAUTH_TAGS")

# Prefer OAuth if configured. Tailscale accepts an OAuth client secret in
# --auth-key, but it must be paired with one or more tags that the OAuth
# client is allowed to use.
if [ -n "$OAUTH_SECRET_VALUE" ] && [ -n "$OAUTH_TAGS_VALUE" ]; then
    eips_log "Authenticating with OAuth..."
    if "$TAILSCALE" up --ssh \
        --auth-key="${OAUTH_SECRET_VALUE}?ephemeral=false&preauthorized=true" \
        --advertise-tags="$OAUTH_TAGS_VALUE" >> "$LOG" 2>&1; then
        eips_log "Tailscale connected!"
    else
        eips_log "OAuth login failed - check log"
        exit 1
    fi
# Fall back to an auth key for first-time registration or after a manual reset.
elif [ -s "$AUTH_KEY" ]; then
    eips_log "Authenticating with auth key..."
    if "$TAILSCALE" up --ssh --auth-key="$(cat "$AUTH_KEY")" >> "$LOG" 2>&1; then
        eips_log "Tailscale connected!"
    else
        eips_log "Auth key login failed - check log"
        exit 1
    fi
else
    eips_log "Tailscale: fill oauth.* or auth.key and retry"
    exit 1
fi
