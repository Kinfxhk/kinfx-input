# ASCII / Windows PowerShell 5.1. Does not launch apps or send input.
$ErrorActionPreference = 'Stop'
$harness = Join-Path $PSScriptRoot 'external-app-acceptance.ps1'
if (-not (Test-Path -LiteralPath $harness)) { throw 'Missing external-app acceptance harness' }
$dir = Join-Path $env:LOCALAPPDATA ('hermes\cache\scratch\external-selftest-' + [guid]::NewGuid().ToString('N'))
& $harness -ValidateOnly
& $harness -OutputDirectory $dir
$plan = Get-Content (Join-Path $dir 'plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$events = @(Get-Content (Join-Path $dir 'events.jsonl') -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
if ($plan.vectors.Count -ne 9) { throw 'Expected 9 cases: 6 Edge, 2 Notepad, 1 optional Terminal' }
$cases = @($events | Where-Object { $_.kind -eq 'case' })
if ($cases.Count -ne 9) { throw 'Missing NOT_RUN records' }
if (@($cases | Where-Object { $_.status -ne 'NOT_RUN' }).Count) { throw 'Plan falsely claims execution' }
if ($null -ne $cases[0].oldField -or $null -ne $cases[0].newField) { throw 'Unexecuted values must be null' }
if ($plan.metadata.activationFlags -ne '0x20000000 (TF_IPPMF_FORSESSION)') { throw 'Wrong TSF activation scope' }
if ($plan.metadata.clipboardFallback -ne 'disabled') { throw 'Clipboard must be opt-in' }
foreach ($path in @($harness,$PSCommandPath)) {
    if (@([IO.File]::ReadAllBytes($path) | Where-Object { $_ -gt 127 }).Count) { throw 'Source is not ASCII' }
}
$tokens=$null; $errors=$null
$null=[Management.Automation.Language.Parser]::ParseFile($harness,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
Write-Output ('SELFTEST PASS: helper compiled; PS5.1 parsed; 9 NOT_RUN cases; no app/input/activation. Results: '+$dir)
