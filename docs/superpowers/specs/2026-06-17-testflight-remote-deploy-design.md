# SynthesisArc — Remote TestFlight Deploy Design

**Date:** 2026-06-17
**Author:** Daniel Willitzer (with Claude)
**Status:** Awaiting approval

## Problem

Deploying SynthesisArc to the iPad Pro was blocked by repeated errors in Xcode's
"Resolve Initial Setup Issues" sheet — specifically the
`XcodeCloudKit.Onboarding.WorkspaceUpdater` "Update app name" step, which failed for
every name entered (including "Forge Commander").

**Root cause (verified):** This is the **Xcode Cloud** onboarding wizard — Apple's
CI/CD service, which is the *wrong tool* for on-demand device deployment. Its
WorkspaceUpdater step fails regardless of the name because the project's signing
config is inconsistent: `project.yml` has `DEVELOPMENT_TEAM: ""` while the generated
`project.pbxproj` carries `U8S9ZLXFJ4` in only some configs (drift). The name was never
the real problem.

## Goal

Deploy the app to the iPad Pro **remotely**, without being physically at the MacBook
(which lives in a data closet). The iPad is sometimes docked at the desk (Thunderbolt +
monitor) and sometimes in the field on cellular. The deploy mechanism must work in both
cases.

## Chosen approach: TestFlight (+ both delivery paths)

TestFlight is the correct fit: upload a build once to App Store Connect; the TestFlight
app on the iPad installs it over **any** network including cellular; builds last 90 days.
No cable, no same-network requirement, no Mac nearby at install time.

Rejected alternatives:
- **Direct Xcode install (cable / local wireless dev):** requires iPad + Mac on the same
  network with Xcode driving the install. Fails when the iPad is in the field. Free-ID
  builds also expire in 7 days. ✗
- **Ad Hoc distribution:** installs from anywhere but requires per-device UDID
  registration, manual re-signing per change, and self-hosting the `.ipa`. Clunky for a
  single user. ✗

Daniel chose to set up **both** delivery paths:
1. **Screen-Share GUI archiving** — works immediately once signing is fixed.
2. **SSH headless build/upload script** — true one-command deploy from the field.

## Verified environment facts

| Fact | Value |
|------|-------|
| Authoritative Team ID | `U8S9ZLXFJ4` (cert OU field; Personal Team — `organizationName=Daniel Willitzer`) |
| Cert UID (red herring, NOT a team) | `3WJ6977LZ3` |
| iOS bundle ID | `com.synthesisarc.SynthesisArc-iOS` |
| App name | "Synthesis Arc" (keep — rename was the wizard's idea, not required) |
| Remote access | Mac on Tailscale as `macbook-pro` (100.111.226.82); SSH On; Screen Sharing loaded |
| Tooling | Xcode 26.5, xcodegen 2.45.4 |
| Project type | xcodegen — `project.yml` is source of truth; pbxproj is tracked in git (caused drift) |

## Design

### Component 1 — Fix signing config (source of truth)
All changes go in `project.yml`, NOT the `.xcodeproj` (which is regenerated):
- Set `DEVELOPMENT_TEAM: U8S9ZLXFJ4` in `settings.base`.
- Add `CODE_SIGN_STYLE: Automatic` so Xcode manages certs/profiles.
- Keep app name as "Synthesis Arc" (no rename).
- Run `xcodegen generate`; verify all configs in the regenerated pbxproj carry the team
  uniformly.

**Optional follow-up (NOT in this change):** stop tracking `project.pbxproj` in git and
add it to `.gitignore` to prevent future drift. Flagged separately to avoid scope creep.

### Component 2 — Screen-Share GUI path (works today)
Once Component 1 lands and an App Store Connect app record exists:
1. From the field, Screen-Share into `macbook-pro` over Tailscale.
2. In Xcode: select "Any iOS Device", Product → Archive.
3. Organizer → Distribute App → TestFlight Internal Only → Upload.
4. Xcode auto-creates the distribution cert + provisioning profile.
5. iPad: open TestFlight, install the new build.

### Component 3 — SSH headless path (one-command deploy)
Create in `scripts/`:
- `ExportOptions.plist` — `method: app-store`, `teamID: U8S9ZLXFJ4`, automatic signing,
  upload enabled.
- `deploy-testflight.sh` — bumps build number, runs `xcodebuild archive` then
  `-exportArchive -allowProvisioningUpdates`, uploads to TestFlight. Authenticates with an
  App Store Connect API key.

Usage from the field:
```
ssh devops@macbook-pro 'cd ~/Projects/active/synthesis-arc-mobile && ./scripts/deploy-testflight.sh'
```

## External prerequisites (Daniel, in browser — cannot be done from terminal)

1. **App Store Connect app record** for `com.synthesisarc.SynthesisArc-iOS`
   (first upload fails without it). App Store Connect → Apps → +.
2. **App Store Connect API key (.p8)** for the SSH path — Users and Access → Integrations →
   App Store Connect API → generate (App Manager role). Save the `.p8` to
   `~/.appstoreconnect/private_keys/`. Record the **Key ID** and **Issuer ID**.

## Error handling
- If `xcodegen generate` reports config errors → fix `project.yml`, do not hand-edit pbxproj.
- If archive fails on signing → confirm the API key path/Key ID/Issuer ID and that the app
  record exists.
- If upload reports "no app record" → create it (prereq #1) and retry.
- Personal Team caveat: individual (non-org) accounts CAN use TestFlight but cannot add
  external testers without App Review; **internal testers** (the account holder's own
  devices) work immediately. This covers Daniel's single-user use case.

## Testing / acceptance
- `xcodegen generate` succeeds; regenerated pbxproj shows `DEVELOPMENT_TEAM = U8S9ZLXFJ4`
  in all relevant configs.
- A clean `xcodebuild archive` succeeds for the iOS scheme (signing resolves).
- Screen-Share path: a build appears in TestFlight and installs on the iPad.
- SSH path: `deploy-testflight.sh` completes end-to-end and a new build appears in
  TestFlight.

## Out of scope
- Push-notification entitlements (no `.entitlements` today; not needed for internal TestFlight).
- macOS distribution (focus is iPad/iOS).
- Removing pbxproj from git tracking (flagged as optional follow-up).
