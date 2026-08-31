# Cloudflare Containers WITHOUT Docker (apple/container + crane)

**When to use:** you need to deploy a Cloudflare **Container** (Workers Containers /
Sandbox SDK) from a Mac that has **no Docker/Colima** — only `apple/container`
(per the global "Docker removed" policy). CF's own tooling (`wrangler deploy`,
`wrangler containers build`, `wrangler containers push`) all shell out to a
`docker` binary (`--path-to-docker` default `"docker"`), so the happy path needs
Docker. This is the verified Docker-free path.

**Proven end-to-end 2026-06-28** building `claude-worker` (ttyd + Claude Code in a
CF Container, Access-gated). Every step below has real evidence.

## The recipe

### 1. Build linux/amd64 with apple/container (cross-builds on Apple Silicon)
```bash
container build --platform linux/amd64 -t registry.cloudflare.com/<ACCOUNT_ID>/<image>:<tag> .
```
- `apple/container` cross-builds `linux/amd64` on arm64 — verified (`container image
  inspect` → `"architecture":"amd64"`). CF Containers REQUIRE linux/amd64.
- **Private-repo clone inside the Dockerfile** → BuildKit build secret (never a layer):
  ```dockerfile
  RUN --mount=type=secret,id=ghtoken \
      git clone --depth 1 \
        "https://x-access-token:$(cat /run/secrets/ghtoken)@github.com/<owner>/<repo>" /tmp/x && ...
  ```
  ```bash
  GHT=$(mktemp); gh auth token > "$GHT"
  container build --platform linux/amd64 --secret id=ghtoken,src="$GHT" -t <ref> .
  ```
  The `$(cat ...)` resolves at build time, so the token is NOT stored in the RUN
  instruction history.

### 2. Mint a Cloudflare managed-registry credential — MUST be `--push --pull`
```bash
wrangler containers registries credentials registry.cloudflare.com --push --pull --json
# => { "username":"v1", "password":"<JWT, 15-min TTL>", "registry_host":"registry.cloudflare.com" }
```
- **`--push` alone returns a push-only token → 401** on the manifest HEAD that any
  conformant pusher does first (HEAD = a *read*). Always `--push --pull`.

### 3. Push with **crane** (NOT apple/container's pusher)
```bash
container image save -o /tmp/img.tar <ref>          # apple/container -> OCI tar
OCIDIR=$(mktemp -d); tar -xf /tmp/img.tar -C "$OCIDIR"   # crane reads an OCI *directory*
echo "$JWT" | crane auth login registry.cloudflare.com -u v1 --password-stdin
crane push "$OCIDIR" <ref>                            # standard registry push
```
- **CF's registry speaks HTTP Basic auth, not Bearer** — `curl -sI
  https://registry.cloudflare.com/v2/` returns `WWW-Authenticate: Basic realm=...`.
  - apple/container's `image push` FAILS here: `401 ... "missing Bearer challenge in
    WWW-Authenticate header"` (it expects the Docker token-exchange flow). That's the
    tell to switch to crane.
  - `crane` (go-containerregistry, `brew install crane` — a ~5MB Go binary, NOT
    Docker) sends Basic and works.
- **`crane push <tarball>` fails** with `manifest.json not found in tar` — apple/
  container produces an **OCI layout** (`index.json`/`oci-layout`/`blobs/`), not a
  docker-save tar. Extract to a DIR and `crane push <dir>`.
- Quick auth sanity probe: `curl -s -o/dev/null -w '%{http_code}' -u "v1:$JWT"
  https://registry.cloudflare.com/v2/` → `200`.

### 4. Reference the prebuilt image in wrangler.jsonc → deploy pulls it, no build
```jsonc
"containers": [{ "image": "registry.cloudflare.com/<ACCOUNT_ID>/<image>:<tag>", ... }]
```
`wrangler deploy` with an image *reference* (not `./Dockerfile`) builds NOTHING
locally — no Docker needed at deploy. (Docker Hub / ECR refs work the same way if
you'd rather not use CF's registry.)

