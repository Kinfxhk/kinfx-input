Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$p = Start-Process 'C:\Program Files\KINFX Input\KINFXSettings.exe' -PassThru
Start-Sleep 3
$w = [Windows.Automation.AutomationElement]::RootElement.FindFirst([Windows.Automation.TreeScope]::Children,
  (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)))
$names = @($w.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition) |
  ForEach-Object { $_.Current.ControlType.ProgrammaticName.Replace('ControlType.', '') + ':' + $_.Current.Name })
$r = @('title=' + $w.Current.Name) + $names
Stop-Process -Id $p.Id -Force
[IO.File]::WriteAllLines('C:\Users\KinTest\inst\kx-ui.txt', [string[]]$r, (New-Object Text.UTF8Encoding($false)))
