# ASCII / Windows PowerShell 5.1. No desktop input is sent by this test.
$ErrorActionPreference = 'Stop'
$harness = Join-Path $PSScriptRoot 'interaction-acceptance.ps1'
if (-not (Test-Path $harness)) { throw 'Missing enhanced acceptance harness' }
$scratch = Join-Path $env:LOCALAPPDATA 'hermes\cache\scratch'
$dir = Join-Path $scratch ('interaction-selftest-' + [guid]::NewGuid().ToString('N'))
& $harness -ValidateOnly
$probe = New-Object InteractionBox
try {
    $probe.Text='raw fixture'
    $probe.Select(2,3)
    $null=$probe.Handle
    $preedit=[InteractionNative]::Preedit($probe)
    if ($null -eq $preedit.value -and -not $preedit.unavailable) { throw 'Unavailable preedit requires a reason' }
    if ($probe.SelectionStart -ne 2 -or $probe.SelectionLength -ne 3) { throw 'Native selection probe failed' }
    $window=[InteractionNative]::Window($probe.Handle)
    if ($window.pid -ne $PID -or $null -eq $window.rect) { throw 'Window probe failed' }
    $null=[InteractionNative]::Candidates([uint32]$PID)
    $null=[InteractionNative]::Caret()
} finally { $probe.Dispose() }
& $harness -OutputDirectory $dir
$plan = Get-Content (Join-Path $dir 'plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($plan.vectors.Count -ne 17) { throw 'Expected exactly 17 vectors' }
$records = @(Get-Content (Join-Path $dir 'events.jsonl') -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
$cases = @($records | Where-Object { $_.kind -eq 'case' })
if ($cases.Count -ne 17) { throw 'Expected 17 NOT_RUN records' }
if (@($cases | Where-Object { $_.status -ne 'NOT_RUN' }).Count) { throw 'Plan must never claim execution' }
if ($plan.vectors[16].repetitions -ne 180) { throw 'Missing 180 focus repetitions' }
foreach ($name in @('oldField','newField','preedit','selection','candidateWindows','caretRect','appForeground')) {
    if ($cases[0].PSObject.Properties.Name -notcontains $name) { throw ('Missing raw field: ' + $name) }
}
if ($null -ne $cases[0].oldField) { throw 'Unexecuted text must be null, not fabricated empty text' }
foreach ($path in @($harness, (Join-Path $PSScriptRoot 'interaction-native.cs'))) {
    if (@([IO.File]::ReadAllBytes($path) | Where-Object { $_ -gt 127 }).Count) { throw ('Non-ASCII source: ' + $path) }
}
Write-Output ('SELFTEST PASS: helper compiled; 17 NOT_RUN vectors; UTF8 JSONL parsed. Results: ' + $dir)
