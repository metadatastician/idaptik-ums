# Security Policy

Report vulnerabilities to j.d.a.jewell@open.ac.uk.
Subject: `[security] <repo>: <summary>`.

Acknowledgement within 72 hours, initial assessment within 7 days.

## Hardening posture

- Chainguard distroless container bases (@sha256: pinned).
- ML-DSA-87 release signing via cerro-torre.
- SPDX SBOM emitted with every container build.
- Read-only root, nonroot user, dropped ALL capabilities.
