#!/usr/bin/env bash
# Claude Code status line: model | context | weekly limit | time to weekly reset | 5-hour limit |
# time to 5-hour reset, right-aligned. All times are differences only, so the local time zone applies throughout.
# Limits come from the session JSON when Claude provides them (Pro/Max), otherwise from quota-axi (cached 60 s,
# refreshed in the background so the status line never waits on the network).
input=$(cat)
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
cache="$cache_dir/quota.json"

model=$(jq -r '.model.display_name // "?"' <<<"$input")
ctx=$(jq -r '.context_window.used_percentage // empty' <<<"$input")
week=$(jq -r '.rate_limits.seven_day.used_percentage // empty' <<<"$input")
week_reset=$(jq -r '.rate_limits.seven_day.resets_at // empty' <<<"$input")
five=$(jq -r '.rate_limits.five_hour.used_percentage // empty' <<<"$input")
five_reset=$(jq -r '.rate_limits.five_hour.resets_at // empty' <<<"$input")

if [ -z "$week" ] || [ -z "$five" ]; then
  mkdir -p "$cache_dir"
  age=999
  [ -f "$cache" ] && age=$(( $(date +%s) - $(stat -c %Y "$cache") ))
  if [ "$age" -ge 60 ] && mkdir "$cache_dir/lock" 2>/dev/null; then
    ( quota-axi --full --json 2>/dev/null > "$cache.tmp" && [ -s "$cache.tmp" ] && mv "$cache.tmp" "$cache"; rmdir "$cache_dir/lock" ) >/dev/null 2>&1 &
  fi
  if [ -f "$cache" ]; then
    q=$(jq -c '[.. | objects | select(.provider? == "claude")][0].windows // []' "$cache" 2>/dev/null)
    [ -z "$week" ] && week=$(jq -r '.[] | select(.id=="seven_day") | .percentUsed // empty' <<<"$q")
    [ -z "$week_reset" ] && week_reset=$(jq -r '.[] | select(.id=="seven_day") | .resetsAt // empty' <<<"$q" | xargs -r -I{} date -d {} +%s)
    [ -z "$five" ] && five=$(jq -r '.[] | select(.id=="five_hour") | .percentUsed // empty' <<<"$q")
    [ -z "$five_reset" ] && five_reset=$(jq -r '.[] | select(.id=="five_hour") | .resetsAt // empty' <<<"$q" | xargs -r -I{} date -d {} +%s)
  fi
fi

parts=("$model")
[ -n "$ctx" ] && parts+=("ctx $(printf '%.0f' "$ctx")%")
[ -n "$week" ] && parts+=("Woche $(printf '%.0f' "$week")%")
if [ -n "$week_reset" ]; then
  left=$(( week_reset - $(date +%s) )); [ "$left" -lt 0 ] && left=0
  parts+=("Reset $(printf '%02dd %02d:%02d:%02d' $((left/86400)) $((left%86400/3600)) $((left%3600/60)) $((left%60)))")
fi
if [ -n "$five" ]; then
  parts+=("5h $(printf '%.0f' "$five")%")
  # A non-epoch value (ISO 8601) is converted first; without an offset date reads it as local time.
  case "$five_reset" in '') ;; *[!0-9]*) five_reset=$(date -d "$five_reset" +%s 2>/dev/null);; esac
  if [ -n "$five_reset" ]; then
    left=$(( five_reset - $(date +%s) ))
    # Nothing is printed for a reset that already passed, rather than a clamped or negative countdown.
    [ "$left" -gt 0 ] && parts+=("$(printf '%02d:%02d:%02d' $((left/3600)) $((left%3600/60)) $((left%60)))")
  fi
fi

line=$(IFS='|'; printf '%s' "${parts[*]}" | sed 's/|/ | /g')
width=$(( ${COLUMNS:-0} - 4 ))
if [ "$width" -gt "${#line}" ]; then printf '%*s' "$width" "$line"; else printf '%s' "$line"; fi
