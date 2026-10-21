# Podium

An open-source macOS Stage Manager replacement. A menu bar app (`Podium`) on top of a pure Swift library (`PodiumCore`).

## Build and run

1. One-time: `scripts/make-dev-cert.sh` creates a self-signed `Podium Dev` code-signing identity. A stable signature keeps the Accessibility permission valid across rebuilds.
2. `scripts/run.sh` builds `build/Podium.app`, signs it, and relaunches it.
3. `swift test` runs the `PodiumCore` tests.

Set `PODIUM_SIGN_IDENTITY` to override the signing identity (`-` for ad-hoc).
