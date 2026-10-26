$ErrorActionPreference='Stop'
try {
 Write-Host '启动诊断：PowerShell 已启动。' -ForegroundColor Green
 Write-Host ('版本：'+$PSVersionTable.PSVersion.ToString())
 Write-Host ('程序目录：'+$PSScriptRoot)
 if ([IO.Path]::GetPathRoot($PSScriptRoot) -ne 'D:\') { throw '请把整个文件夹解压到 D 盘，再运行。' }
 Write-Host '正在打开翻译工具界面；此操作不会自动修改游戏。'
 & (Join-Path $PSScriptRoot 'Installer.ps1')
 Write-Host '安装界面已关闭。' -ForegroundColor Green
} catch {
 Write-Host '启动失败：请把下方错误截图发来。' -ForegroundColor Red
 Write-Host $_.Exception.ToString() -ForegroundColor Red
 Write-Host $_.InvocationInfo.PositionMessage
 Write-Host $_.ScriptStackTrace
 exit 1
}
