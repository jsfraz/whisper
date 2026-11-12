# whisper — agent contract

Flutter 3.47 / Dart 3.13 client for Whisper. Talks to `whisper-server` over HTTP (generated `whisper_openapi_client_dart`)
and WebSocket (`whisper_websocket_client_dart`).

## Commands

- deps: `flutter pub get`
- analyze: `flutter analyze --no-fatal-infos` (errors and warnings block, infos do not)
- format: `dart format` on the files you touched
- test: `flutter test`
- e2e: `flutter test integration_test -d linux` (needs Linux desktop toolchain)
- build: `flutter build apk --release` (requires `firebase_options.dart`, `google-services.json`, `firebase.json`)

## AI / MCP tooling

OpenCode has two Flutter MCP servers wired globally (config in `~/.config/opencode/opencode.json`,
not in this repository). Use them for the fast loop, but the shell gates below still define done.

| Server | Role |
|---|---|
| `dart` | `analyze_files`, symbol resolution, `run_tests`, `pub`, hot reload/restart, DTD connection, widget inspector |
| `flutter-mcp-toolkit` | screenshots, semantic snapshot, tap/type, recent logs — UI verification of a running debug build |

1. At session start register roots: `whisper`, `../whisper_openapi_client_dart`, `../whisper_websocket_client_dart`.
2. MCP-driven runs use a fixed port so the toolkit can attach: `flutter run -d linux --device-vmservice-port=8181`. One running instance only.
3. UI work: `fmt_semantic_snapshot` → `ref` → `fmt_tap_widget`/`fmt_enter_text`, then hot reload after every widget change. Pixel capture is unsupported on Linux desktop (needs the app permission bridge), so use `fmt_hot_reload_flutter`, not `fmt_hot_reload_and_capture`.
4. Never call `fmt_evaluate_dart_expression`; it is denied in the OpenCode `permissions` config and there is no server-side flag for it.
5. Toolkit and debug builds only with test data — never with a real account.
6. `pub add`/`pub remove` and any `pubspec.yaml` change need explicit confirmation. `dart_fix` is disabled on purpose: it would rewrite the generated clients.
7. `flutter analyze --no-fatal-infos` from the shell remains the definition-of-done gate; MCP analysis does not replace it.

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
