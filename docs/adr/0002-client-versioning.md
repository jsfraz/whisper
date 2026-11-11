# 0002 - Pin clients to tags once releases exist

Status: accepted (2026-11-11); supersedes the `path:` setup once a server tag exists

## Context
`pubspec.yaml` pulls both Dart clients through `path: ../...`. CI must check out
sibling repositories and nothing records which client version the app used.

## Decision
Keep `path:` while the clients have no release tags; local and CI checkouts put
them next to the app. After the first server `v*` tag, tag the clients and pin
the app to those tags. Generated code is still regenerated in one sequence with
the server spec.

## Consequences
CI depends on sibling checkouts and the branch name today; the Flutter E2E
workflow already mirrors what a tag pin will replace.
