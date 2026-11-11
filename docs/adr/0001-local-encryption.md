# 0001 - Encrypt on the device, server sees ciphertext

Status: accepted (2026-11-11)

## Context
Messages and media pass through a self-hosted server that must not read them.
There is no key escrow and no password reset that could recover content.

## Decision
Messages use AES-256-GCM content with the AES key wrapped by the recipient's
RSA-4096 public key. Media uses a random per-file AES-256-GCM key that travels
inside the encrypted message; the download is decrypted on the device and
stored encrypted at rest with the PBKDF2-derived app key. Biometrics only
unlock that key from secure storage.

## Consequences
A lost private key means unreadable history; the server cannot scan or
transcode attachments; RSA-4096, AES-256-GCM and PBKDF2 are a hard floor.
