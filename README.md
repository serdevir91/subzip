# SubZip

SubZip is a Flutter-based file manager and archive utility focused on ZIP workflows, background file operations, and folder customization.

## Core Features

- File/folder browse, search, create, rename, delete
- ZIP compress and extract operations
- Background task queue (copy, move, delete, archive, conversion)
- Favorites and dashboard shortcuts
- Theme support: light / dark / system with AMOLED-style dark palette
- Startup update check and in-app review prompt support

## Security Controls

- Local-first processing: file operations run on the device; no remote file upload in core flow.
- Permission-gated startup: Android permissions are requested before privileged operations.
- Signed release workflow: Android release signing uses `android/key.properties` (not tracked in git).
- Dependency linting baseline: run `flutter analyze` before release.
- Secret hygiene: scan source before push:

```bash
rtk rg -n "AIza|api[_-]?key|secret|token|password|private_key" -S lib android ios
```

## Android Permissions (Why Needed)

SubZip handles archive and file-management operations. For Android, storage/media permissions are requested to access user files and perform ZIP operations. Keep Play policy alignment under regular review, especially for broad storage scopes.

## Release Channels

- Google Play: [SubZip on Google Play](https://play.google.com/store/apps/details?id=www.subzip.app)
- Windows package: distributed via GitHub Releases assets

## Release Safety Checklist

1. Run static checks:
```bash
rtk flutter analyze
```
2. Validate no secrets are committed:
```bash
rtk rg -n "AIza|api[_-]?key|secret|token|password|private_key" -S lib android ios
```
3. Build artifacts from clean state and verify signing.
4. Publish only required artifacts to GitHub Release.
5. Attach Windows installer/package and include Play Store link in release notes.

## Development

```bash
rtk flutter pub get
rtk flutter run
```

## License

Proprietary / All rights reserved unless explicitly stated otherwise.
