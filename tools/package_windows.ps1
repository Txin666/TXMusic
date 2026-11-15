<#
.SYNOPSIS
    一键打包 TX Music Windows 发布版（自带 KuGouMusicApi 服务 + node 运行时）。

.DESCRIPTION
    流程：
      1. tools\prepare_kugou_api.ps1  → dist\kugou_api（服务代码 + 生产依赖 + 官方 node.exe）
      2. flutter build windows --release
      3. 把 dist\kugou_api 拷进 Release\kugou_api（客户端启动时会自动拉起）
      4. 打成 dist\TXMusic-<版本>-win64.zip

    产物是绿色包：解压到任意目录、双击 txmusic.exe 即可用，
    不需要朋友另外装 Node.js，也不会写到安装目录（登录态在 %APPDATA%\TXMusic）。

.PARAMETER Configuration
    Release（默认）/ Debug / Profile。

.PARAMETER SkipBuild
    跳过 flutter build（已有构建产物时用，省时间）。

.PARAMETER NoZip
    只把服务拷进 Release，不压缩。

.PARAMETER SkipService
    跳过服务准备（dist\kugou_api 已就绪时用）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\package_windows.ps1
#>
[CmdletBinding()]
param(
    [string]$Configuration = 'Release',
    [switch]$SkipBuild,
    [switch]$SkipService,
    [switch]$NoZip
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

function Write-Step($message) { Write-Host "[package] $message" -ForegroundColor Cyan }
function Fail($message) { Write-Host "[package] 失败：$message" -ForegroundColor Red; exit 1 }

# ------------------------------------------------------------------ 版本号
$pubspec = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Raw
$match = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)')
$version = if ($match.Success) { $match.Groups[1].Value } else { '0.0.0' }
Write-Step "版本：$version / 配置：$Configuration"

# ------------------------------------------------------------------ 1. 服务
if (-not $SkipService) {
    & (Join-Path $PSScriptRoot 'prepare_kugou_api.ps1')
    if (-not $?) { Fail '准备内嵌服务失败' }
}
$serviceDir = Join-Path $projectRoot 'dist\kugou_api'
if (-not (Test-Path (Join-Path $serviceDir 'node.exe'))) {
    Fail '缺少 dist\kugou_api\node.exe，请先运行 tools\prepare_kugou_api.ps1'
}

# ------------------------------------------------------------------ 2. 构建
if (-not $SkipBuild) {
    Write-Step "flutter build windows --$($Configuration.ToLower())"
    # 用 Start-Process 而非 cmd /c：flutter 会往 stderr 输出提示，
    # 在 $ErrorActionPreference='Stop' 下会被当成异常抛出。
    $buildProc = Start-Process -FilePath 'cmd.exe' `
        -ArgumentList '/c', "flutter build windows --$($Configuration.ToLower())" `
        -NoNewWindow -Wait -PassThru
    if ($buildProc.ExitCode -ne 0) { Fail "flutter build 失败（exit $($buildProc.ExitCode)）" }
}

$release = Join-Path $projectRoot "build\windows\x64\runner\$Configuration"
if (-not (Test-Path $release)) { Fail "构建产物不存在：$release" }
if (-not (Test-Path (Join-Path $release 'txmusic.exe'))) { Fail "未找到 txmusic.exe（$release）" }

# ------------------------------------------------------------------ 3. 内嵌服务
$target = Join-Path $release 'kugou_api'
if (Test-Path $target) {
    Write-Step '清掉旧的 kugou_api'
    Remove-Item -LiteralPath $target -Recurse -Force
}
Write-Step '拷贝 kugou_api 到 Release'
Copy-Item -LiteralPath $serviceDir -Destination $target -Recurse -Force

# 启动日志会写到 %APPDATA%\TXMusic\kugou_api.log，包里不该有历史日志
Get-ChildItem -LiteralPath $target -Filter '*.log' -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

# ------------------------------------------------------------------ 4. 使用说明
$readme = @(
    'TX Music 便携版',
    '',
    '用法：解压到任意目录（路径别带敏感权限限制），双击 txmusic.exe 启动。',
    '首次启动会在 %APPDATA%\TXMusic 建配置目录，登录态与播放进度都存在这里，',
    '所以整个文件夹可以随便挪位置，也可以直接删掉重装。',
    '',
    '自带本地音乐服务（kugou_api 文件夹 + node.exe），无需另外安装 Node.js。',
    '若杀毒软件拦截 node.exe，请手动放行；服务只监听 127.0.0.1，不对外暴露。',
    '',
    '出问题时看日志：',
    '  %APPDATA%\TXMusic\kugou_api.log   本地服务日志',
    '  %APPDATA%\TXMusic\boot.log        客户端启动日志',
    '',
    "版本：$version"
) -join "`r`n"
Set-Content -LiteralPath (Join-Path $release '使用说明.txt') -Value $readme -Encoding Unicode

# ------------------------------------------------------------------ 5. 压缩
if (-not $NoZip) {
    $distDir = Join-Path $projectRoot 'dist'
    if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir -Force | Out-Null }
    $zip = Join-Path $distDir "TXMusic-$version-win64.zip"
    if (Test-Path $zip) { Remove-Item -LiteralPath $zip -Force }

    Write-Step "压缩到 $zip"
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    Push-Location $release
    try {
        if (Test-Path $tar) {
            # tar.exe 走 libarchive，比 Compress-Archive 快很多
            & $tar -a -c -f $zip *
            if ($LASTEXITCODE -ne 0) { Fail "压缩失败（tar exit $LASTEXITCODE）" }
        } else {
            Compress-Archive -Path (Join-Path $release '*') -DestinationPath $zip -CompressionLevel Optimal
        }
    } finally {
        Pop-Location
    }
}

# ------------------------------------------------------------------ 汇报
$sum = Get-ChildItem -LiteralPath $release -Recurse -File -ErrorAction SilentlyContinue |
    Measure-Object -Property Length -Sum
Write-Host ''
Write-Host "发布目录：$release（$([math]::Round($sum.Sum / 1MB, 1)) MB）" -ForegroundColor Green
if (-not $NoZip) {
    $zipSize = [math]::Round((Get-Item $zip).Length / 1MB, 1)
    Write-Host "压缩包　：$zip（$zipSize MB）" -ForegroundColor Green
}
Write-Host '直接把这个文件夹（或 zip）丢给朋友，双击 txmusic.exe 就能用。' -ForegroundColor DarkGray
