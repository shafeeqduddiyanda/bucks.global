# Incident: `curl -fsSL https://bucks.global/install | bash` fails for real users

**Status:** Fix implemented and verified on branch `fix/install-gateway-robustness`. **Not merged to `main`, not deployed.**
**Date:** 2026-08-17

## Summary

The public one-line installer for Bucks Browser was broken in production. New
users running the documented install command got a hard failure with no
working fallback, because the release tarball — while correctly referenced
by CID in `version.json`, `install`, and `install.ps1` — was not actually
reachable from any public IPFS gateway.

## Functionality breakdown (what the installer does)

1. `install` / `install.ps1` are fetched and piped into `bash`/`iex` by the
   user.
2. The script checks for an existing good install at `~/.bucks/bucks-browser`
   and skips straight to dependency install if one is found.
3. Otherwise it needs the release tarball (`bucks-browser-dist.tar.gz`,
   ~13.5MB). It tries, in order:
   - A copy sitting next to the script locally (rare — power-user/offline
     path).
   - Four public IPFS gateways (`ipfs.io`, `dweb.link`, `w3s.link`,
     `nftstorage.link`) resolving the CID pinned in `BUCKS_CID` /
     `$BucksCid`.
   - *(new, this fix)* A same-origin HTTPS mirror at
     `https://bucks.global/dl/bucks-browser-dist.tar.gz`.
   - If everything fails, it prints manual recovery steps and exits 1.
4. Once downloaded, the tarball is extracted into `~/.bucks/bucks-browser`
   and `npm install` / first-run happens.

## Root cause

The release referenced by `version.json` (v1.1.0, CID
`bafybeifdjsptd56c5gt4pcsx5w7soo2opoylcdcpoyipdk2ynaybdtklgy`) was pinned
**only on a local, NAT'd IPFS node** (see [[project_bucks_global_site]] /
[[project_cluster_membership]] in prior session notes — the cluster's
IPFS-native release pipeline pins through `build-and-pin-release.js` against
a local Kubo/Helia bridge, not a public pinning service). A NAT'd node has no
inbound reachability, so:

- The CID is valid and the content is real, but no public gateway can ever
  find a provider for it via the DHT.
- All four gateways (`ipfs.io`, `dweb.link`, `w3s.link`, `nftstorage.link`)
  returned `504 Gateway Timeout` when tested against this CID — confirmed
  independently by the debugging session that opened this incident.
- The installer's *only* other path was "manual recovery," which for a
  first-time user running a one-line curl command is effectively a hard
  failure — they have no local copy, no CID they can independently resolve,
  and no reason to suspect the fix is "go find a different gateway."

This is a **release-infra gap**, not a bug in the install script logic
itself: the script always did the right thing with the inputs it was given
(try several gateways, verify what comes back), it just had no path to the
bits when IPFS as a whole was unreachable for this CID.

## The fix

Two parts, following the decision to make the previously-stubbed HTTPS
fallback real rather than merge with it still pointing at a 404:

### 1. Install script robustness (already on this branch, unchanged by this session)

- `--connect-timeout 8` on every gateway attempt, so a dead/firewalled host
  fails in ~8s instead of eating the full 120s `--max-time` budget meant for
  an actual slow transfer.
- `BUCKS_SHA256`, a hardcoded hash of the exact release tarball, checked via
  a new `is_valid_download()` that layers on top of the existing
  gzip-magic-byte check. The magic-byte check alone only catches a gateway
  serving an HTML error page — it does **not** catch a connection that drops
  mid-transfer, because a truncated file still starts with valid gzip bytes.
  Verified below.
- The new HTTPS mirror fallback: `https://bucks.global/dl/bucks-browser-dist.tar.gz`,
  tried after all four gateways fail. Same-origin to the site itself, so it
  fails independently of IPFS being reachable at all — a distinct failure
  domain from "gateway can't find a DHT provider."
- Friendlier terminal failure message: explains the failure is very likely
  transient network/gateway trouble rather than a broken release, gives a
  retry command, lists all fallback URLs (mirror included) for manual
  fetch, and points at the GitHub issues page.

### 2. This session: made the mirror real

- Located the verified release tarball
  (`Bucks Core/bucks-browser-dist.tar.gz`, 13,509,655 bytes) and confirmed
  its SHA256 (`5922b76129929cfe963a89259917d21206d7c3c5a33a574deb98fa4be106ceae`)
  matches the `BUCKS_SHA256` constant already hardcoded into `install` /
  `install.ps1` by the earlier session — i.e. this is the exact file that
  hash was computed against, not a guess.
  - Note: attempting to independently re-derive the IPFS CID for this file
    via the local `ipfs` CLI (`ipfs add --only-hash --cid-version=1`) does
    **not** reproduce `bafybeifdjsptd56c5gt4pcsx5w7soo2opoylcdcpoyipdk2ynaybdtklgy`.
    This is expected, not a red flag: the release pipeline
    (`build-and-pin-release.js`) pins through a Helia-backed bridge
    (`/api/v0/add`), whose default UnixFS chunker/raw-leaves settings are not
    guaranteed to match the `kubo` CLI's defaults, so CID reproduction this
    way isn't a meaningful check. SHA256-of-bytes is the check that actually
    matters here, and it matches exactly.
  - Also confirms the file is a different, older build than the *other*
    tarball on disk at `bucks browser/bucks-browser-dist.tar.gz` (38.8MB,
    different hash) — that one was not used.
