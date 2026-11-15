<#
.SYNOPSIS
    准备内嵌 KuGouMusicApi 服务目录（发布包随包附带，用户装完即用）。

.DESCRIPTION
    TX Music 客户端本身只是本地 Node 服务的前端壳。为了让发布包在别人的电脑上
    零配置可用，这里把服务代码 + 生产依赖 + node 运行时整理到 dist\kugou_api，
    由 tools\package_windows.ps1 一起塞进 Release 目录。

    产物结构：
        dist\kugou_api\
            node.exe          随包 node 运行时（约 80 MB）
            app.js server.js  服务入口
            module\ util\     接口实现
            node_modules\     仅生产依赖
            .env              platform=lite / HOST=127.0.0.1

.PARAMETER Source
    KuGouMusicApi 源码目录。默认依次尝试：环境变量 KUGOU_API_SOURCE、
    D:\tengxin\Desktop\Flutter\KuGouMusicApi、上级目录 .\KuGouMusicApi。

.PARAMETER NodeExe
    用作随包运行时的 node.exe。默认依次尝试：环境变量 TXMUSIC_NODE_EXE、
    .local\third_party\node\node.exe 缓存、PATH 中的 node。

.PARAMETER OutDir
    输出目录，默认 <项目根>\dist\kugou_api。

.PARAMETER Force
    已存在时先清空重建（默认增量覆盖）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\prepare_kugou_api.ps1
#>
[CmdletBinding()]
param(
    [string]$Source = '',
    [string]$NodeExe = '',
    [string]$OutDir = '',
    [switch]$Force,
    # 缓存里没有官方 node 时是否自动下载（-DownloadNode:$false 可关闭）
    [bool]$DownloadNode = $true
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $projectRoot 'dist\kugou_api'
}

function Write-Step($message) { Write-Host "[kugou_api] $message" -ForegroundColor Cyan }
function Fail($message) { Write-Host "[kugou_api] 失败：$message" -ForegroundColor Red; exit 1 }

# 下载官方 Windows x64 node 运行时并缓存到 .local\third_party\node\node.exe。
# 不直接打包本机其它软件自带的 node：分发给别人不合适。
function Get-OfficialNode {
    param([string]$Version, [string]$CacheDir)

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $zipName = "node-$Version-win-x64.zip"
    $url = "https://nodejs.org/dist/$Version/$zipName"
    $workDir = Join-Path $CacheDir '_tmp'
    if (-not (Test-Path $workDir)) { New-Item -ItemType Directory -Path $workDir -Force | Out-Null }
    $zipPath = Join-Path $workDir $zipName

    Write-Step "下载官方 node 运行时：$url"
    try {
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing -TimeoutSec 600
    } catch {
        Fail "下载 node 失败（$($_.Exception.Message)）。可用 -NodeExe 指定本机 node.exe，或把 node.exe 放到 .local\third_party\node\node.exe。"
    }

    $extractDir = Join-Path $workDir "解压"
    if (Test-Path $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force }
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force
    $found = Get-ChildItem -LiteralPath $extractDir -Recurse -Filter 'node.exe' | Select-Object -First 1
    if (-not $found) { Fail '解压后未找到 node.exe' }

    $target = Join-Path $CacheDir 'node.exe'
    Copy-Item -LiteralPath $found.FullName -Destination $target -Force
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    return $target
}

# ------------------------------------------------------------------ 定位源码
if ([string]::IsNullOrWhiteSpace($Source)) {
    $envSource = $env:KUGOU_API_SOURCE
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($envSource)) { $candidates += $envSource }
    $candidates += 'D:\tengxin\Desktop\Flutter\KuGouMusicApi'
    $candidates += (Join-Path (Split-Path -Parent $projectRoot) 'KuGouMusicApi')
    foreach ($c in $candidates) {
        if ((Test-Path $c) -and (Test-Path (Join-Path $c 'app.js'))) { $Source = $c; break }
    }
}
if ([string]::IsNullOrWhiteSpace($Source) -or -not (Test-Path (Join-Path $Source 'app.js'))) {
    Fail "未找到 KuGouMusicApi 源码，请用 -Source 指定目录（需包含 app.js）。"
}
$Source = (Resolve-Path $Source).Path
Write-Step "源码目录：$Source"

# ------------------------------------------------------------------ 清理输出
if ($Force -and (Test-Path $OutDir)) {
    Write-Step "清空已有产物：$OutDir"
    Remove-Item -LiteralPath $OutDir -Recurse -Force
}
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

# ------------------------------------------------------------------ 拷贝服务代码
$files = @('app.js', 'server.js', 'main.js', 'index.js', 'package.json', 'package-lock.json', 'interface.d.ts')
$dirs  = @('util', 'module', 'public')

foreach ($f in $files) {
    $src = Join-Path $Source $f
    if (Test-Path $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $OutDir $f) -Force
    }
}
foreach ($d in $dirs) {
    $src = Join-Path $Source $d
    if (Test-Path $src) {
        # 用 Copy-Item 而非 robocopy：robocopy 的状态输出会写 stderr，
        # 在 $ErrorActionPreference='Stop' 下会被当成致命错误。
        Copy-Item -LiteralPath $src -Destination (Join-Path $OutDir $d) -Recurse -Force
    }
}
Write-Step '服务代码已就位'

# ------------------------------------------------------------------ 生产依赖
$nodeModules = Join-Path $OutDir 'node_modules'
if (-not (Test-Path $nodeModules)) {
    $srcModules = Join-Path $Source 'node_modules'
    if (Test-Path $srcModules) {
        Write-Step '复制 node_modules（约 4000 个文件，稍等）'
        Copy-Item -LiteralPath $srcModules -Destination $nodeModules -Recurse -Force
    }
}

