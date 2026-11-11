# 0001 - Encrypt on the device, server sees ciphertext

Status: accepted (2026-11-11)

## Context

Messages and media pass through a self-hosted server that must not be able to
read them. There is no key escrow and no password reset that would recover
content.

## Decision

- Messages: AES-256-GCM content, AES key wrapped with the recipient's RSA-4096
  public key; the server only routes the envelope.
- Media: a random per-file AES-256-GCM key encrypts the uploaded bytes; the key
  travels inside the encrypted message. Downloads are decrypted on the device
  and stored encrypted at rest with the app master key.
- The app master key is derived from the local password with PBKDF2 and is kept
  in secure storage for biometric unlock.

## Consequences

- A lost private key means the history is unreadable.
- The server cannot scan or transcode attachments.
- RSA-4096, AES-256-GCM and PBKDF2 parameters are a hard floor.
