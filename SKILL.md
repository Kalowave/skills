---
name: kaloclip
description: KaloClip Open API — upload images, generate video scripts, create videos, poll jobs, check credits via the bundled CLI (scripts/kaloclip.sh). Use when user asks to upload images, generate a script/video, poll a job, check credit balance, preview credit cost, authenticate with X-API-Key, set/save the KaloClip API key, call /api/open/v1/ endpoints, or debug Open API errors. Triggers on "kaloclip", "Open API", "KaloClip API", "X-API-Key", "开放接口", "上传图片", "生成视频", "查积分", "视频创作API", "设置apikey", "set apikey".
---

# KaloClip Open API

AI-powered video generation. Use the bundled CLI (`scripts/kaloclip.sh`). `KALOCLIP_API_KEY` env var overrides the saved file.

## CLI (`scripts/kaloclip.sh`)

```bash
./scripts/kaloclip.sh set-key <api_key>     # saved to ~/.config/kaloclip/config.env (0600)
./scripts/kaloclip.sh show-config           # key is masked
./scripts/kaloclip.sh unset                 # delete config

./scripts/kaloclip.sh help                  # command list + topics
./scripts/kaloclip.sh help <topic>          # request-body + response schema
./scripts/kaloclip.sh help all              # every schema in one shot
```

### Subcommands

| Command | Purpose |
|---------|---------|
| `credits` / `images-options` / `videos-options` / `videos-queue` | simple GETs |
| `upload <file>...` | POST /images (multipart, 1–6, 5MB each) |
| `import <url>...` | POST /images/import |
| `script` / `preview` / `video` | POSTs — JSON body on stdin |
| `job <jobId>` | poll job status (also `/videos/{jobId}`) |
| `wait <jobId> [interval_s]` | poll until `COMPLETED`/`FAILED`; ticks → stderr, final JSON → stdout, exit 0/1 |
| `flow <image-url> [title]` | end-to-end: import → script → wait → video → wait; final JSON (videoUrl, coverImageUrl, script) to stdout |

**`help <topic>` is the authoritative schema reference** — request fields (required/optional, types, enums), response shape, rate limit, and state flow for `job`. Run it before constructing any JSON body.

### Agent guidance

1. Run `show-config`. If key is `<unset>`, ask user for it and `set-key`. Never echo the raw key.
2. Before `script` / `preview` / `video`, run `help <topic>` to confirm the schema.
3. For async endpoints (`script`, `video`), capture the returned jobId and use `wait`. `state` comes back lowercase (`processing` / `completed` / `failed`); `wait` matches case-insensitively, exits 0 on `completed` and 1 on `failed`. Submit errors land in the outer envelope (`success:false`), so guard `wait` calls behind a numeric-jobId check.
4. Responses are wrapped `{success, code, message, data, cached}` — always check `.success` first; pipe through `jq '.data'` for payload.
5. For a quick end-to-end demo, `flow <image-url>` chains import → script → video with opinionated defaults (12s / sr2l / 720P / 9:16) and prints `{videoUrl, coverImageUrl, userAssetId, script, ...}` on success. Costs ~12 credits.

## Typical Flow

```
1.  show-config                     → verify key (else set-key)
2.  credits                         → balance
3.  images-options / videos-options → allowed formats + video params
4.  upload <files...>  (or import <urls...>) → assetId + imageUrl
5.  script <<JSON                   → async (2 credits) → jobId
6.  wait <jobId>                    → .data.output.script
7.  videos-queue                    → queue load
8.  preview <<JSON                  → credit cost (no deduct)
9.  video <<JSON                    → submit (credits deducted) → jobId
10. wait <jobId>                    → completed: .data.output.videoUrl (+ coverImageUrl)
                                      failed:    auto-refund, .data.errorMessage
```

## Response Envelope

```json
{"success": true,  "code": null,           "message": null, "data": <payload>, "cached": null}
{"success": false, "code": "<ERROR_CODE>", "message": "...", "data": null,     "cached": null}
```

Check `.success`; on failure read `.code` and `.message`. `.data` carries the payload (object, array, or primitive depending on endpoint). `cached` is API metadata — usually null; ignore unless debugging.

## Error Codes

| Code | HTTP | |
|------|------|-|
| `API_KEY_INVALID` | 401 | missing/invalid key |
| `INSUFFICIENT_BENEFIT` | 402 | not enough credits |
| `RATE_LIMIT_EXCEEDED` | 429 | too many requests |
| `TASK_QUEUE_FULL` | 429 | user queue full |
| `VALIDATION_FAILED` | 400 | bad request |
| `RESOURCE_NOT_FOUND` | 404 | job not found |
