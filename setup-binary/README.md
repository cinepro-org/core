# CinePro Manager for Windows

![CinePro logo](https://avatars.githubusercontent.com/u/196096730?s=200&v=4)

CinePro Manager is the Windows setup and control app for CinePro Core. It is meant to make the local setup feel normal for people who do not want to clone a repo, run Git commands, install random tools, or guess which env value is missing.

CinePro Manager is published for:

```text
CinePro Foundation
CinePro Foundation — The Home of Open-Source Streaming, Built by the Community for the Community
https://github.com/cinepro-org
```

The first Windows version focuses on a tight scope:

- install CinePro Core into a user selected folder
- install the CinePro UI from the current `main` branch
- update Core through signed release assets
- update the UI by checking the latest `main` commit
- update the manager itself from verified setup assets
- keep install and update operations recoverable after crashes or restarts
- manage a bundled Node runtime
- edit and validate `.env`
- start and stop Core from the manager
- start, stop, and clear a managed Redis cache through Docker
- open the backend and frontend from the manager
- keep logs hidden on first launch and reveal them when needed
- show closable notices when files or services change outside the manager
- expose Windows only keyboard shortcuts from the three dot menu
- open bug reports and changelogs from the manager
- uninstall managed Core files with a clear confirmation prompt

This folder is intentionally separate from the backend code. The manager adapts around CinePro Core without changing the existing Core source.

## Project Layout

```text
setup-binary/
  README.md
  installer/
    cinepro-manager.iss
  manager/
    assets/
      cinepro-logo.png
    lib/
      main.dart
      src/
        app.dart
        manager_controller.dart
        models/
        services/
        theme/
    pubspec.yaml
    pubspec.lock
  prototype/
    assets/
      cinepro-logo.png
```

`manager` is the Flutter desktop app.

`installer` contains the Inno Setup script used to package the built Windows manager.

`prototype` currently only keeps the original logo asset that was already present.

## Windows Development Prerequisites

To test the manager and installer locally on Windows, install:

- Flutter with Windows desktop support enabled
- Visual Studio with the `desktop development with c++` workload
- Inno Setup

Check Flutter first:

```powershell
flutter doctor -v
```

The Windows section must be clean before `flutter build windows` can produce the exe.

If Flutter says Windows desktop is disabled:

```powershell
flutter config --enable-windows-desktop
```

If Flutter says Visual Studio is missing, install Visual Studio from:

```text
https://visualstudio.microsoft.com/downloads/
```

During Visual Studio install, select:

```text
desktop development with c++
```

Inno Setup is only needed after the Flutter release build exists. If `ISCC.exe` is not on PATH, either open the `.iss` file in Inno Setup Compiler or add the Inno Setup install folder to PATH.

Common `ISCC.exe` paths are:

```text
C:\Program Files (x86)\Inno Setup 7\ISCC.exe
C:\Program Files\Inno Setup 7\ISCC.exe
C:\Program Files (x86)\Inno Setup 6\ISCC.exe
C:\Program Files\Inno Setup 6\ISCC.exe
```

Check from PowerShell:

```powershell
where.exe ISCC
Test-Path "C:\Program Files (x86)\Inno Setup 7\ISCC.exe"
Test-Path "C:\Program Files\Inno Setup 7\ISCC.exe"
Test-Path "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
Test-Path "C:\Program Files\Inno Setup 6\ISCC.exe"
```

If both checks fail, Inno Setup is probably not installed or not installed in the default location.

## What The Manager Does

The manager is designed as a Windows control center for Core, not just a one time installer.

The current implementation includes:

- a minimal Flutter UI using the CinePro logo and the `#F30F17` accent color
- a native Windows title bar with the CinePro icon and `cinepro manager` title
- a log panel that slides in only after an action starts or the user opens it
- a folder picker for the install location
- GitHub release lookup
- signed release manifest verification
- SHA256 verification before extraction
- safe ZIP extraction
- crash recovery through `state.json`
- staged install and update flow
- previous version retention for rollback
- bundled Node runtime handling
- `.env.example` based env editor
- required `TMDB_API_KEY` validation before startup
- process supervision with Windows job objects
- service exit tracking when Core or UI closes outside the manager
- Docker and Redis checks through cli, daemon, service, process, and container state
- a manager app folder readout that shows where setup installed the manager
- app logs with a clear logs action
- a smoke test that taps the main widgets and buttons
- a language menu that currently ships with English and leaves room for translations
- a three dot menu for manager updates, shortcuts, language, bug reports, and foundation info
- an update indicator dot when a verified manager update is available
- uninstall confirmation with separate options for Core files and logs

The app does not blindly download the GitHub source ZIP and run it. It expects a manager ready release asset that can be verified before anything is extracted.

## Why Signed Manifests Are Required

GitHub release pages can expose source archives, but those archives are not enough for a mature launcher. The manager needs to know exactly what it is installing.

The release workflow should publish these assets:

```text
cinepro-core-windows-x64.zip
cinepro-core-windows-x64.manifest.json
cinepro-core-windows-x64.manifest.sig
node-v24.x-win-x64.zip
```

The manifest should describe the Core package and the runtime package:

```json
{
  "schema": 1,
  "name": "cinepro-core",
  "tag": "main-98ba005",
  "commit": "98ba005...",
  "asset": {
    "name": "cinepro-core-windows-x64.zip",
    "url": "https://github.com/cinepro-org/core/releases/download/main-98ba005/cinepro-core-windows-x64.zip",
    "sha256": "...",
    "size": 12345678
  },
  "runtime": {
    "nodeVersion": "24.16.0",
    "url": "https://github.com/cinepro-org/core/releases/download/main-98ba005/node-v24.16.0-win-x64.zip",
    "sha256": "...",
    "size": 34567890
  },
  "minManagerVersion": "0.1.0",
  "publishedAt": "2026-06-03T00:00:00.000Z"
}
```

The `.manifest.sig` file should be an Ed25519 signature of the raw manifest bytes.

The manager flow is:

1. download the manifest
2. download the manifest signature
3. verify the manifest with the embedded Ed25519 public key
4. download the ZIP asset
5. verify downloaded byte count
6. verify SHA256
7. inspect ZIP paths
8. extract into staging
9. validate expected Core files
10. swap staging into the active install

If any check fails, extraction does not happen.

## Ed25519 Key Setup

The manager currently has a placeholder public key in:

```text
setup-binary/manager/lib/src/manager_controller.dart
```

Look for:

```dart
static const releaseManifestPublicKeyBase64 =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
```

Before real installs, replace this with the real base64 encoded Ed25519 public key.

The private key should only live in the release pipeline secret store. Do not commit it to the repository.

Generate the key pair from the manager folder:

```powershell
cd setup-binary\manager
dart run tool\generate_release_keys.dart
```

That prints two values:

```text
CINEPRO_RELEASE_PUBLIC_KEY_BASE64=...
CINEPRO_RELEASE_PRIVATE_KEY_BASE64=...
```

Use them like this:

- put `CINEPRO_RELEASE_PUBLIC_KEY_BASE64` into `releaseManifestPublicKeyBase64` in `manager_controller.dart`
- put `CINEPRO_RELEASE_PRIVATE_KEY_BASE64` into GitHub Actions secrets
- do not put the private key in the repo, a release asset, or a local config file that gets committed

The public key is safe to commit because it only verifies signatures. The private key signs releases, so anyone with that key can produce manifests the manager trusts.

Sign a manifest locally or in CI:

```powershell
cd setup-binary\manager
$env:CINEPRO_RELEASE_PUBLIC_KEY_BASE64="public-key-from-generate-script"
$env:CINEPRO_RELEASE_PRIVATE_KEY_BASE64="private-key-from-generate-script"
dart run tool\sign_release_manifest.dart path\to\cinepro-core-windows-x64.manifest.json path\to\cinepro-core-windows-x64.manifest.sig
```

A simple signing flow should look like this:

```text
release workflow
  build cinepro-core-windows-x64.zip
  compute sha256
  build node runtime zip or download the pinned runtime
  compute sha256
  write manifest json
  sign manifest json with private ed25519 key
  upload zip, manifest, and signature to github release

manager
  downloads manifest and signature
  verifies with embedded public key
  trusts only the signed manifest contents
```

The important part is that the manager trusts the signature, not the release page text.

## Manager App Updates

Core/UI updates and manager app updates are separate.

Core/UI updates happen inside the manager. Manager app updates replace the installed Flutter manager itself, so the flow is:

1. the manager checks the latest Core release
2. the release must include a setup exe named like `cinepro-manager-setup-0.2.0.exe`
3. the release must include a matching checksum asset, for example `cinepro-manager-setup-0.2.0.exe.sha256`
4. the manager reads the checksum before downloading the setup exe
5. the manager downloads the setup exe into a temporary update folder
6. byte count and SHA256 are verified before launch
7. the verified setup exe is launched
8. the manager exits so Inno Setup can close and replace installed files cleanly
9. Windows requests elevation through UAC because setup installs under Program Files
10. after setup completes, the user can launch the updated manager from setup, Start Menu, or Desktop shortcut

The manager refuses to run an unsigned Core install, and it also refuses to launch a manager setup update when the checksum asset is missing or invalid.

The three dot menu handles manager updates:

- when no update is known, it shows `Check Manager Updates`
- when a verified newer setup asset exists, the menu shows `Update Manager`
- the three dot button shows a small red dot while the update is ready
- `Changelog` opens the Core releases page so the user can read what changed
- `Report Bug` opens the Core issues page

Release workflow requirement:

```text
cinepro-manager-setup-0.2.0.exe
cinepro-manager-setup-0.2.0.exe.sha256
```

The setup exe should also be code signed in the release workflow when a signing certificate is available. SHA256 protects the download from corruption and mismatch. Code signing gives Windows and users a stronger publisher trust signal.

## Frontend Main Branch Handling

The CinePro UI repo currently does not publish GitHub releases.

Repo:

```text
https://github.com/cinepro-org/ui
```

Branch archive:

```text
https://github.com/cinepro-org/ui/archive/refs/heads/main.zip
```

Because there is no UI release page yet, the manager uses a different flow for the frontend:

1. query the GitHub API for the current `main` branch commit
2. download the `main` branch archive
3. write the archive to a temporary `.part` file first
4. verify the completed byte count when GitHub provides a content length
5. compute and record the downloaded SHA256
6. inspect ZIP paths before extraction
7. extract into `ui/staging`
8. validate that the archive contains a UI package
9. swap `ui/staging` into `ui/current`
10. record the installed UI commit in `cinepro-managed-install.json`

This is good enough for branch based development updates, but it is not as strong as the Core signed release flow. A future UI release workflow should publish a signed UI manifest too, especially if the manager becomes the official desktop control center.

The manager still always follows `main` for UI because that is the current project shape. It records the commit so the app can show which UI revision is installed and whether a newer main commit is available.

## Safe Extraction

The manager uses the Dart `archive` package, not 7zip.

7zip is a good tool, but it does not automatically make the install safer. The security comes from verification and strict extraction rules.

The safe extractor rejects:

- absolute paths
- Windows drive paths
- parent paths like `..`
- null bytes
- symlinks
- archives with too many files
- archives that expand past the configured size limit
- any destination path that escapes the staging folder

The install never extracts directly into the active Core folder. It extracts into staging first, validates the result, then swaps folders.

## Crash Recovery

The manager writes operation state to:

```text
%LOCALAPPDATA%\CinePro Manager\state.json
```

The state tracks:

- current operation
- phase
- install path
- current tag
- target tag
- staging path
- backup path
- timestamps
- user readable status

On startup, the manager checks for unfinished work.

If an install or update was interrupted before the swap, staging is cleaned.

If interruption happened during the swap, the manager checks `current` and `previous`, then finishes the safe state or restores the previous version.

The manager also watches the selected CinePro Content Folder while it is open. If the managed Core folder, UI folder, or bundled runtime is removed outside the manager, it shows a closable notice with an `x` button and writes the problem to the log. A periodic fallback check runs too, because filesystem watchers can miss events on some Windows setups.

## Runtime Strategy

The manager prefers a bundled Node runtime.

That means normal users should not need to install Node globally, change PATH, use winget, or care which Node version happens to be on the machine.

The release manifest pins the runtime version. The manager downloads and verifies that runtime the same way it verifies Core.

The goal is predictable behavior:

```text
same core build
same node runtime
same startup command
same env validation
```

This avoids the usual local setup problem where one user has Node 20, another has Node 22, and another has a broken global npm install.

## App Data And Install Folders

The Inno setup installs the manager app itself into the setup selected folder. By default that is:

```text
C:\Program Files\CinePro Manager
```

The manager shows this as:

```text
Manager App Folder
```

That folder contains the manager exe, Flutter runtime files, assets, and shortcuts created by setup. The user does not need to download the manager again after setup. The setup success page can launch CinePro Manager immediately, and the Start Menu shortcut points to the installed manager exe.

Manager state and logs are stored under:

```text
%LOCALAPPDATA%\CinePro Manager
```

The default Core install folder is:

```text
%LOCALAPPDATA%\CinePro
```

The manager shows this as:

```text
CinePro Content Folder
```

Core, UI, runtime, downloads, staging, and rollback folders live here. Keeping this folder under local app data avoids normal user runs needing admin rights just to update Core/UI or write logs.

Inside that folder the manager uses:

```text
current/
previous/
staging/
runtime/
ui/current/
ui/previous/
ui/staging/
downloads/
cinepro-managed-install.json
```

`cinepro-managed-install.json` is important. The uninstall flow only removes the Core install folder when this marker exists and says the folder is managed by CinePro Manager.

This prevents accidental deletion of a folder the user selected manually.

## Starting CinePro Services

The manager starts Core with the bundled Node runtime:

```text
runtime/node.exe current/dist/server.js
```

Before starting Core it checks:

- Core is installed
- bundled Node exists
- `dist/server.js` exists
- env values are loaded
- `TMDB_API_KEY` is not empty and not the placeholder value

After Core starts, the manager tries to start the frontend from:

```text
ui/current/
```

The frontend startup path is:

1. check that `ui/current/package.json` exists
2. check that bundled `npm.cmd` exists
3. install frontend dependencies once with `npm ci` when `package-lock.json` exists, otherwise `npm install`
4. choose the first available frontend script in this order: `start`, `preview`, `dev`
5. choose an available local frontend port starting near the service manifest port
6. start that script under the same Windows process supervisor
7. read frontend stdout and stderr until the web service announces its real local URL

The manager gives the frontend these useful env values:

```text
HOST=127.0.0.1
PORT=selected-frontend-port
VITE_HOST=127.0.0.1
VITE_PORT=selected-frontend-port
CORE_URL=http://host:port
CINEPRO_CORE_URL=http://host:port
VITE_CINEPRO_CORE_URL=http://host:port
```

That keeps the backend and frontend from fighting over the same port by default. The preferred frontend port is currently `5173`, but the manager checks whether it is free before startup. If it is busy, the manager tries the next nearby ports.

The Open Frontend action does not trust a hardcoded URL. It starts with a safe local fallback, then updates when the frontend process prints a URL such as:

```text
Local: http://localhost:5174/
```

The detector ignores backend env URLs, normalizes wildcard hosts like `0.0.0.0` to `localhost`, strips ANSI terminal color codes, and prefers local URLs over network URLs. The manager does not change the frontend repo. It adapts around the scripts that the frontend package already exposes.

The Services panel has an `Open` menu:

- `Open Backend` opens the Core URL in the default browser
- `Open Frontend` opens the frontend URL in the default browser

The menu items are only active when the manager knows that service is running.

The current Core repo source does not produce a manager ready release yet. The manager expects the release package to include built output under `dist/`.

Until the release workflow publishes manager ready packages, the app will show that the package is not ready for manager startup.

## Redis And Docker

The manager has a Redis Cache panel for users who want Redis backed caching.

It checks Docker through several signals before taking action:

- `docker` on PATH
- `docker info` for daemon readiness
- `docker compose version` for compose availability
- Docker Desktop process on Windows
- `com.docker.service` state on Windows
- existing `cinepro-redis` container state
- whether port `6379` is already occupied

The managed Redis container is:

```text
name: cinepro-redis
image: redis:7-alpine
port: 6379
```

Redis actions:

- `Check Docker` updates the visible Docker and Redis state
- `Start Redis` creates or starts `cinepro-redis`
- `Stop Redis` stops `cinepro-redis` without deleting it
- `Clear Redis Cache` runs `redis-cli FLUSHDB` inside the managed container

The clear action always checks Docker and Redis first. If Docker is missing, the daemon is stopped, the container is absent, or Redis is not running, the manager shows a clear status and writes a short log entry instead of running a blind command.

When Redis starts successfully and env values are loaded, the manager prepares these values in memory:

```text
CACHE_TYPE=redis
REDIS_HOST=localhost
REDIS_PORT=6379
```

The user can then save env values from the Environment panel.

If `CACHE_TYPE=redis` but Redis is not running when CinePro starts, the manager shows a closable notice and writes a log line. It does not hide that problem because Core may fail or fall back depending on its own cache behavior.

## Stopping Core When The App Closes

The manager starts child services under a Windows job object.

When the manager exits, the job object allows Windows to clean up child processes that were started by the manager.

This is used so Core and future frontend services do not keep running silently after the user closes the manager.

The UI also has a manual `stop all` action.

If Core or the frontend exits outside the manager, for example from Task Manager or another terminal, the manager records that as:

```text
core closed outside the manager with code ...
frontend closed outside the manager with code ...
```

The visible running badges update, and a closable notice appears in the top right of the app.

## System Tray Behavior

The manager uses the native Windows minimize button.

When the window is minimized, it hides to the system tray instead of staying visible on the taskbar.

Tray behavior:

- left click the tray icon to reopen the manager
- right click the tray icon to open the tray menu
- the tray menu shows a title row, then `Open`, then `Exit`
- `Open` restores and focuses the manager
- `Exit` closes the manager and lets normal cleanup run

The tray package does not expose native bold styling for menu items. The title row is disabled and placed above the menu actions so it behaves like a small header.

Important manager errors call the desktop shell service and bring the manager window back to the front.

The manager still has a normal maximize button. Resize is limited so the UI cannot be squeezed below the safe layout size or stretched into an awkward shape.

Native bounds:

```text
minimum: 900x640
maximum: 1680x1120
default: 1280x720
```

## Manager Menu, Language, And Shortcuts

The three dot menu is the compact place for secondary controls:

- check or run a manager app update
- open the changelog
- report a bug
- view keyboard shortcuts
- choose language
- view CinePro Foundation information

The language menu currently ships with English. More languages can be added later by moving display text into a small translation map instead of scattering strings through the widgets.

Keyboard shortcuts are Windows only because this manager is currently Windows only:

```text
Ctrl + U           check Core/UI updates, then update CinePro when ready
Ctrl + Shift + U   check manager updates, then run manager update when ready
Ctrl + R           start CinePro
Ctrl + Shift + S   stop all services
Ctrl + L           toggle logs
Ctrl + B           open backend when running
Ctrl + F           open frontend when running
F1                 show shortcuts
```

## Env Handling

The manager reads `.env.example` from the installed Core folder and builds the env editor from it.

This means new env fields can appear in the manager without hardcoding every field in the UI.

Current required value:

```text
TMDB_API_KEY
```

Optional values are shown with descriptions from `.env.example` where possible.

Secret looking values such as keys and passwords are treated as hidden input fields.

## Health Checks

The manager already has a health client that checks:

```text
http://host:port/health
```

The existing backend was not changed. For proper manager health reporting, Core should eventually expose a stable health contract:

```json
{
  "status": "healthy",
  "version": {
    "tag": "main-98ba005",
    "commit": "98ba005"
  },
  "tmdb": true,
  "cache": {
    "type": "memory",
    "ok": true
  },
  "redis": {
    "enabled": false,
    "ok": false
  }
}
```

Provider health should be a separate endpoint because provider checks can be slower and more network dependent.

## How To Run The Manager In Development

From the repository root:

```powershell
cd setup-binary\manager
dart pub get
flutter analyze
flutter test
```

If the editor reports an error like:

```text
target of uri does not exist: package:path/path.dart
```

run:

```powershell
cd setup-binary\manager
dart pub get
```

Then reload the Dart analysis server or reopen the editor window. That error means dependency metadata has not been generated for the Flutter app yet.

The Windows runner should already exist in:

```text
setup-binary/manager/windows
```

If that folder is missing on a fresh checkout, generate it:

```powershell
flutter config --enable-windows-desktop
flutter create --platforms=windows --org cc.cinepro .
```

Then run the app:

```powershell
flutter run -d windows
```

That starts the manager in development mode. You can use it to check the UI, folder picker, logs, env editor, update check, and uninstall prompt.

The update check will not install real Core files until the GitHub release has signed manager ready assets. That is expected.

Build a release version:

```powershell
flutter build windows
```

Run only the manager widget smoke tests:

```powershell
flutter test test\manager_ui_smoke_test.dart
```

The build output should be:

```text
setup-binary/manager/build/windows/x64/runner/Release/
```

That folder is what Inno Setup packages.

## How To Test The Inno Installer

Install Inno Setup on Windows first.

Then build the Flutter manager release output:

```powershell
cd setup-binary\manager
flutter build windows
```

After the build succeeds, open this file in Inno Setup Compiler:

```text
setup-binary/installer/cinepro-manager.iss
```

Click `compile`.

Or compile from PowerShell if `ISCC.exe` is on PATH:

```powershell
cd setup-binary\installer
ISCC.exe cinepro-manager.iss
```

If you installed Inno Setup 7 in the default 32 bit location:

```powershell
cd setup-binary\installer
& "C:\Program Files (x86)\Inno Setup 7\ISCC.exe" cinepro-manager.iss
```

If it is installed in the 64 bit program files folder:

```powershell
cd setup-binary\installer
& "C:\Program Files\Inno Setup 7\ISCC.exe" cinepro-manager.iss
```

The generated setup exe requests admin rights when it starts. The Inno script controls that with:

```text
PrivilegesRequired=admin
```

The installer output will be generated by Inno Setup using:

```text
cinepro-manager-setup-0.1.0.exe
```

The version is part of the filename because the manager update checker parses versions from release assets.

The setup language prompt appears because the Inno script includes multiple real language files:

```text
English
French
German
Spanish
Tamil
```

These languages affect the installer wizard. The manager app language menu is separate and currently ships with English.

The Inno script also writes CinePro Foundation publisher, support, and update URLs into the setup metadata:

```text
publisher: https://github.com/cinepro-org
support: https://github.com/cinepro-org/core/issues
updates: https://github.com/cinepro-org/core/releases
```

For local dev testing, the normal loop is:

```powershell
cd setup-binary\manager
flutter analyze
flutter test
flutter build windows

cd ..\installer
ISCC.exe cinepro-manager.iss
```

Then install the generated setup exe, launch CinePro Manager from the Start Menu, and confirm:

- the app opens with the CinePro logo
- the window cannot be resized below the safe minimum
- the install folder picker opens
- update check reports unsigned releases as not manager ready
- logs update when actions run
- the uninstall prompt appears
- closing the app stops services started by the manager

During install, it should:

- show the setup language prompt
- request elevation through Windows UAC
- install the manager app
- create Start Menu shortcuts
- optionally create a Desktop shortcut
- offer to launch CinePro Manager and install verified CinePro files after setup

The user downloads and runs only the setup exe. The manager is bundled inside that installer. After Inno Setup finishes successfully, the installed manager can be launched from the final setup page, the Start Menu, or the optional Desktop shortcut. The user should not need to download the manager separately.

The setup itself does not directly trust or extract GitHub Core files. When the final setup page launches the manager, it passes:

```text
--setup-install
```

That tells the manager to start the verified install flow. The manager then checks GitHub releases, verifies the Ed25519 manifest signature, verifies SHA256 and byte count, downloads Core and the runtime, downloads the UI main archive, and extracts only after those checks pass.

If the latest GitHub release does not include manager ready assets yet, the manager shows a toast such as:

```text
Core Release Is Not Ready
This release has no signed Windows manager manifest yet.
```

That is expected until the release workflow publishes the signed manifest and signature files.

During uninstall, it should:

- ask before uninstalling CinePro Manager
- remind the user to use the in app uninstall prompt for managed Core files
- optionally remove manager logs, cache, and saved state

The Inno uninstaller is not supposed to blindly remove Core installs. Core removal belongs to the manager because the manager can check the managed install marker first.

If `flutter build windows` fails with a Visual Studio toolchain error, fix that before testing Inno. Inno packages the compiled Flutter output, so it cannot produce a useful installer without:

```text
setup-binary/manager/build/windows/x64/runner/Release/
```

## Testing Checklist

Use this checklist when testing a dev build:

- app opens without a backend repo change
- logo renders
- title bar shows the CinePro icon and `cinepro manager`
- manager app folder shows the setup installed location
- CinePro content folder shows the managed Core/UI location
- logs are hidden on first launch
- logs slide in after an action starts or after clicking `logs`
- three dot menu opens manager update, changelog, bug report, language, and shortcuts
- keyboard shortcuts dialog opens from `F1` and the three dot menu
- language dialog shows English and keeps the selected language
- closable notices appear when managed files are missing
- install folder can be changed
- update check refuses releases without a signed manager manifest
- update check shows the latest UI main commit when GitHub is reachable
- manager update check refuses setup assets without SHA256
- manager update ready state shows the red dot on the three dot menu
- Docker check handles missing cli, stopped daemon, and running daemon states
- Redis start, stop, and clear buttons report clear statuses
- Open menu can launch the backend and frontend urls when services are active
- frontend open url updates from the actual web service output after startup
- env panel is empty before install
- uninstall prompt opens
- uninstall stops services before cleanup
- clear logs works
- app close stops Core and frontend child processes
- external Core or frontend exit is logged and reflected in the badges
- `flutter analyze` passes
- `flutter test` passes
- Inno installer compiles after `flutter build windows`
- Inno output is named `cinepro-manager-setup-0.1.0.exe`

When signed release assets exist, also test:

- corrupted ZIP fails before extraction
- wrong SHA256 fails before extraction
- wrong manifest signature fails before download trust
- partial download is deleted
- ZIP path traversal is rejected
- interrupted install recovers on next launch
- interrupted update rolls back or completes safely
- missing `TMDB_API_KEY` blocks startup
- valid `TMDB_API_KEY` allows startup

## How To Contribute

Keep changes inside `setup-binary` unless the task is explicitly about adding a Core endpoint or release workflow support.

Good first contributions:

- improve the Windows UI polish
- add tests for safe ZIP extraction
- add tests for env parsing
- add tests for state recovery
- add a release workflow that publishes signed manager ready assets
- add a real Ed25519 signing script for the manifest
- add a Core `/health` endpoint in a separate backend pull request
- improve Inno Setup metadata and code signing

Code style:

- keep comments and doc comments lowercase
- keep comments short and useful
- avoid generated looking comments in app code
- do not add unrelated icons or decorative UI
- use the CinePro logo for identity
- keep the UI minimal and native feeling
- do not change backend Core behavior from this folder

Before opening a pull request:

```powershell
cd setup-binary\manager
dart format lib
flutter analyze
```

If the Windows runner exists:

```powershell
flutter build windows
```

For installer changes:

```powershell
cd setup-binary\installer
ISCC.exe cinepro-manager.iss
```

## Current Known Limitation

The manager code is valid and passes `flutter analyze` and `flutter test`, but real Core installs require the CinePro release workflow to publish signed manager ready assets.

Until that workflow exists, update checks should report that the release is not manager ready.

This is intentional. The manager should not silently fall back to unsigned source ZIP installs.

The UI can be checked from `cinepro-org/ui` main, but a signed UI manifest would still be better for production grade updates.

Regards,
Nischal
