# Security Policy

Lattice is **unaudited, pre-1.0 software.** It re-implements and adapts
established contracts (OpenZeppelin, Solady, Uniswap V2, Yearn V3) into the
EIP-2535 Diamond facet pattern, but it has **not** received an independent
security audit. Do not deploy it to mainnet with funds at risk without your own
review.

## Supported versions

Lattice is pre-1.0. Only the latest tagged release is supported: fixes land on
the development branch (`dev`) and ship in the next release. Older 0.x releases
receive no backports. See
[Versioning and compatibility](README.md#versioning-and-compatibility) for what
a minor or patch release may change.

## Reporting a vulnerability

**Please do not open public issues, pull requests, or discussions for security
vulnerabilities.**

Report privately through GitHub's private vulnerability reporting:
**Security → Report a vulnerability** on
<https://github.com/dadadave80/lattice>. This opens an advisory visible only to
the maintainer.

If private reporting is unavailable, contact the maintainer (daveproxy80.eth) to
arrange a disclosure channel before posting any details publicly.

As a solo-maintained project, responses are best-effort. Please allow reasonable
time for a fix before public disclosure (90 days is a good default). Reporters
who follow coordinated disclosure will be credited unless they prefer to remain
anonymous.
