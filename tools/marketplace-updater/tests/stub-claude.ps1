# Stand-in for the claude CLI: logs "<cwd>|<args>" and answers `plugin list --json` from a file.
# `marketplace update bad` fails, so tests can check a failed refresh skips that marketplace.
# C4_STUB_LIST_FAIL=1 makes `plugin list` fail.
$line = $args -join ' '
Add-Content $env:C4_STUB_LOG "$((Get-Location).Path)|$line"
if ($line -eq 'plugin list --json') {
    if ($env:C4_STUB_LIST_FAIL) { exit 1 }
    Get-Content -Raw $env:C4_STUB_LIST
}
if ($line -eq 'plugin marketplace update bad') { exit 1 }
exit 0
