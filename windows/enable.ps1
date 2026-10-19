# Add KINFX Input to the current user's zh-TW (繁中) input methods. Run as the user, not admin.
# Never touches other languages; never switches the default away from what the user had.
param([switch]$Remove)
$tip = '0404:{42EBBC99-2AAD-4AF6-A8D9-2552AD948ED3}{35BE04B0-E9E0-4E06-8438-10BFDCAE9E41}'
$list = Get-WinUserLanguageList
$tw = $list | Where-Object { $_.LanguageTag -eq 'zh-Hant-TW' }
if (-not $tw) {
  if ($Remove) { exit 0 }
  $list.Add('zh-Hant-TW')
  $tw = $list | Where-Object { $_.LanguageTag -eq 'zh-Hant-TW' }
}
if ($Remove) { [void]$tw.InputMethodTips.Remove($tip) }
elseif (-not $tw.InputMethodTips.Contains($tip)) { $tw.InputMethodTips.Add($tip) }
Set-WinUserLanguageList $list -Force