## Lock the Worker route to one email (Cloudflare Access, via API)
```bash
CF_EMAIL=$(jq -r .email ~/.cloudflared/cf-global-api-key.json)
CF_KEY=$(jq -r '.key // .api_key' ~/.cloudflared/cf-global-api-key.json)
APP=$(curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/<ACCT>/access/apps" \
  -H "X-Auth-Email: $CF_EMAIL" -H "X-Auth-Key: $CF_KEY" -H 'Content-Type: application/json' \
  --data '{"name":"X","domain":"code.example.com","type":"self_hosted","session_duration":"24h"}')
APPID=$(echo "$APP" | jq -r .result.id)
curl -s -X POST ".../access/apps/$APPID/policies" -H ... \
  --data '{"name":"only-me","decision":"allow","include":[{"email":{"email":"you@example.com"}}]}'
```
**Verify the gate (do this — a live ttyd is a root shell):** `curl -sI
https://code.example.com/` must `302` → `*.cloudflareaccess.com/cdn-cgi/access/login`
and the unauth body must contain ZERO app markers. Keep `workers_dev:false`.

## Reuse a host's Claude Code auth inside the container (no `claude setup-token`)
macOS stores it in the keychain, not a file:
```bash
security find-generic-password -s "Claude Code-credentials" -w \
  | jq -c '{claudeAiOauth: .}' \
  | wrangler secret put CLAUDE_CREDENTIALS_JSON
```
The Worker forwards `CLAUDE_CREDENTIALS_JSON` into the container `envVars`; the
entrypoint writes it to `$HOME/.claude/.credentials.json` (subscription auth WITH
refresh — better than a bare `CLAUDE_CODE_OAUTH_TOKEN`, which can't refresh).

## Claude Code in the container MUST run as a non-root user
Claude Code **refuses `bypassPermissions` / `--dangerously-skip-permissions` under
root**: `--dangerously-skip-permissions cannot be used with root/sudo privileges for
security reasons`. A `settings.json` with `"permissions":{"defaultMode":"bypassPermissions"}`
triggers it just like the CLI flag. For an autonomous (no-prompt) terminal you therefore
MUST run as non-root:
- `node:*-bookworm` already ships a `node` user at **UID 1000** — reuse it (`useradd -u 1000`
  collides: "UID 1000 is not unique"). `cp -a $HOME/.claude $HOME/.claude && chown -R
  node:node $HOME /workspace`, `ENV HOME=$HOME`, `USER node`.
- The entrypoint (runs as that user) writes the credential file under `$HOME`, not `/root`.
- **Forcing the running container to pick up a new image:** you CANNOT `kill 1` from inside
  (kernel protects PID 1) and a same-tag digest change does NOT recycle a warm instance.
  `wrangler containers delete <APP_ID>` then `wrangler deploy` recreates it clean → next
  request cold-starts the new image (a few min to provision). Verify in the browser
  (xterm renders to **canvas**, so `wait_for`/DOM-text checks see nothing — screenshot
  instead; `window.term.input('cmd\r')` types+executes, `term.paste()` is bracketed-paste
  and does NOT auto-run).

## Gotcha quick-reference
| Symptom | Cause | Fix |
|---|---|---|
| `wrangler containers push` needs docker | `--path-to-docker` default | use crane path above |
| apple/container push: `missing Bearer challenge` | CF registry is **Basic** auth | push with crane |
| crane: `manifest.json not found in tar` | apple/container emits **OCI layout** | extract tar → `crane push <dir>` |
| crane/push: `401` on manifest HEAD | credential is **push-only** | mint `--push --pull` |
| `npx wrangler` prints socket-wrapper help | `socket` npm wrapper hijacks npx | call `./node_modules/.bin/wrangler` |

Reference build: `~/claude-worker` (repo `<you>/claude-worker`), 2026-06-28.
