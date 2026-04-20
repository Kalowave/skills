---
name: kaloclip
description: KaloClip Open API CLI — upload/import images, generate scripts, create videos, poll jobs, check credits via /api/open/v1. Use when the user wants to call KaloClip Open API, set up an X-API-Key, or debug its errors. Triggers on "kaloclip", "KaloClip", "Open API" + KaloClip context, "X-API-Key", "视频创作API", "开放接口", "上传图片", "生成视频", "查积分".
---

# KaloClip Open API

AI-powered video generation. Use the bundled CLI (`scripts/kaloclip.sh`). `KALOCLIP_API_KEY` env var overrides the saved file.

## CLI (`scripts/kaloclip.sh`)

One-off setup (human only, not the agent loop):
```bash
./scripts/kaloclip.sh login                 # device-flow: opens /cli-login page in browser,
                                            # key auto-saved to ~/.kaloclip/config.env (0600).
./scripts/kaloclip.sh set-key <api_key>     # non-interactive alternative (headless / no browser)
./scripts/kaloclip.sh show-config           # masked key + config file path
./scripts/kaloclip.sh unset                 # delete config
```

Everything below is agent-driven, composable, and retriable per step:
```bash
./scripts/kaloclip.sh help                  # command list + topics
./scripts/kaloclip.sh help <topic>          # request-body + response schema for one endpoint
./scripts/kaloclip.sh help all              # every schema in one shot
```

### Subcommands

Every step is an independent subcommand. If one fails (network blip, transient server error, rate limit), retry **just that step** — previous results (assetId, scriptJobId, …) stay in the caller's state.

| Command | Purpose |
|---------|---------|
| `credits` / `images-options` / `videos-options` / `videos-queue` | simple GETs |
| `upload <file>...` | POST /images (multipart, 1–6, 5MB each) |
| `import <url>...` | POST /images/import |
| `script` / `preview` / `video` | POSTs — JSON body on stdin |
| `job <jobId>` | poll job status (also `/videos/{jobId}`) |
| `wait <jobId> [interval_s] [max_wait_s]` | poll until `COMPLETED`/`FAILED`; ticks → stderr, final JSON → stdout, exit 0/1 |

**`help <topic>` is the authoritative schema reference** — required/optional fields, enums, valid (duration, model) and (duration, resolution) combos, response shape, rate limit, state flow for `job`. Run it before constructing any JSON body.

### Agent guidance

1. Run `show-config`. If key is `<unset>`, tell the user to run `./scripts/kaloclip.sh login` once themselves (it's a browser-interactive flow; agents can't drive it). Fall back to `set-key <key>` only if the user has the key at hand. Never echo the raw key.
2. Before `script` / `preview` / `video`, run `help <topic>` to confirm the schema — the `(duration, model)` and `(duration, resolution)` rules in particular. Pick matching values; mismatches come back as `400 VALIDATION_FAILED` with a field-level hint you can use to correct.
3. For async endpoints (`script`, `video`), capture the returned jobId and use `wait`. `state` comes back lowercase (`processing` / `completed` / `failed`); `wait` matches case-insensitively, exits 0 on `completed` and 1 on `failed` or timeout. If submit itself returned `success:false`, the JSON has no jobId — guard `wait` behind a numeric-jobId check.
4. Responses are wrapped `{success, code, message, data, cached}` — always check `.success` first; pipe through `jq '.data'` for payload.
5. `login` / `install` / `set-key` / `unset` are interactive one-offs for the user, not part of the agent loop.

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
