# ADR-005: Open Source Strategy

**Status:** Accepted
**Date:** 2026-04-24
**Supersedes:** Roadmap recommendation (which suggested open core)

## Context

Pildora's primary selling point is trust: "your health data is yours — we can't
see it even if we wanted to." The licensing model must reinforce this trust
while being sustainable for a solo developer.

The roadmap initially recommended **open core** (crypto library MIT, apps
closed). This was revised after considering the project's goals.

## Decision

**Fully open source under AGPL-3.0.** All components — crypto library, apps,
server, data pipeline — are licensed under the GNU Affero General Public
License v3.0.

## Rationale

### Trust is the competitive advantage

No competitor in the medication tracking space offers full source visibility.
Users must take Medisafe, MyTherapy, and others at their word when they claim
to protect data. With Pildora, anyone can verify every line of code that
handles their health data. Partial openness (open core) would undermine this
message — "trust us on the parts you can't see" is weaker than "verify
everything."

### Career showcase over profit

This project's primary purpose is to demonstrate software engineering skill.
A fully open-source, well-architected multi-platform health app with E2E
encryption is a stronger portfolio piece than closed-source work nobody can
inspect. Employers and clients can evaluate the code directly.

### AGPL protects against closed forks

AGPL requires that anyone running a modified version as a network service must
release their modifications under the same license. This prevents a competitor
from forking Pildora, closing the source, and offering a competing service.
MIT or Apache would allow this.

### Precedent: Bitwarden

Bitwarden is fully open source (AGPL for the server, GPL for clients) and
generates significant revenue from managed hosting. The model works: free to
self-host, pay for convenience. Pildora can follow the same path if revenue
becomes important.

## Alternatives Considered

**Open core (crypto MIT, apps closed):** The roadmap's original recommendation.
Builds trust on the crypto layer but keeps the app UI as proprietary IP.
Rejected because the user's primary goal is trust, not IP protection, and
partial openness weakens the trust narrative.

**Source-available (BSL):** Code is visible but not freely modifiable for
commercial use. Rejected because it discourages community contributions and
doesn't qualify as true open source — which matters for the trust message.

**Closed source:** Maximum IP protection. Rejected because it directly
contradicts the zero-knowledge trust positioning. "Trust us but you can't see
the code" is a weak message for a privacy-first product.

## Consequences

- Anyone can fork and self-host Pildora. This is a feature, not a risk — it
  reinforces the data ownership promise.
- Revenue from the project (if any) must come from managed hosting, support,
  or premium features — not from restricting access to the code.
- All contributions must be AGPL-3.0 compatible.
- Third-party dependencies must be evaluated for AGPL compatibility.
- The AGPL network-use clause means any organization running a modified Pildora
  sync server must release their modifications. This is intentional.
