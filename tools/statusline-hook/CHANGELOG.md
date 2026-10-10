# Changelog

All notable changes to `statusline-hook` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Releases are tagged `slh-vX.Y.Z`.

## [Unreleased]

### Added

- `statusline-hook-setup.sh`: a bash setup script (needs `jq`) that installs or uninstalls either
  variant, the twin of `statusline-hook-setup.ps1`.

## [0.1.0] - 2026-10-10

First public release: a rebuild of the hook from the ground up.

### Added

- Three-row layout: model, context gauge, runtime and cost on row 1, then aligned 5-hour and
  7-day rate-limit gauges with local reset times. A row is shown only when Claude Code sends
  that window.
- Reasoning effort (`effort.level`) next to the model name, when the model supports effort.
- Time left until each rate-limit reset, in brackets after the reset time.
- A `◷` marker before the session runtime.
- `C4_STATUSLINE_NOW`: a test-only clock override (epoch seconds) used by the golden harness.
- One colour scale for every gauge: green below 50%, yellow below 80%, red from 80%.
- Golden fixtures (`fixtures/`) and `tests/golden.sh`, which hold both ports to identical output.
- Windows PowerShell 5.1 support alongside PowerShell 7.

### Changed

- The bash port renders everything in one `jq` call and no longer depends on GNU or BSD `date`.
- Bad input of any kind prints nothing and exits 0.
- The setup script removes scripts left by earlier installs.

### Removed

- The Python port (`statusline-hook.py`) and the `py` setup variant.
- The JSONL export and `C4_STATUSLINE_EXPORT`. The statusline only prints the statusline.
- The 1M-context ×5 scaling of the context percentage, which Claude Code now sends
  pre-calculated.