$npm = Get-Command npm -ErrorAction SilentlyContinue
if ($npm) {
    Write-Step 'npm prune --omit=dev（裁掉 pkg/typescript 等开发依赖）'
    Push-Location $OutDir
    try {
        # 走 cmd 调用，避开 PowerShell 对 npm 输出（stderr 进度条）的处理。
        cmd /c "npm prune --omit=dev --ignore-scripts --no-audit --no-fund >nul 2>&1"
        if ($LASTEXITCODE -ne 0) { Write-Warning 'npm prune 未成功，保留全部依赖（体积偏大但能跑）' }
    } finally {
        Pop-Location
        $global:LASTEXITCODE = 0
    }
} else {
    Write-Warning '未找到 npm，跳过依赖裁剪'
}

if (-not (Test-Path (Join-Path $OutDir 'node_modules\express'))) {
    Fail 'node_modules 缺少 express，服务无法启动。请先在源码目录执行 npm install。'
}

# ------------------------------------------------------------------ node 运行时
# 优先官方（缓存 → 下载），其次手动指定，最后 PATH。
$nodeVersionWanted = $env:TXMUSIC_NODE_VERSION
if ([string]::IsNullOrWhiteSpace($nodeVersionWanted)) { $nodeVersionWanted = 'v22.12.0' }

$cacheDir = Join-Path $projectRoot '.local\third_party\node'
$cached = Join-Path $cacheDir 'node.exe'

if ([string]::IsNullOrWhiteSpace($NodeExe)) {
    if (Test-Path $cached) {
        $NodeExe = $cached
    } elseif (-not [string]::IsNullOrWhiteSpace($env:TXMUSIC_NODE_EXE)) {
        $NodeExe = $env:TXMUSIC_NODE_EXE
    } elseif ($DownloadNode) {
        $NodeExe = Get-OfficialNode -Version $nodeVersionWanted -CacheDir $cacheDir
    } else {
        $onPath = Get-Command node -ErrorAction SilentlyContinue
        if ($onPath) { $NodeExe = $onPath.Source }
    }
}
if ([string]::IsNullOrWhiteSpace($NodeExe) -or -not (Test-Path $NodeExe)) {
    Fail '未找到 node.exe：请用 -NodeExe 指定，或把 node.exe 放到 .local\third_party\node\node.exe 做缓存。'
}

$targetNode = Join-Path $OutDir 'node.exe'
Copy-Item -LiteralPath $NodeExe -Destination $targetNode -Force
# 只读文件版本信息，不启动 node：省掉 native 调用的输出处理麻烦。
$nodeVersion = (Get-Item -LiteralPath $targetNode).VersionInfo.ProductVersion
Write-Step "node 运行时：$NodeExe（v$nodeVersion）"

# ------------------------------------------------------------------ .env
# platform=lite：概念版接口（每日领 VIP 依赖它）；HOST 只绑回环，
# 避免防火墙弹窗与把本地代理暴露到局域网；PORT 由客户端启动时用 --port 指定。
$envContent = @(
    '# Generated by tools/prepare_kugou_api.ps1. Do not edit this copy.',
    '# Change .env in the KuGouMusicApi source directory instead.',
    "platform='lite'",
    "PORT=''",
    "KUGOU_API_PROXY=''",
    "KUGOU_API_GUID=''",
    "KUGOU_API_DEV=''",
    "KUGOU_API_MAC=''",
    "KUGOU_API_WEBGL=''",
    "HOST='127.0.0.1'"
) -join "`r`n"
Set-Content -LiteralPath (Join-Path $OutDir '.env') -Value $envContent -Encoding ASCII

# ------------------------------------------------------------------ 上游补丁
# generate_simulate.js 调用了 generateWebGLHash，却没有从 util.js 导入它，
# 运行期抛 ReferenceError，导致 /song/url 拿不到播放地址（表现为 502）。
$simulatePath = Join-Path $OutDir 'util\generate_simulate.js'
if (Test-Path -LiteralPath $simulatePath) {
    $simulateRaw = [System.IO.File]::ReadAllText($simulatePath)
    $brokenRequire = "const { randomString } = require('./util');"
    $fixedRequire = "const { randomString, generateWebGLHash } = require('./util');"
    if ($simulateRaw.Contains($brokenRequire)) {
        $simulateRaw = $simulateRaw.Replace($brokenRequire, $fixedRequire)
        [System.IO.File]::WriteAllText($simulatePath, $simulateRaw, (New-Object System.Text.UTF8Encoding($false)))
        Write-Step '已修补 generate_simulate.js：补全 generateWebGLHash 导入'
    } elseif ($simulateRaw.Contains($fixedRequire)) {
        Write-Step '补丁已存在，跳过'
    } else {
        Write-Warning '未找到可修补的 require 行，/song/url 可能报错，请检查上游源码'
    }
}

# ------------------------------------------------------------------ 汇报
$sum = Get-ChildItem -LiteralPath $OutDir -Recurse -File -ErrorAction SilentlyContinue |
    Measure-Object -Property Length -Sum
$mb = [math]::Round($sum.Sum / 1MB, 1)
Write-Host ''
Write-Host "产物：$OutDir" -ForegroundColor Green
Write-Host "体积：$mb MB / $($sum.Count) 个文件" -ForegroundColor Green
Write-Host '自检命令：cd dist\kugou_api; .\node.exe app.js --port=3999' -ForegroundColor DarkGray
