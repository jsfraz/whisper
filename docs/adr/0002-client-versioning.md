# 0002 - Pin clients to tags once releases exist

Status: accepted (2026-11-11); supersedes the `path:` setup once a server tag exists

## Context

`pubspec.yaml` pulls `whisper_openapi_client_dart` and
`whisper_websocket_client_dart` through `path: ../...`. CI has to check out the
sibling repositories, and nothing records which client version the app used.

## Decision

Keep `path:` while the clients have no release tags; both repositories are
checked out next to the app locally and in CI. As soon as the server publishes
its first `v*` tag, the clients get matching tags and the app pins those tags
instead of `path:`. The generated client is still regenerated in one sequence
with the server spec.

## Consequences

- Today CI depends on sibling checkouts and the branch name.
- The Flutter E2E workflow already checks the clients out explicitly; that
  mirrors what a tag pin will replace.
- A spec change still ships the regenerated client and updated call sites in
  one change.
