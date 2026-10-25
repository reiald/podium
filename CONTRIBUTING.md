# Contributing to Podium

Thanks for helping. Bug reports, fixes and small features are all welcome.

## Report a bug

Open an issue with:

- your macOS version and Mac model (displays and Spaces matter),
- the steps that trigger it, and what you expected,
- the log from just after it happened (the system log rotates within hours):

```bash
/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "dev.podium.Podium"'
```

If a window ever goes missing, choose **Restore All Windows** from the Podium menu first, then tell us what happened.

## Set up

```bash
scripts/make-dev-cert.sh   # once, so macOS keeps Podium's permissions across rebuilds
scripts/test.sh            # all tests
scripts/run.sh             # build, sign and launch
```

Use `scripts/test.sh` and not plain `swift test`. It retries a known "TestingMacros plugin not found" failure of the Swift toolchain.

## How the code is split

- `Sources/PodiumCore` is pure logic: the stage model, strip layout, motion and the parking safety code. It must not import AppKit, and every behaviour in it has a test.
- `Sources/Podium` is the app: windows, event taps, overlays and settings.

Put new decisions in `PodiumCore` where they can be tested, and keep the app layer thin.

## Rules

- **Tests first for logic.** Write a failing test in `Tests/PodiumCoreTests`, then the fix.
- **Never lose a window.** Anything that moves a window off screen must go through the parking ledger so it can be restored.
- **Do not write Apple's Stage Manager preferences** (`com.apple.WindowManager`). Podium only reads them.
- **Log with `podiumLog(...)`** or a `Logger` with subsystem `dev.podium.Podium` and `privacy: .public`. Never `NSLog`, because its output does not reach the unified log. A test enforces this.
- **Read the log as the process, not the shell.** In zsh, `log` is a builtin, so call `/usr/bin/log`.

## Pull requests

Keep each pull request to one change, include the tests, and describe what you saw on screen. Mention your macOS version if the change depends on it.

By contributing you agree that your work is released under the [MIT license](LICENSE).
