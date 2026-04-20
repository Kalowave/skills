#!/usr/bin/env bash
# kaloclip - CLI wrapper for KaloClip Open API.
set -euo pipefail

BASE="https://clip.kalowave.com/api/open/v1"
# Home dir. Override with KALOCLIP_HOME.
CONFIG_DIR="${KALOCLIP_HOME:-$HOME/.kaloclip}"
CONFIG_FILE="$CONFIG_DIR/config.env"

load_config() {
  [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE" || true
}

save_config() {
  mkdir -p "$CONFIG_DIR" && chmod 700 "$CONFIG_DIR"
  printf 'KALOCLIP_API_KEY=%q\n' "${KALOCLIP_API_KEY:-}" > "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}

require_key() {
  load_config
  [ -n "${KALOCLIP_API_KEY:-}" ] || { echo "Error: API key not set. Run: $0 set-key <api_key>" >&2; exit 1; }
}

api() { curl -sS -H "X-API-Key: $KALOCLIP_API_KEY" "$@"; }

usage() {
  cat <<'EOF'
kaloclip - KaloClip Open API CLI

USAGE
  kaloclip.sh <command> [args...]
  kaloclip.sh help [topic]
      topics: login | credits | images-options | upload | import |
              videos-options | videos-queue | preview | video |
              script | job | wait | flow | all

CONFIG
  login                        browser-based device-flow: confirm once, key auto-saved
  set-key <key>                save API key directly (non-interactive / no browser)
  show-config                  show masked key
  unset                        delete config

QUERY
  credits                      balance
  images-options               upload constraints
  videos-options               available duration / resolution / aspectRatio
  videos-queue                 { pending, processing, estimatedWaitSeconds }
  job <jobId>                  poll job status (also /videos/{jobId})

ACTION
  upload <file>...             POST /images   (multipart, 1-6 files, 5MB each)
  import <url>...              POST /images/import   (1-6 HTTPS URLs)
  script                       POST /scripts  async, 2 credits   (JSON on stdin)
  preview                      POST /videos/preview  credit cost   (JSON on stdin)
  video                        POST /videos   credits deducted    (JSON on stdin)
  wait <jobId> [interval_s]    poll until COMPLETED/FAILED (default 5s)
  flow <image-url> [title]     end-to-end: import → script → video → videoUrl

All responses wrapped: { success, code, message, data, cached }.  Check .success first.
Env: KALOCLIP_API_KEY overrides saved file.  KALOCLIP_HOME overrides ~/.kaloclip.
Use  `help <topic>`  for request-body and response schemas.
EOF
}

_help_credits() { cat <<'EOF'
credits - GET /credits                                            rate: 30/min

Response (.data):
  totalRemain           number    total
  monthlyRemain         number    monthly (expire)
  permanentRemain       number    permanent
  subAccount            boolean
  mainTotalRemain       number?   main-account totals (sub-accounts only)
  mainPermanentRemain   number?
  mainMonthlyRemain     number?
EOF
}

_help_images-options() { cat <<'EOF'
images-options - GET /images/options                              rate: 30/min

Response (.data):
  {"allowedTypes":["image/jpeg","image/png","image/gif","image/webp"],
   "maxSizeBytes":5242880,"maxCount":6}
EOF
}

_help_upload() { cat <<'EOF'
upload <file>... - POST /images                                   rate: 10/min

Multipart part `images` (file[]), 1-6 files, 5MB each, JPEG/PNG/GIF/WebP.

Response (.data): array of
  assetId      number    asset id, use in imageInfos[].assetId
  imageUrl     string    CDN URL, use in imageInfos[].imageUrl
  description  string?   initial AI description (may be null)
  success      boolean   true if upload/compliance passed
EOF
}

_help_import() { cat <<'EOF'
import <url>... - POST /images/import                             rate: 10/min

Body: JSON array of HTTPS URLs. Same constraints/response as `upload`.
EOF
}

_help_videos-options() { cat <<'EOF'
videos-options - GET /videos/options                              rate: 30/min

Response (.data): dynamic config with enums and rules.

  aspectRatioOptions  [{label,value}]   value: RATIO_9_16 | RATIO_16_9
  durationOptions     [{label,value,default?}]   value: 8 | 12 | 15 | 20
  resolutionOptions   [{label,value}]   value: 720P | 1080P | 4K
  quantityOptions     [{label,value}]   (only value=1 is accepted by /videos)
  modelOptions        [{label,value,description}]
                        values: v31 | sr2l | sr2 | sd2f | sd2 | sr20
                        (this value goes into `internalModelId` on /videos|/scripts|/videos/preview)
  rules.duration_model        { "8":[...], "12":[...], ... }
  rules.duration_resolution   { "8":[...], "720P":[...], ... }

Fetch this endpoint first to discover valid (duration, resolution, model) combos.
EOF
}

_help_videos-queue() { cat <<'EOF'
videos-queue - GET /videos/queue                                  rate: 30/min

Response (.data):
  pending                 number   tasks waiting
  processing              number   tasks in progress
  estimatedWaitSeconds    number   ~120s per queued task
EOF
}

_help_preview() { cat <<'EOF'
preview - POST /videos/preview   (JSON on stdin)                  rate: 20/min

Returns credit cost (number in .data); no deduction.

Body:
  REQUIRED
    duration         int     8 / 12 / 15 / 20
    resolution       string  720P / 1080P / 4K
    aspectRatio      string  RATIO_9_16 / RATIO_16_9
    quantity         int     must be 1
    internalModelId  string  v31 / sr2l / sr2 / sd2f / sd2 / sr20
                             (must match duration per rules.duration_model)
EOF
}

_help_video() { cat <<'EOF'
video - POST /videos   (JSON on stdin)                            rate: 5/min

Credits deducted on submit; auto-refund on fail. Returns jobId (number in .data).
Poll with `wait <jobId>` or `job <jobId>`. On completed:
  .data.output.videoUrl        generated mp4 URL
  .data.output.coverImageUrl   cover jpg URL
  .data.output.userAssetId     library asset id

Body:
  REQUIRED
    imageInfos       ImageInfo[]  1-6
    productTitle     string
    duration         int     8 / 12 / 15 / 20
    aspectRatio      string  RATIO_9_16 / RATIO_16_9
    resolution       string  720P / 1080P / 4K
    quantity         int     must be 1
    internalModelId  string  v31 / sr2l / sr2 / sd2f / sd2 / sr20
                             (must match duration per rules.duration_model
                              returned by GET /videos/options)
  OPTIONAL
    originScript, userModifiedScript, language (default en),
    categoryNames, sellingPoints, creationDescription (<= 300),
    requestId (script jobId, auto-fills script),
    productId, country, sellingCountry

  ImageInfo: { "assetId": number, "imageUrl": string, "description"?: string }
EOF
}

_help_script() { cat <<'EOF'
script - POST /scripts   (JSON on stdin)                          rate: 5/min

Async. Deducts 2 credits (auto-refund on FAIL). Returns jobId (number in .data).
Poll with `wait <jobId>` or `job <jobId>`. On COMPLETED: .data.output.script.

Body:
  REQUIRED
    imageInfos       ImageInfo[]  1-6 (from upload/import)
    productTitle     string
    categoryNames    string[]
    language         string    en, zh, ...
    duration         int       8 / 12 / 15 / 20
    internalModelId  string    v31 / sr2l / sr2 / sd2f / sd2 / sr20
  OPTIONAL
    sellingPoints         string[]
    creationDescription   string   <= 300 chars
    productId             string
    productLink           string
    sellingCountry        string

  ImageInfo: { "assetId": number, "imageUrl": string, "description"?: string }
EOF
}

_help_job() { cat <<'EOF'
job <jobId> - GET /jobs/{jobId}   (also /videos/{jobId})          rate: 30/min

States (lowercase): queued -> prepared -> processing -> processed -> enhanced
                                                      -> completed | failed
(`wait` matches case-insensitively.)

Response (.data):
  id                       number
  jobType                  string   VIDEO_CREATION | REFERENCE_SCRIPT_GENERATE  (uppercase)
  state                    string   see above
  input                    object?  echoes the submitted body (debug)
  resourceId               string   backend resource id
  retryCount               number   server-side retry count
  queuePosition            number?  null in terminal states; 1 = next
  estimatedCompletionTime  number?  ms timestamp; null in terminal states
  errorMessage             string?  set on failed   (e.g. "Server busy. No credits deducted.")
  output                   object?  set on completed:
                                      VIDEO_CREATION          -> { videoUrl, coverImageUrl,
                                                                   enhanceVideoUrl?, userAssetId }
                                      REFERENCE_SCRIPT_GENERATE -> { script }
  gmtCreated, gmtUpdated   number   ms timestamps
EOF
}

_help_wait() { cat <<'EOF'
wait <jobId> [interval_s] - poll /jobs/{jobId} until COMPLETED or FAILED (default 5s).

Tick lines go to stderr; the final full response JSON goes to stdout.
Exit code: 0 on COMPLETED, 1 on FAILED or after 5 consecutive transient errors.
EOF
}

_help_login() { cat <<'EOF'
login - device-flow: hands-free setup via browser confirmation.

Generates a one-time random seed, opens
  https://clip.kalowave.com/api/users/open-api-key/device-flow/confirm?seed=<seed>
in your browser. You must already be logged in to kaloclip.com in that
browser — the server validates the session, derives your apiKey, and
stashes it in Redis under the seed (TTL 10min).

Meanwhile the CLI polls
  /api/open/device-flow/poll?seed=<seed>
every 2 seconds. First successful poll retrieves the apiKey; the server
deletes the Redis entry on that same call (one-shot pickup). No copy-paste.

On success the key is saved to ~/.kaloclip/config.env (0600) and a
/credits round-trip confirms it works.

Timeout: 5 min (seed TTL is 10 min; CLI polls for 5 to cap wait).
Non-interactive environments should use `set-key <key>` instead.
EOF
}

_help_flow() { cat <<'EOF'
flow <image-url> [product-title] - end-to-end demo: import → script → wait → video → wait

Runs the full happy path with opinionated defaults (duration=12s, model=sr2l,
aspectRatio=RATIO_9_16, resolution=720P, quantity=1, language=en,
categoryNames=["General"]). Import is free; script costs 2 credits; video
costs the credits shown by `preview` (~10 for this combo).

Progress (each step, state ticks) goes to stderr.
Final JSON (scriptJobId, videoJobId, videoUrl, coverImageUrl, userAssetId, script)
goes to stdout. Exit code: 0 on end-to-end success, 1 on any failure.

Example:
  ./scripts/kaloclip.sh flow https://picsum.photos/id/200/600/600.jpg "Fresh Croissant"
EOF
}

help_topic() {
  local t="${1:-}"
  case "$t" in
    "") usage ;;
    all)
      for sub in login credits images-options upload import videos-options videos-queue preview video script job wait flow; do
        "_help_$sub"; echo
      done ;;
    login|credits|images-options|upload|import|videos-options|videos-queue|preview|video|script|job|wait|flow)
      "_help_$t" ;;
    *)
      echo "Unknown help topic: $t" >&2
      echo "Topics: login credits images-options upload import videos-options videos-queue preview video script job wait flow all" >&2
      exit 2 ;;
  esac
}

