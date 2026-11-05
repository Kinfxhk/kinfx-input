#Requires -Version 5.1
<#
Test-only native two-textbox GUI acceptance recorder. Windows x64 / PowerShell 5.1 STA.
Copy BOTH interaction-acceptance.ps1 and interaction-native.cs to the test machine.
Default invocation writes a NOT_RUN plan only. No VM automation, installation,
registry, engine, settings, or tracing changes. Explicit GUI execution:
  powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File .\interaction-acceptance.ps1 -Run -OutputDirectory C:\QA\interaction
  Add -SourceSha <40-or-64-hex> when copying outside the source checkout.
-ValidateOnly compiles helper and checks vectors without opening UI or sending keys.
Raw native EDIT text can include inline composition: do not equate Text with commit.
OBSERVED is NOT PASS. Semantic acceptance requires inspection of raw checkpoints;
missing TSF/IMM preedit, missing candidate evidence, or missing prerequisites must
not be interpreted as success. S/F/L are instrumented commands in this test host,
not evidence of passthrough in an unrelated browser or editor.
#>
[CmdletBinding()]
param(
    [switch]$Run,
    [switch]$ValidateOnly,
    [string]$OutputDirectory,
    [string]$DllPath = 'C:\Program Files\KINFX Input\KINFXInput.dll',
    [string]$SourceSha,
    [int]$KeyDelayMs = 35
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Windows only' }
if (-not [Environment]::Is64BitProcess) { throw 'Use x64 PowerShell (SendInput layout is x64)' }
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Launch powershell.exe -STA' }
if ($KeyDelayMs -lt 0) { throw 'KeyDelayMs cannot be negative' }
if ($SourceSha -and $SourceSha -notmatch '^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$') { throw 'SourceSha must be a literal full Git SHA' }
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$helper = Join-Path $PSScriptRoot 'interaction-native.cs'
if (-not (Test-Path -LiteralPath $helper)) { throw 'Copy interaction-native.cs alongside this script' }
if (-not ('InteractionNative' -as [type])) {
    Add-Type -Path $helper -ReferencedAssemblies System.Windows.Forms,System.Drawing
}
$vectors = @(
    @{id='01-idle-target'; prefix=''; action='switch'; keys='vd1'},
    @{id='02-pending-vd'; prefix='vd'; action='switch'; keys='vd1'},
    @{id='03-pending-hel'; prefix='hel'; action='switch'; keys='vd1'},
    @{id='04-committed-vd1'; prefix='vd1'; action='switch'; keys='vd1'},
    @{id='05-vd1hel'; prefix='vd1hel'; action='switch'; keys='vd1'},
    @{id='06-escape'; action='escape'; keys='vd'},
    @{id='07-enter-commit-newline'; action='enter'; keys='vd'},
    @{id='08-tab-shifttab'; action='tab'; keys='vd'},
    @{id='09-app-shortcuts'; action='shortcuts'; chords=@('A','C','X','V','Z','S','F','L')},
    @{id='10-vd1-paste-shift1'; action='paste'; keys='vd1'; shift1=$true},
    @{id='11-vdhel-paste'; action='paste'; keys='vdhel'; shift1=$false},
    @{id='12-decimal-space'; action='text'; keys='123.45 '},
    @{id='13-symbol-space'; action='text'; keys='BTCUSDT '},
    @{id='14-shifta-pi-space'; action='shiftA'; keys='vd'},
    @{id='15-candidate-borders'; action='borders'; keys='vd'},
    @{id='16-switch-minimize-hide'; action='hide'; keys='vd1'},
    @{id='17-repeated-focus'; action='repeat'; repetitions=180; prefixes=@('','vd','hel','vd1','vd1hel')}
)
if ($vectors.Count -ne 17) { throw 'Vector definition incomplete' }
if ($ValidateOnly) { Write-Output 'VALIDATED: 17 vectors; x64 helper compiled; no desktop operations'; return }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot ('results\interaction-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)) }
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$utf8 = New-Object Text.UTF8Encoding($false)
$eventsPath = Join-Path $OutputDirectory 'events.jsonl'
if (Test-Path -LiteralPath $eventsPath) { throw 'Use a new results directory; will not overwrite previous events' }
$writer = New-Object IO.StreamWriter($eventsPath,$false,$utf8)
$writer.AutoFlush = $true
$script:sequence = 0
$script:finished = @{}
$script:current = $null
$script:commands = @()
$script:activation = $null
function Emit($record) {
    $script:sequence++
    $record.sequence = $script:sequence
    $record.utc = [DateTime]::UtcNow.ToString('o')
    $writer.WriteLine(($record | ConvertTo-Json -Depth 18 -Compress))
}
function NotRun($id,$reason) {
    Emit @{kind='case';id=$id;status='NOT_RUN';reason=$reason;oldField=$null;newField=$null;preedit=$null;preeditUnavailable=$reason;selection=$null;candidateWindows=$null;caretRect=$null;appForeground=$null}
}
function HashOrNull($path) { if (Test-Path -LiteralPath $path -PathType Leaf) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }; return $null }
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$sourceOrigin = 'parameter'
$dirty = $null
if (-not $SourceSha) {
    $sourceOrigin = 'unavailable'
    if (Get-Command git -ErrorAction SilentlyContinue) {
        try {
            $sha = & git -C $repo rev-parse HEAD 2>$null
            if ($LASTEXITCODE -eq 0 -and $sha -match '^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$') { $SourceSha=$sha; $sourceOrigin='checkout HEAD (not proof of installed DLL provenance)' }
        } catch { $sourceOrigin='unavailable: git execution blocked or checkout inaccessible; provide -SourceSha' }
    }
}
if (Get-Command git -ErrorAction SilentlyContinue) {
    try {
        $state = & git -C $repo status --porcelain 2>$null
        if ($LASTEXITCODE -eq 0) { $dirty = @($state) }
    } catch { $dirty = $null }
}
$dllVersion = $null
if (Test-Path -LiteralPath $DllPath -PathType Leaf) { $dllVersion = (Get-Item -LiteralPath $DllPath).VersionInfo.FileVersion }
$meta = @{kind='metadata';schemaVersion=1;sourceSha=$SourceSha;sourceShaOrigin=$sourceOrigin;sourceDirty=$dirty;dllPath=$DllPath;dllSha256=(HashOrNull $DllPath);dllVersion=$dllVersion;scriptSha256=(HashOrNull $PSCommandPath);helperSha256=(HashOrNull $helper);processId=$PID;os=[Environment]::OSVersion.VersionString;psVersion=$PSVersionTable.PSVersion.ToString();mode='plan';semanticPolicy='OBSERVED is not PASS; no inferred commit or hidden candidate PASS';preeditPolicy='IMM32 and WM_IME_COMPOSITION only; TSF-only unobservable values are null with reason'}
if ($Run) { $meta.mode='GUI' }
$plan = @{metadata=$meta;vectors=$vectors}
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'plan.json'),($plan | ConvertTo-Json -Depth 12),$utf8)
Emit $meta
foreach ($v in $vectors) { NotRun $v.id 'Not started; latest case event supersedes this initial NOT_RUN record' }
function Pump([int]$ms=80) {
    $sw=[Diagnostics.Stopwatch]::StartNew()
    do { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 2 } while ($sw.ElapsedMilliseconds -lt $ms)
}
function OwnForeground {
    $fg=[InteractionNative]::GetForegroundWindow()
    return ($fg -eq $form.Handle -or $fg -eq $other.Handle)
}
function Key([int]$vk,[bool]$shift=$false,[bool]$ctrl=$false) {
    if (-not (OwnForeground)) { throw 'Foreground left test-owned windows; input aborted' }
    [InteractionNative]::Key([uint16]$vk,$shift,$ctrl)
    Pump $KeyDelayMs
}
function TypeCode([string]$s) {
    foreach ($ch in $s.ToCharArray()) {
        if ($ch -eq '.') { Key 190 }
        elseif ($ch -eq ' ') { Key 32 }
        elseif ($ch -cmatch '[a-zA-Z0-9]') { Key ([int][char]::ToUpperInvariant($ch)) ([char]::IsUpper($ch)) }
        else { throw ('Unsupported literal VK mapping: ' + $ch) }
    }
}
function ClickBox($box) {
    $hostForm=$box.FindForm()
    [void][InteractionNative]::SetForegroundWindow($hostForm.Handle)
    $pt=$box.PointToScreen((New-Object Drawing.Point(18,18)))
    [InteractionNative]::Click($pt.X,$pt.Y)
    Pump 100
    if ([InteractionNative]::GetForegroundWindow() -ne $hostForm.Handle -or -not $box.Focused) { throw 'Cannot establish requested textbox foreground/focus' }
}
function Snapshot([string]$step) {
    $caret=[InteractionNative]::Caret()
    $raw=@{kind='snapshot';id=$script:current;step=$step;status='OBSERVED';oldField=$old.Text;newField=$new.Text;preedit=@{old=[InteractionNative]::Preedit($old);new=[InteractionNative]::Preedit($new)};selection=@{old=@{start=$old.SelectionStart;length=$old.SelectionLength;end=($old.SelectionStart+$old.SelectionLength)};new=@{start=$new.SelectionStart;length=$new.SelectionLength;end=($new.SelectionStart+$new.SelectionLength)}};candidateWindows=@([InteractionNative]::Candidates([uint32]$PID));candidateScope='All top-level KINFXInputCand windows owned by harness PID only';caretRect=$caret;caretUnavailable=$null;appForeground=[InteractionNative]::Window([InteractionNative]::GetForegroundWindow());focusedField='none';hostCommands=@($old.Commands.ToArray())+@($new.Commands.ToArray());activationHr=$script:activation}
    if ($null -eq $caret) { $raw.caretUnavailable='GetGUIThreadInfo has no caret or ClientToScreen failed' }
    if ($old.Focused) { $raw.focusedField='old' }; if ($new.Focused) { $raw.focusedField='new' }
    Emit $raw
    return $raw
}
function Mark([string]$step) { $null=Snapshot $step }
function ResetFields {
    $form.WindowState='Normal'; $form.Show(); ClickBox $old; Key 27
    ClickBox $new; Key 27
    $old.Clear();$new.Clear();$old.Commands.Clear();$new.Commands.Clear()
    $old.ObservedPreedit=$null;$new.ObservedPreedit=$null;$old.CompositionObserved=$false;$new.CompositionObserved=$false
    ClickBox $old
    Mark 'reset'
}
function SwitchVector([string]$prefix) {
    if ($prefix) { TypeCode $prefix }
    Mark 'before-switch'
    ClickBox $new; Mark 'after-switch-before-target'
    TypeCode 'vd1'; Mark 'after-target-vd1'
}
$form=$null;$other=$null;$clipboard=$null;$clipboardSaved=$false
try {
    if (-not $Run) { Emit @{kind='end';status='NOT_RUN';reason='GUI requires explicit -Run';vectors=17}; return }
    if (-not [Environment]::UserInteractive) { throw 'No interactive desktop; cannot establish GUI prerequisites' }
    if (-not $meta.dllSha256) { throw 'Installed DLL unavailable; cannot establish IME under test' }
    [void][InteractionNative]::SetProcessDPIAware()
    $clipboard=[Windows.Forms.Clipboard]::GetDataObject();$clipboardSaved=$true
    $form=New-Object Windows.Forms.Form
    $form.Text='KINFX interaction acceptance - native EDIT';$form.StartPosition='Manual';$form.SetBounds(40,40,640,410)
    $old=New-Object InteractionBox;$old.Multiline=$true;$old.AcceptsReturn=$true;$old.AcceptsTab=$false;$old.TabIndex=0;$old.SetBounds(15,20,590,135)
    $new=New-Object InteractionBox;$new.Multiline=$true;$new.AcceptsReturn=$true;$new.AcceptsTab=$false;$new.TabIndex=1;$new.SetBounds(15,195,590,135)
    $form.Controls.AddRange(@($old,$new))
    $other=New-Object Windows.Forms.Form;$other.Text='KINFX acceptance focus sink (same process)';$other.StartPosition='Manual';$other.SetBounds(710,40,300,180)
    $sink=New-Object Windows.Forms.Button;$sink.Text='Focus sink';$sink.Dock='Fill';$other.Controls.Add($sink)
    $other.Show();$form.Show();Pump 300;ClickBox $old
    $script:activation=[InteractionNative]::Activate();Pump 350
    $script:current='baseline';TypeCode 'vd1';$base=Snapshot 'baseline-vd1'
    if ($script:activation -lt 0 -or $old.Text -cne ([string][char]0x597D) -or $new.Text -ne '') { throw 'Baseline vd1 -> U+597D not established; refusing false GUI acceptance' }
    Key 27
    foreach ($v in $vectors) {
        $script:current=$v.id
        try {
            ResetFields
            switch ($v.action) {
                'switch' { SwitchVector $v.prefix }
                'escape' { TypeCode $v.keys;Mark 'before-Esc';Key 27;Mark 'after-Esc';TypeCode 'vd1';Mark 'after-recovery-vd1' }
                'enter' { TypeCode $v.keys;Mark 'before-first-Enter';Key 13;Mark 'after-first-Enter-commit';Key 13;Mark 'after-second-Enter-newline' }
                'tab' { TypeCode 'vd';Mark 'before-Tab';Key 9;Mark 'after-Tab';TypeCode 'vd1';Mark 'target-input';Key 9 $true;Mark 'after-ShiftTab';TypeCode 'vd1';Mark 'source-input' }
                'shortcuts' {
                    foreach ($prefix in @('','vd')) {
                        foreach ($chord in $v.chords) {
                            ResetFields
                            # Seed committed fixture directly; keys under test still use real VK input.
                            $old.Text='QA_SHORTCUT';$old.Select($old.TextLength,0)
                            [Windows.Forms.Clipboard]::SetText('QA_PASTE')
                            if ($prefix) { TypeCode $prefix }
                            if ($chord -in @('C','X')) { $old.SelectAll() }
                            Mark ('before-Ctrl-'+$chord+'-prefix-'+$prefix)
                            Key ([int][char]$chord) $false $true
                            $clipText=[Windows.Forms.Clipboard]::GetText()
                            Emit @{kind='clipboard';id=$v.id;chord=$chord;prefix=$prefix;value=$clipText;host='native EDIT with S/F/L instrumented commands'}
                            Mark ('after-Ctrl-'+$chord+'-prefix-'+$prefix)
                        }
                    }
                }
                'paste' { [Windows.Forms.Clipboard]::SetText('QA_PASTE');TypeCode $v.keys;Mark 'before-paste';Key 86 $false $true;Mark 'after-paste';if ($v.shift1) { Key 49 $true;Mark 'after-Shift1' };Key 27;Mark 'after-Esc' }
                'text' { TypeCode $v.keys;Mark 'after-text-space';Key 27;Mark 'after-Esc' }
                'shiftA' { TypeCode 'vd';Mark 'after-vd';Key 65 $true;Mark 'after-ShiftA';TypeCode 'pi ';Mark 'after-pi-space' }
                'borders' {
                    $original=$form.Bounds
                    foreach ($edge in @('right','bottom','bottom-right')) {
                        ResetFields
                        $wa=[Windows.Forms.Screen]::FromControl($old).WorkingArea
                        $x=$wa.Left;$y=$wa.Top
                        if ($edge -in @('right','bottom-right')) { $x=$wa.Right-$form.Width }
                        if ($edge -in @('bottom','bottom-right')) { $y=$wa.Bottom-$form.Height }
                        $form.Location=New-Object Drawing.Point($x,$y);ClickBox $new
                        $new.Text=('W'*68+"`r`n")*5;$new.Select($new.TextLength,0)
                        TypeCode 'vd';Mark ('candidate-'+$edge+'-preedit');TypeCode '1';Mark ('candidate-'+$edge+'-association')
                        Emit @{kind='geometry';id=$v.id;edge=$edge;workArea=@{left=$wa.Left;top=$wa.Top;right=$wa.Right;bottom=$wa.Bottom};status='OBSERVED';reason='Inspect actual candidate rectangles against workArea; absent window is not a border PASS'}
                    }
                    $form.Bounds=$original
                }
                'hide' {
                    foreach ($mode in @('switch','minimize','hide')) {
                        ResetFields;TypeCode 'vd1';$before=Snapshot ('before-'+$mode)
                        $visibleBefore=@($before.candidateWindows | Where-Object { $_.visible }).Count
                        if ($mode -eq 'switch') { [void][InteractionNative]::SetForegroundWindow($other.Handle);$pt=$sink.PointToScreen((New-Object Drawing.Point(30,30)));[InteractionNative]::Click($pt.X,$pt.Y) }
                        elseif ($mode -eq 'minimize') { $form.WindowState='Minimized' }
                        else { $form.Hide() }
                        Pump 350;Mark ('after-'+$mode)
                        if (-not $visibleBefore) { Emit @{kind='subcase';id=$v.id;mode=$mode;status='NOT_RUN';reason='No visible association candidate before transition; hide predicate cannot be established'} }
                        $form.Show();$form.WindowState='Normal';ClickBox $old;Key 27
                    }
                }
                'repeat' {
                    for ($i=0;$i -lt 180;$i++) {
                        ResetFields;$prefix=$v.prefixes[$i % $v.prefixes.Count]
                        Emit @{kind='iteration';id=$v.id;iteration=$i;prefix=$prefix;status='STARTED'}
                        SwitchVector $prefix
                        Emit @{kind='iteration';id=$v.id;iteration=$i;prefix=$prefix;status='OBSERVED';oldField=$old.Text;newField=$new.Text;expectedTarget=([string][char]0x597D);targetMatches=($new.Text -ceq ([string][char]0x597D));reason='Target equality alone does not prove no source corruption'}
                    }
                }
            }
            $last=Snapshot 'final'
            $last.kind='case';$last.status='OBSERVED';$last.reason='Raw sequence captured; no automatic semantic PASS';Emit $last
            $script:finished[$v.id]=$true
        } catch {
            NotRun $v.id ('Incomplete: '+$_.Exception.Message)
            $script:finished[$v.id]=$true
            # Abort on lost focus / input failure. Never send subsequent keys elsewhere.
            throw
        }
    }
    Emit @{kind='end';status='OBSERVED';vectors=17;reason='All vectors recorded; review snapshots and NOT_RUN subcases, not a PASS summary'}
} catch {
    Emit @{kind='error';status='NOT_RUN';id=$script:current;message=$_.Exception.Message;detail=$_.ScriptStackTrace}
    foreach ($v in $vectors) { if (-not $script:finished.ContainsKey($v.id)) { NotRun $v.id ('Prerequisite/earlier failure: '+$_.Exception.Message) } }
    Write-Warning $_.Exception.Message
} finally {
    if ($null -ne $form) { $form.Close();$form.Dispose() }
    if ($null -ne $other) { $other.Close();$other.Dispose() }
    if ($clipboardSaved) {
        try { if ($null -ne $clipboard) { [Windows.Forms.Clipboard]::SetDataObject($clipboard,$true) } else { [Windows.Forms.Clipboard]::Clear() } }
        catch { Emit @{kind='warning';message=('Clipboard restoration failed: '+$_.Exception.Message)} }
    }
    $writer.Dispose()
    Write-Output ('Results: '+$OutputDirectory)
}