- Committed the tarball to the repo at `dl/bucks-browser-dist.tar.gz`, which
  is the site's static-asset root convention here (plain static site served
  from the repo root — `vercel.json`/`_headers` already reference `/install`
  and `/install.ps1` the same way; no `public/` prefix, this isn't
  Next.js-style).
- Added `Content-Type: application/gzip` for that path in both `vercel.json`
  and `_headers` (the site apparently ships headers config for two
  platforms — kept both in sync). Deliberately used `Cache-Control: no-cache`
  (revalidate-before-use), matching the existing convention for `/install`
  and `/install.ps1`, **not** a long-lived/immutable cache — see Edge case
  analysis below for why.

## Verification performed

Ran the actual functions from `install` (`is_valid_gzip`, `sha256_of`,
`is_valid_download`) sourced verbatim into a throwaway test harness, against
a local HTTP server standing in for the mirror (no DNS/hosts changes made —
gateway hosts in the fallback loop were pointed at nonexistent test domains
instead, which fail fast the same way a real outage does):

| Case | Gateways | Mirror | Result |
|---|---|---|---|
| Gateways down, mirror has the correct tarball | 4/4 fail (fast, ~3s each) | serves `dl/bucks-browser-dist.tar.gz` | `DOWNLOADED=true`, hash verified — **matches production behavior once deployed** |
| Gateways down, mirror unreachable | 4/4 fail | connection refused | `DOWNLOADED=false` → falls through to the manual-recovery message, exit 1 (correct — no silent bad state) |
| Mirror serves a truncated file (5MB of a 13.5MB tarball) | n/a | truncated but starts with valid gzip magic bytes | `is_valid_gzip` → **true** (would have false-passed under the old logic), `is_valid_download` → **false**, correctly rejected on hash mismatch |

All three match the intended design. The third case is the specific failure
mode the hash-check comment in the script was written to close, and it's
now confirmed to actually close it, not just documented as closing it.

Local test servers were torn down after verification; nothing was left
running.

## Edge case analysis

- **Filename reuse across releases.** `dl/bucks-browser-dist.tar.gz` is not
  version-namespaced. On the next release, this file gets manually
  overwritten in place. If it had been given a long-lived/immutable
  `Cache-Control`, a CDN edge or client that cached the v1.1.0 bytes could
  keep serving them after v1.2.0 ships with a new `BUCKS_SHA256` — and
  because the mirror is the *last* fallback with no further recovery inside
  the script, that would surface as a confusing hash-mismatch failure on a
  path that "should" work. Using `no-cache` (revalidate) avoids this; the
  tradeoff (slightly less efficient repeat fetch) is irrelevant here since
  each real user hits this URL at most once per install.
- **`BUCKS_SHA256` and `BUCKS_CID` can drift independently.** Nothing
  enforces that the mirror file, the hardcoded hash, and the pinned CID all
  describe the same bytes on a future release — that's a manual,
  three-place update (`version.json` CID, `install`/`install.ps1` hash
  constant, and this file). Worth a follow-up: have
  `build-and-pin-release.js` write the mirror copy and hash constant
  automatically instead of relying on someone remembering all three.
- **Mirror depends on `bucks.global` itself being up**, which is a narrower
  but nonzero shared-fate risk with the gateways (all of it depends on DNS
  resolving and *some* HTTPS endpoint being reachable). It's still strictly
  better than before: previously a DNS/network partition from IPFS
  specifically was unrecoverable even though the site itself was fine.
- **Repo bloat.** This adds a ~13.5MB binary directly into git history on
  this branch. Every future release that updates this file adds another
  ~13.5MB+ to the repo's history (git does not diff binary blobs
  efficiently), and every clone of this repo now pays for all of them
  forever. This is fine as an immediate unblock but is **not** the right
  long-term home for release binaries.

## Recommendation (not implemented, not blocking)

Move `dl/bucks-browser-dist.tar.gz` to Vercel Blob storage (already on this
stack) or a CDN, and have the install script's mirror URL point there
instead of a same-origin static path. Keeps the fallback same-origin in
spirit (still bucks.global-controlled, still independent of IPFS) without
growing the git repo on every release. Out of scope for this fix — the goal
here was to make the already-coded fallback actually work today.

## Still open after this fix

- **The real fix is public IPFS pinning**, not this mirror. The release
  needs to be pinned through a public pinning service (web3.storage,
  Pinata, etc.) so the CID resolves from any gateway without depending on
  bucks.global or a NAT'd local node at all. This HTTPS mirror is a
  last-resort safety net, not a replacement for that.
- This branch is **not merged to `main`** and **not deployed**. The live
  site at bucks.global still has the old install script without this
  fallback until this is reviewed and merged.
