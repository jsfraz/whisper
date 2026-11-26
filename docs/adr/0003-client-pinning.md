# 0003 - Clients are pinned by release tag

Status: accepted (2026-11-17)

## Context
`pubspec.yaml` pulled both Dart clients through `path: ../...`. Nothing recorded
which client the app was built against, CI had to check out two sibling
repositories, and a local change to a client silently changed the app.

## Decision
Both clients are tagged `v0.1.0` (pre-1.0: the products tag `v1.0.0` only after
F1-F10) and the app depends on them as git dependencies at that tag. Local work
on a client and the app together uses `pubspec_overrides.yaml`, which is
gitignored, so CI and release builds always resolve the tags.

The OpenAPI client carries `lib/version.dart` with `clientVersion`, the WS client
`lib/version.dart`, and the app `lib/utils/version.dart` with `appVersion`, which
it sends as `X-Client-Version`. The server refuses a login below its
`minClientVersion` (`GET /api/version`).

## Consequences
A contract change needs a new tag on the client before the app can use it, and
the app version bump lands in the same series. CI no longer checks out siblings.
