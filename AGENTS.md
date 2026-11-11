# whisper — agent contract

Flutter 3.47 / Dart 3.13 client for Whisper. Talks to `whisper-server` over HTTP (generated `whisper_openapi_client_dart`)
and WebSocket (`whisper_websocket_client_dart`).

## Commands

- deps: `flutter pub get`
- analyze: `flutter analyze --no-fatal-infos` (errors and warnings block, infos do not)
- format: `dart format` on the files you touched
- test: `flutter test`
- build: `flutter build apk --release` (requires `firebase_options.dart`, `google-services.json`, `firebase.json`)

## Hard rules

1. Never commit secrets, keys, `.env*`, `firebase_options.dart`, `google-services.json` or `firebase.json`.
2. Do not edit `whisper_openapi_client_dart/lib` or `whisper_websocket_client_dart/lib` by hand. Contract changes go through `whisper-server` and regeneration (skill `contract-change`).
3. `lib/media_download.dart` is a hand-written extension of the generated client — when the download changes, edit this file, not the generated `downloadMedia`.
4. Crypto: never lower RSA 4096, AES-256-GCM or PBKDF2 parameters. No key may leave the device in plaintext and no seed may be constant.
5. Do not weaken the app lock (password, biometrics), not even "temporarily for debugging".
6. Never disable a test, lint or the analyzer to get CI green. Fix it, or file an issue and escalate.
7. Force-push only to your own feature branch, never to `main`.

## Where it hurts

- **Media upload**: `uploadMedia(file, receiverId)` — the argument order comes from the generator, not from logic. Verify call sites after regenerating the client.
- **Path dependencies**: `pubspec.yaml` pulls both clients via `path:`, so CI cannot see which client version the app actually uses. Pinning to a tag is phase 2 debt.
- **Firebase**: analysis fails without `lib/firebase_options.dart`. CI decodes it from a secret.

## Definition of done

- New non-trivial logic has a test (`test/`).
- `flutter analyze --no-fatal-infos` reports no errors and no warnings.
- Formatting is clean on the files you touched.
- A contract change ships the regenerated client and the updated call sites in one PR.

## When unsure

Stop and ask. Security decisions (keys, encryption, auth) are not up for guessing.
