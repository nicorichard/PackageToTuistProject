---
name: release-process
description: How to cut a release of PackageToTuistProject — version bump, tagging, and the GitHub Actions release workflow. Use this whenever the user wants to ship, release, tag, publish, or cut a new version of this tool, or asks how releases work for this project. Trigger on phrases like "release 0.0.8", "ship a new version", "cut a release", "tag X.Y.Z", or "publish to GitHub releases". Also use when the user asks why caches aren't invalidating between versions or how the artifact bundle is built.
---

# Release process

## What gets released

Each release publishes two assets to a GitHub release tagged `X.Y.Z` (no `v` prefix):

- `PackageToTuistProject-X.Y.Z-macos-arm64.tar.gz` — raw binary tarball
- `PackageToTuistProject.artifactbundle.zip` — SwiftPM/Tuist artifact bundle (this is what downstream `package.swift` consumers point at)

Both are built by `.github/workflows/release.yml`, which fires on `release: created`. There is no manual build step — tagging a release is the trigger.

## Why the toolVersion constant matters

`Sources/PackageToTuistProject/PackageToTuistProjectCommand.swift` has:

```swift
let toolVersion = "X.Y.Z"
```

This constant is written into every `.package-description.json` cache file the tool generates. On each run, the loader compares the cached constant against the current one — if they differ, the cache is discarded. **Bumping this is how end users get their caches invalidated when a new version ships.** Forgetting to bump it means users on the new release silently keep stale cached package descriptions (potentially missing fields the new version knows how to read).

CI also `sed`-injects the tag into this constant at build time (see workflow step "Inject version into source"), so the binary always reports the right version. But the source on `main` should still be bumped pre-release so:

- Source-built users get the right version string and cache-bust.
- The commit history records when the cache contract changed.

## Pre-flight checklist

1. **Everything you want shipped is merged to `main`.** No PRs in flight.
2. **Working tree clean** on `main`: `git status` shows nothing.
3. **Bump `toolVersion`** in `Sources/PackageToTuistProject/PackageToTuistProjectCommand.swift` to the new `X.Y.Z`. Commit on `main`:
   ```
   git commit -am "Bump toolVersion to X.Y.Z"
   git push origin main
   ```
4. **Tests pass**: `swift test` — every test green. The project's CLAUDE.md is firm on this; don't skip.

## Cut the release

```
gh release create X.Y.Z --generate-notes
```

The tag name *is* the version — no `v` prefix. `--generate-notes` produces release notes from PRs/commits since the last tag; edit them in the GitHub UI afterward if needed.

Alternative: create the release through the GitHub web UI. Either way, the workflow trigger is `release: created`, not `push: tags`, so pushing a tag without creating a release does nothing.

## What CI does (so you know what to wait for)

On `release: created`, `.github/workflows/release.yml` runs on `macos-26`:

1. Checks out the repo.
2. Reads the tag name into `${VERSION}`.
3. `sed`-injects `${VERSION}` into `let toolVersion = "..."`.
4. `swift build -c release --arch arm64`.
5. Assembles `PackageToTuistProject.artifactbundle/` (info.json + binary), zips it.
6. Tars the raw binary as `PackageToTuistProject-${VERSION}-macos-arm64.tar.gz`.
7. `gh release upload X.Y.Z <both files> --clobber` attaches both assets.

Typical runtime is a couple of minutes. Watch with `gh run watch` if you want to.

## Verify the release

```
gh release view X.Y.Z
```

The output should list both assets:

- `PackageToTuistProject-X.Y.Z-macos-arm64.tar.gz`
- `PackageToTuistProject.artifactbundle.zip`

If either is missing, check `gh run list --workflow release.yml` for a failed run.

## Troubleshooting

**Workflow didn't run.** It triggers on `release: created`, not on tag push. If you created a tag with `git tag X.Y.Z && git push --tags` and stopped, no release exists yet. Run `gh release create X.Y.Z --generate-notes` to create the release from the existing tag.

**Workflow ran but failed at `gh release upload`.** Check `gh run view <run-id> --log-failed`. The `--clobber` flag is there so re-runs overwrite cleanly; a manual rerun from the Actions UI should fix it once the underlying issue is resolved.

**Binary reports the wrong version.** That means the `sed` injection step failed silently (e.g., the regex in the workflow didn't match because the line in `PackageToTuistProjectCommand.swift` was reformatted). Verify the line still matches the pattern `let toolVersion = ".*"` and that no other line shares that pattern.

**Caches didn't invalidate for users on the new release.** The `toolVersion` constant in source on `main` wasn't bumped before the tag. The binary is correct (CI injects it), but anyone tracking `main` from source will not get the bump. Fix forward: bump it now, ship a patch release.
