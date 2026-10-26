param([ValidateSet('UI','Inspect','Install','Uninstall')][string]$Action='UI', [string]$GamePath='')
$ErrorActionPreference='Stop'
$PluginName='LocalChineseTranslator'
$BackupName='.localchinese-translator-backup'
$Utf8=[Text.UTF8Encoding]::new($false)

function Resolve-Game([string]$Folder) {
 $base=[IO.Path]::GetFullPath($Folder)
 if ([IO.Path]::GetPathRoot($base) -ne 'D:\') { throw '此版本仅允许选择 D 盘游戏。请先将游戏完整移到 D 盘，再选择文件夹。' }
 $check=Get-Item -LiteralPath $base
 while ($null -ne $check) {
  if ($check.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '不支持链接或重定向目录，请选择实际位于 D 盘的游戏。' }
  $check=$check.Parent
 }

 foreach ($candidate in @($base,(Join-Path $base 'www'))) {
  foreach ($relative in @('', 'js', 'js\plugins', 'js\plugins.js', '.localchinese-translator-backup')) {
   $target=if ($relative) { Join-Path $candidate $relative } else { $candidate }
   if ((Test-Path -LiteralPath $target) -and ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '不支持重定向的游戏子目录或文件。' }
  }
  $manifest=Join-Path $candidate 'js\plugins.js'
  if ((Test-Path -LiteralPath $manifest) -and (Test-Path -LiteralPath (Join-Path $candidate 'data\System.json'))) {
   $engine=if (Test-Path -LiteralPath (Join-Path $candidate 'js\rmmz_core.js')) { 'MZ' } elseif (Test-Path -LiteralPath (Join-Path $candidate 'js\rpg_core.js')) { 'MV' } else { $null }
   if ($engine) { return [pscustomobject]@{Root=$candidate; Engine=$engine; Manifest=$manifest; Plugin=(Join-Path $candidate ('js\plugins\'+$PluginName+'.js')); Backup=(Join-Path $candidate $BackupName)} }
  }
 }
 throw '没有找到普通的 RPG Maker MV/MZ 游戏。请选择 Game.exe 所在文件夹或 www 文件夹。XP/VX/VX Ace、网页链接及封装数据不受支持。'
}
function Read-Plugins([string]$Path) {
 $text=[IO.File]::ReadAllText($Path)
 # Read JSON only. Never evaluate game scripts in the installer.
 $pattern='(?s)\A\s*(?://[^\r\n]*(?:\r?\n|\z)\s*)*var\s+\$plugins\s*=\s*(\[.*\])\s*;\s*\z'
 $match=[regex]::Match($text,$pattern)
 if (-not $match.Success) { throw 'plugins.js 不是标准插件列表，为避免破坏游戏，已停止。' }
 if ($match.Groups[1].Value -match '^\s*\[\s*\]\s*$') { return ,@() }
 $parsed=ConvertFrom-Json -InputObject $match.Groups[1].Value
 foreach ($entry in @($parsed)) {
  if ($null -eq $entry -or -not ($entry.name -is [string]) -or -not ($entry.status -is [bool])) { throw '插件列表结构异常，已停止。' }
 }
 return ,@($parsed)
}
function Encode-Plugins($Entries) {
 $json=ConvertTo-Json -InputObject @($Entries) -Depth 100
 return '// Generated plugin list; original backed up by LocalChineseTranslator.'+"`r`n"+'var $plugins = '+$json+';'+"`r`n"
}
function Hash-Bytes([byte[]]$Bytes) {
 $sha=[Security.Cryptography.SHA256]::Create()
 try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
}
function Write-Atomic([string]$Path,[byte[]]$Bytes) {
 $tmp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try {
  [IO.File]::WriteAllBytes($tmp,$Bytes)
  if (Test-Path -LiteralPath $Path) {
   # PowerShell 5.1 can coerce $null to an empty string for this .NET string argument.
   # Use an explicit absolute backup path, then remove it only after a successful replace.
   $swapBackup=$Path+'.'+[guid]::NewGuid().ToString('N')+'.replace-backup'
   [IO.File]::Replace($tmp,$Path,$swapBackup)
   Remove-Item -LiteralPath $swapBackup -Force -ErrorAction SilentlyContinue
  } else { [IO.File]::Move($tmp,$Path) }
 } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } }
}
function Install-Translator($Game) {
 if (Test-Path -LiteralPath $Game.Backup) {
  $recoveryStatePath=Join-Path $Game.Backup 'state.json'
  if (Test-Path -LiteralPath $recoveryStatePath) {
   $recoveryState=ConvertFrom-Json ([IO.File]::ReadAllText($recoveryStatePath))
   if ($recoveryState.tool -eq 'LocalChineseTranslator' -and $recoveryState.version -eq 1 -and
       (Hash-Bytes ([IO.File]::ReadAllBytes($Game.Manifest))) -eq $recoveryState.originalHash) {
    # Only auto-recover when the manifest is provably still the original.
    # Uninstall verifies the backup and any remaining plugin before changing anything.
    $null=Uninstall-Translator $Game
   }
  }
  if (Test-Path -LiteralPath $Game.Backup) { throw '已有安装记录。请先点击“卸载还原”，再重新安装；请保留备份目录。' }
 }
 if (Test-Path -LiteralPath $Game.Plugin) { throw '游戏已有同名插件，未覆盖。' }
 $entries=Read-Plugins $Game.Manifest
 if (@($entries | Where-Object { $_.name -eq $PluginName }).Count) { throw '列表中已有同名插件，未修改。' }
 $pluginSource=Join-Path $PSScriptRoot ($PluginName+'.js')
 $pluginBytes=[IO.File]::ReadAllBytes($pluginSource)
 $original=[IO.File]::ReadAllBytes($Game.Manifest)
 $newEntry=[pscustomobject]@{name=$PluginName;status=$true;description='游戏内中文翻译（实验版）';parameters=[pscustomobject]@{}}
 $updated=$Utf8.GetBytes((Encode-Plugins (@($entries)+@($newEntry))))
 $state=[pscustomobject]@{tool='LocalChineseTranslator';version=1;originalHash=(Hash-Bytes $original);installedHash=(Hash-Bytes $updated);pluginHash=(Hash-Bytes $pluginBytes)}
 [void][IO.Directory]::CreateDirectory($Game.Backup)
 [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Game.Plugin))
 # Persist recovery information BEFORE touching game files.
 [IO.File]::WriteAllBytes((Join-Path $Game.Backup 'plugins.js.original'),$original)
 [IO.File]::WriteAllText((Join-Path $Game.Backup 'state.json'),(ConvertTo-Json $state),$Utf8)
 try {
  Write-Atomic $Game.Plugin $pluginBytes
  Write-Atomic $Game.Manifest $updated
 } catch {
  $installError=$_
  # The backup remains so recovery can be retried even if a file is locked.
  try { Write-Atomic $Game.Manifest $original } catch {}
  if ((Test-Path -LiteralPath $Game.Plugin) -and (Hash-Bytes ([IO.File]::ReadAllBytes($Game.Plugin))) -eq $state.pluginHash) {
   Remove-Item -LiteralPath $Game.Plugin -Force -ErrorAction SilentlyContinue
  }
  throw $installError
 }
 return '安装完成（'+$Game.Engine+'）。现在启动 Game.exe。右上角可查看状态，F6 暂停/恢复。首次翻译需要联网。'
}
function Uninstall-Translator($Game) {
 $statePath=Join-Path $Game.Backup 'state.json'
 $originalPath=Join-Path $Game.Backup 'plugins.js.original'
 if (-not (Test-Path -LiteralPath $statePath) -or -not (Test-Path -LiteralPath $originalPath)) { throw '没有完整的本工具备份，未修改游戏。' }
 $state=ConvertFrom-Json ([IO.File]::ReadAllText($statePath))
 if ($state.tool -ne 'LocalChineseTranslator' -or $state.version -ne 1) { throw '备份记录异常，未修改游戏。' }
 $original=[IO.File]::ReadAllBytes($originalPath)
 if ((Hash-Bytes $original) -ne $state.originalHash) { throw '备份校验失败，未修改游戏。' }
 $pluginExists=Test-Path -LiteralPath $Game.Plugin
 if ($pluginExists -and (Hash-Bytes ([IO.File]::ReadAllBytes($Game.Plugin))) -ne $state.pluginHash) { throw '本工具插件已被手动修改，未覆盖或删除。请先保留修改，再处理卸载。' }
 $currentHash=Hash-Bytes ([IO.File]::ReadAllBytes($Game.Manifest))
 if ($currentHash -eq $state.installedHash -or $currentHash -eq $state.originalHash) {
  Write-Atomic $Game.Manifest $original
 } else {
  # If another plugin was installed later, remove only our entry.
  $entries=Read-Plugins $Game.Manifest
  $remaining=@($entries | Where-Object { $_.name -ne $PluginName })
  Write-Atomic $Game.Manifest ($Utf8.GetBytes((Encode-Plugins $remaining)))
 }
 if ($pluginExists) { Remove-Item -LiteralPath $Game.Plugin -Force }
 # Keep originals for manual recovery, and allow a future fresh installation.
 $archived=$Game.Backup+'-removed-'+[datetime]::Now.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)
 [IO.Directory]::Move($Game.Backup,$archived)
 return '已卸载。原始游戏数据与存档均未修改。备份已保留在游戏目录中（目录名结尾为 removed…）。'
}

if ($Action -ne 'UI') {
 $game=Resolve-Game $GamePath
 switch ($Action) {
  'Inspect' { $game; break }
  'Install' { Install-Translator $game; break }
  'Uninstall' { Uninstall-Translator $game; break }
 }
 exit
}
Add-Type -AssemblyName @('System.Windows.Forms','System.Drawing')
[Windows.Forms.Application]::EnableVisualStyles()
$form=[Windows.Forms.Form]::new(); $form.Text='RPG Maker 游戏内中文翻译 · MV / MZ · 0.1.2 · D盘版'; $form.Size=[Drawing.Size]::new(690,430)
$form.StartPosition='CenterScreen'; $form.Font=[Drawing.Font]::new('Microsoft YaHei UI',10); $form.FormBorderStyle='FixedDialog'; $form.MaximizeBox=$false
$intro=[Windows.Forms.Label]::new(); $intro.SetBounds(20,18,640,66)
$intro.Text="把对话和菜单译为中文，直接显示在游戏原位置。`n支持普通 Windows 桌面版 MV / MZ。操作前请关闭游戏。"
$pathBox=[Windows.Forms.TextBox]::new(); $pathBox.SetBounds(20,94,520,30)
$browse=[Windows.Forms.Button]::new(); $browse.Text='选择游戏…'; $browse.SetBounds(550,91,105,34)
$install=[Windows.Forms.Button]::new(); $install.Text='安装中文翻译'; $install.SetBounds(20,145,200,42)
$remove=[Windows.Forms.Button]::new(); $remove.Text='卸载还原'; $remove.SetBounds(240,145,180,42)
$privacy=[Windows.Forms.Label]::new(); $privacy.SetBounds(20,205,640,70)
$privacy.Text="翻译需要联网：游戏文字会发送至 Google 翻译，译文仅在 D:\RPGTranslator\cache 缓存。`n免费网页接口属于实验功能，可能限流或连接失败；失败时显示原文。`n安装会备份并修改插件列表，加入一个插件；不会改写游戏数据或存档。"
$status=[Windows.Forms.TextBox]::new(); $status.SetBounds(20,288,635,75); $status.ReadOnly=$true; $status.Multiline=$true; $status.ScrollBars='Vertical'; $status.Text='请选择 Game.exe 所在文件夹（也可以选择 www 文件夹）。'
$form.Controls.AddRange(@($intro,$pathBox,$browse,$install,$remove,$privacy,$status))
$browse.Add_Click({
 $dialog=[Windows.Forms.FolderBrowserDialog]::new(); $dialog.Description='选择 Game.exe 所在文件夹或 www 文件夹'
 try { if ($dialog.ShowDialog() -eq 'OK') { $pathBox.Text=$dialog.SelectedPath; try { $game=Resolve-Game $pathBox.Text; $status.Text='检测到 RPG Maker '+$game.Engine+'。请关闭游戏，再点击安装。' } catch { $status.Text=$_.Exception.Message } } } finally { $dialog.Dispose() }
})
$install.Add_Click({
 try {
  $game=Resolve-Game $pathBox.Text
  $answer=[Windows.Forms.MessageBox]::Show($form,'请确认游戏已关闭。安装后启动游戏会自动将游戏文字发送给 Google 翻译。是否安装？','安装中文翻译','YesNo','Question')
  if ($answer -ne 'Yes') { return }
  $status.Text=Install-Translator $game
 } catch { $status.Text='未完成：'+$_.Exception.Message }
})
$remove.Add_Click({
 try { $game=Resolve-Game $pathBox.Text; $status.Text=Uninstall-Translator $game } catch { $status.Text='未完成：'+$_.Exception.Message }
})
try { [void]$form.ShowDialog() } finally { $form.Dispose() }