cmd="${1:-help}"; shift || true

case "$cmd" in
  help|--help|-h) help_topic "${1:-}" ;;

  set-key)
    [ $# -ge 1 ] || { echo "usage: $0 set-key <api_key>  (or run '$0 login' for guided setup)" >&2; exit 2; }
    KALOCLIP_API_KEY="$1"; save_config
    echo "API key saved to $CONFIG_FILE" ;;

  login)
    # CLI device-flow: generate seed -> open browser to confirm URL -> poll for pickup.
    # Base host is the authority portion of $BASE (strip /api/open/v1).
    host="${BASE%/api/*}"
    # 32 bytes URL-safe base64 = 43 chars — well within the 16-128 server limit.
    if command -v python3 >/dev/null 2>&1; then
      seed=$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')
    else
      seed=$(head -c 32 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=\n')
    fi
    confirm_url="$host/api/users/open-api-key/device-flow/confirm?seed=$seed"
    poll_url="$host/api/open/device-flow/poll?seed=$seed"
    cat <<EOF
Opening the authorization page in your browser.

  $confirm_url

You must be logged in to kaloclip.com in the same browser. Once the page
shows "CLI authorized", this terminal will pick the key up automatically.
EOF
    if command -v open >/dev/null 2>&1; then
      open "$confirm_url" >/dev/null 2>&1 || true
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$confirm_url" >/dev/null 2>&1 || true
    else
      echo "(No 'open'/'xdg-open' — paste the URL above into your browser manually.)"
    fi
    echo
    # Poll every 2s for up to 5 min.
    max_tries=150
    for i in $(seq 1 $max_tries); do
      presp=$(curl -sS "$poll_url" 2>/dev/null || echo '{}')
      pstatus=$(printf '%s' "$presp" | jq -r '.data.status // empty' 2>/dev/null)
      case "$pstatus" in
        ready)
          key=$(printf '%s' "$presp" | jq -r '.data.apiKey')
          if [ -z "$key" ] || [ "$key" = "null" ]; then
            echo "Error: poll reported ready but apiKey missing: $presp" >&2
            exit 1
          fi
          KALOCLIP_API_KEY="$key"; save_config
          echo "API key saved to $CONFIG_FILE"
          # Round-trip sanity check.
          vresp=$(api "$BASE/credits" 2>/dev/null || true)
          vok=$(printf '%s' "$vresp" | jq -r '.success // empty' 2>/dev/null)
          if [ "$vok" = "true" ]; then
            echo "Key verified: $(printf '%s' "$vresp" | jq -r '.data | "balance=\(.totalRemain)"')"
          else
            echo "Warning: key saved but /credits call did not succeed (response: $vresp)" >&2
          fi
          exit 0
          ;;
        pending)
          printf '\r  waiting for browser confirmation... (%ds)' "$((i * 2))"
          ;;
        *)
          echo ""
          echo "Unexpected poll response: $presp" >&2
          exit 1
          ;;
      esac
      sleep 2
    done
    echo ""
    echo "Timed out after $((max_tries * 2))s waiting for browser confirmation." >&2
    echo "If you confirmed too late, the seed expired (TTL 10 min). Rerun '$0 login'." >&2
    exit 1
    ;;

  show-config)
    load_config
    echo "Config file: $CONFIG_FILE"
    if [ -n "${KALOCLIP_API_KEY:-}" ] && [ ${#KALOCLIP_API_KEY} -gt 8 ]; then
      echo "KALOCLIP_API_KEY=${KALOCLIP_API_KEY:0:4}...${KALOCLIP_API_KEY: -4}"
    elif [ -n "${KALOCLIP_API_KEY:-}" ]; then
      echo "KALOCLIP_API_KEY=****"
    else
      echo "KALOCLIP_API_KEY=<unset>"
    fi ;;

  unset) rm -f "$CONFIG_FILE"; echo "Removed $CONFIG_FILE" ;;

  credits)        require_key; api "$BASE/credits" ;;
  images-options) require_key; api "$BASE/images/options" ;;
  videos-options) require_key; api "$BASE/videos/options" ;;
  videos-queue)   require_key; api "$BASE/videos/queue" ;;

  job)
    require_key
    [ $# -ge 1 ] || { echo "usage: $0 job <jobId>" >&2; exit 2; }
    api "$BASE/jobs/$1" ;;

  upload)
    require_key
    [ $# -ge 1 ] || { echo "usage: $0 upload <file> [file...]" >&2; exit 2; }
    args=()
    for f in "$@"; do
      [ -f "$f" ] || { echo "Error: file not found: $f" >&2; exit 2; }
      args+=(-F "images=@$f")
    done
    api -X POST "$BASE/images" "${args[@]}" ;;

  import)
    require_key
    [ $# -ge 1 ] || { echo "usage: $0 import <url> [url...]" >&2; exit 2; }
    body=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@")
    api -X POST "$BASE/images/import" -H "Content-Type: application/json" -d "$body" ;;

  script|preview|video)
    require_key
    case "$cmd" in script) path=/scripts ;; preview) path=/videos/preview ;; video) path=/videos ;; esac
    api -X POST "$BASE$path" -H "Content-Type: application/json" --data-binary @- ;;

  wait)
    require_key
    [ $# -ge 1 ] || { echo "usage: $0 wait <jobId> [interval_s]" >&2; exit 2; }
    jobId="$1"; interval="${2:-5}"
    case "$jobId" in ''|*[!0-9]*) echo "Error: jobId must be a positive integer, got '$jobId'" >&2; exit 2 ;; esac
    transient=0
    final_rc=0
    while :; do
      resp=$(api "$BASE/jobs/$jobId")
      state=$(printf '%s' "$resp" | jq -r '.data.state // empty')
      code=$(printf  '%s' "$resp" | jq -r '.code // empty')
      msg=$(printf   '%s' "$resp" | jq -r '.message // empty')
      if [ -n "$state" ]; then
        transient=0
        # Ticks go to stderr so stdout carries only the final response JSON.
        echo "[$(date +%H:%M:%S)] state=$state" >&2
        # API returns either uppercase (COMPLETED/FAILED) or lowercase (completed/failed).
        upper=$(printf '%s' "$state" | tr '[:lower:]' '[:upper:]')
        case "$upper" in
          COMPLETED) printf '%s\n' "$resp"; break ;;
          FAILED)    printf '%s\n' "$resp"; final_rc=1; break ;;
        esac
      else
        transient=$((transient + 1))
        echo "[$(date +%H:%M:%S)] transient code=${code:-?} msg=${msg:-?} (retry $transient/5)" >&2
        if [ $transient -ge 5 ]; then
          echo "giving up after $transient transient errors:" >&2
          printf '%s\n' "$resp" >&2
          exit 1
        fi
      fi
      sleep "$interval"
    done
    exit $final_rc
    ;;

  flow)
    require_key
    [ $# -ge 1 ] || { echo "usage: $0 flow <image-url> [product-title]" >&2; exit 2; }
    flow_url="$1"
    flow_title="${2:-Test Product}"
    flow_duration=12
    flow_model=sr2l
    flow_aspect=RATIO_9_16
    flow_resolution=720P
    check_ok() {
      local resp="$1" step="$2"
      [ "$(printf '%s' "$resp" | jq -r '.success')" = "true" ] && return 0
      echo "$step failed: $resp" >&2
      exit 1
    }
    section() { printf '\n>>> %s\n' "$1" >&2; }

    section "1/4 import $flow_url"
    flow_body=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$flow_url")
    imp=$(api -X POST "$BASE/images/import" -H "Content-Type: application/json" -d "$flow_body")
    check_ok "$imp" "import"
    aid=$(printf '%s' "$imp" | jq -r '.data[0].assetId')
    iurl=$(printf '%s' "$imp" | jq -r '.data[0].imageUrl')
    echo "  assetId=$aid" >&2
    echo "  imageUrl=$iurl" >&2

    section "2/4 submit script (duration=${flow_duration}s, model=$flow_model)"
    sbody=$(jq -nc \
      --argjson aid "$aid" --arg iurl "$iurl" --arg title "$flow_title" \
      --argjson dur "$flow_duration" --arg model "$flow_model" \
      '{imageInfos:[{assetId:$aid,imageUrl:$iurl}],productTitle:$title,categoryNames:["General"],language:"en",duration:$dur,internalModelId:$model}')
    sresp=$(printf '%s' "$sbody" | api -X POST "$BASE/scripts" -H "Content-Type: application/json" --data-binary @-)
    check_ok "$sresp" "script submit"
    sjob=$(printf '%s' "$sresp" | jq -r '.data')
    echo "  scriptJobId=$sjob" >&2

    section "3/4 wait for script completion"
    sfinal=$("$0" wait "$sjob" 8) || { echo "script job failed:" >&2; printf '%s\n' "$sfinal" >&2; exit 1; }
    script=$(printf '%s' "$sfinal" | jq -r '.data.output.script')
    echo "  script length=${#script} chars" >&2

    section "4/4 submit video (same duration/model) with generated script"
    vbody=$(jq -nc \
      --argjson aid "$aid" --arg iurl "$iurl" --arg title "$flow_title" \
      --argjson dur "$flow_duration" --arg aspect "$flow_aspect" --arg resolution "$flow_resolution" \
      --arg model "$flow_model" --arg script "$script" \
      '{imageInfos:[{assetId:$aid,imageUrl:$iurl}],productTitle:$title,duration:$dur,aspectRatio:$aspect,resolution:$resolution,quantity:1,internalModelId:$model,originScript:$script,language:"en"}')
    vresp=$(printf '%s' "$vbody" | api -X POST "$BASE/videos" -H "Content-Type: application/json" --data-binary @-)
    check_ok "$vresp" "video submit"
    vjob=$(printf '%s' "$vresp" | jq -r '.data')
    echo "  videoJobId=$vjob" >&2

    section "waiting for video completion (~2 min)"
    vfinal=$("$0" wait "$vjob" 12) || { echo "video job failed:" >&2; printf '%s\n' "$vfinal" >&2; exit 1; }

    # Final summary to stdout; everything above is progress to stderr.
    jq -n \
      --argjson sjob "$sjob" --argjson vjob "$vjob" \
      --arg vurl   "$(printf '%s' "$vfinal" | jq -r '.data.output.videoUrl')" \
      --arg cover  "$(printf '%s' "$vfinal" | jq -r '.data.output.coverImageUrl')" \
      --argjson uaid "$(printf '%s' "$vfinal" | jq -r '.data.output.userAssetId')" \
      --arg script "$script" \
      '{scriptJobId:$sjob, videoJobId:$vjob, videoUrl:$vurl, coverImageUrl:$cover, userAssetId:$uaid, script:$script}'
    ;;

  *) echo "Unknown command: $cmd" >&2; usage >&2; exit 2 ;;
esac
