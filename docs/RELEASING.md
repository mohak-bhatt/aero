# Releasing Aero alpha builds

Aero checks `https://api.github.com/repos/<owner>/<repo>/releases` for a release newer than the running
version (`CFBundleShortVersionString`). **The repo must be public** (the API call has no token).

## One-time setup
1. In `Browser/UpdateManager.swift` set `repo = "your-username/aero"`.
2. Install the GitHub CLI: `brew install gh`, then `gh auth login`.

## Each release
1. Bump **Version** (Target → General → Identity) to e.g. `0.1.1` — it must be higher than the last release.
2. Commit, then run `./scripts/release.sh 0.1.1`.
   It builds a Release app, zips it as `Aero.zip`, and publishes a GitHub pre-release tagged `v0.1.1`.
3. Friends' running copies see the blue **Update Now** button (or use Aero → Check for Updates…).

## Friends installing the first alpha
Unzip `Aero.zip`, drag `Aero.app` to Applications. The build is ad-hoc signed, so macOS will block the first
launch: right-click → Open, or run `xattr -dr com.apple.quarantine /Applications/Aero.app`.
After that, updates install themselves (the app must not be sandboxed to replace itself; if it can't, "Update Now"
opens the release page instead).
