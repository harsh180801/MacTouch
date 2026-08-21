# Release signing + notarization setup

This repository's release workflow (`.github/workflows/release-mactouch-app.yml`) builds and publishes a signed + notarized macOS artifact for each version tag (`v*`).

## Required GitHub Secrets

Add these in **Repository Settings -> Secrets and variables -> Actions**:

1. `APPLE_SIGNING_CERTIFICATE_P12`  
   Base64-encoded `.p12` containing a **Developer ID Application** certificate and private key.

2. `APPLE_SIGNING_CERTIFICATE_PASSWORD`  
   Password used when exporting the `.p12`.

3. `APPLE_API_KEY_ID`  
   App Store Connect API key ID (for notarization).

4. `APPLE_API_ISSUER_ID`  
   App Store Connect issuer ID.

5. `APPLE_API_PRIVATE_KEY`  
   Base64-encoded private key file contents for `AuthKey_<KEY_ID>.p8`.

## How to generate secret values

### A) Export Developer ID certificate as P12

1. Open Keychain Access on your Mac.
2. Locate your **Developer ID Application** certificate.
3. Export it as `.p12` with a password.
4. Convert to base64:

```bash
base64 -i developer_id_app.p12 | pbcopy
```

Paste into `APPLE_SIGNING_CERTIFICATE_P12`.

### B) Prepare App Store Connect API key

1. In App Store Connect, create an API key with notarization permissions.
2. Download `AuthKey_<KEY_ID>.p8`.
3. Convert to base64:

```bash
base64 -i "AuthKey_<KEY_ID>.p8" | pbcopy
```

Paste into `APPLE_API_PRIVATE_KEY`.

## Triggering a signed release

After secrets are set:

```bash
git tag -a v0.1.1 -m "v0.1.1"
git push origin v0.1.1
```

Workflow outputs:

- `MacTouchApp-macos-arm64.dmg` (signed + notarized, recommended)
- `MacTouchApp-macos-arm64.zip` (signed app bundle archive)

## Validation checklist

- Release workflow succeeds in GitHub Actions.
- Release includes `.dmg` and `.zip` assets.
- Downloaded `.dmg` opens without Gatekeeper malware warning.
