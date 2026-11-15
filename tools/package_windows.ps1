<#
.SYNOPSIS
    一键打包 TX Music Windows 发布版（自带 KuGouMusicApi 服务 + node 运行时）。

.DESCRIPTION
    流程：
      1. tools\prepare_kugou_api.ps1  → dist\kugou_api（服务代码 + 生产依赖 + 官方 node.exe）
      2. flutter build windows --release
      3. 把 dist\kugou_api 拷进 Release\kugou_api（客户端启动时会自动拉起）
      3.1 把 Visual Studio 的 VC++ 运行库（msvcp140 / vcruntime140 等）拷进 Release，
          让干净系统无需另装 vc_redist 也能双击运行
      4. 打成 dist\TXMusic-<版本>-win64.zip

    产物是绿色包：解压到任意目录、双击 txmusic.exe 即可用，
    不需要朋友另外装 Node.js，也不需要装 VC++ 运行库，
    也不会写到安装目录（登录态在 %APPDATA%\TXMusic）。

    运行库目录的查找顺序：环境变量 TXMUSIC_VC_CRT → vswhere 报告的 VS 安装路径
    → 常见安装路径（含 D:\APP 这类非默认盘）。都找不到时退回 System32 里的同名 DLL。

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

# 从 Visual Studio 的 VC Redist 目录里找出 x64 版 CRT 的原生 DLL 所在目录。
# 顺序：环境变量 TXMUSIC_VC_CRT → vswhere 报告的安装路径 → 常见安装路径（含非默认盘符）。
# 找不到返回 $null，由调用方决定兜底或告警。
function Resolve-VcCrtDir {
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:TXMUSIC_VC_CRT) { $candidates.Add($env:TXMUSIC_VC_CRT) }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $installs = & $vswhere -products * -property installationPath 2>$null
        foreach ($ip in $installs) {
            if ($ip) { $candidates.Add((Join-Path $ip 'VC\Redist\MSVC')) }
        }
    }

    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, 'C:\Program Files', 'D:\APP', 'D:\Program Files', 'E:\APP')) {
        if (-not $root -or -not (Test-Path $root)) { continue }
        Get-ChildItem -LiteralPath $root -Directory -Filter '*Visual Studio*' -ErrorAction SilentlyContinue |
            ForEach-Object { $candidates.Add((Join-Path $_.FullName 'VC\Redist\MSVC')) }
    }

    foreach ($dir in $candidates) {
        if (-not (Test-Path $dir)) { continue }
        $crtDirs = Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory -Filter 'x64' -ErrorAction SilentlyContinue } |
            ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue }
        foreach ($crt in $crtDirs) {
            if (Test-Path (Join-Path $crt.FullName 'msvcp140.dll')) { return $crt.FullName }
        }
    }
    return $null
}

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

# ------------------------------------------------------------------ 3.1 VC++ 运行库
# txmusic.exe 与 flutter_windows.dll 都是 /MD 编译，依赖 MSVCP140 等 CRT DLL。
# 干净系统（虚拟机、重装的新机器）没装过 VC++ 2015-2022 运行库，双击就会报「找不到 MSVCP140.dll」。
# 这里把 CRT 直接放进 exe 同目录做 app-local 部署：Windows 加载 DLL 时程序目录优先于 System32，
# 于是发布包自带运行库，不用教别人去装 vc_redist。
$crtNames = @(
    'concrt140.dll',
    'msvcp140.dll',
    'msvcp140_1.dll',
    'msvcp140_2.dll',
    'msvcp140_atomic_wait.dll',
    'msvcp140_codecvt_ids.dll',
    'vccorlib140.dll',
    'vcruntime140.dll',
    'vcruntime140_1.dll',
    'vcruntime140_threads.dll'
)
$crtSource = Resolve-VcCrtDir
$crtCopied = 0
if ($crtSource) {
    foreach ($name in $crtNames) {
        $src = Join-Path $crtSource $name
        if (Test-Path $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $release $name) -Force
            $crtCopied++
        }
    }
    Write-Step "内置 VC++ 运行库 $crtCopied 个 DLL ← $crtSource"
} else {
    Write-Step '未找到 VS 的 VC Redist 目录，改从 System32 兜底'
    foreach ($name in $crtNames) {
        $src = Join-Path $env:SystemRoot "System32\$name"
        if (Test-Path $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $release $name) -Force
            $crtCopied++
        }
    }
    if ($crtCopied -gt 0) {
        Write-Step "内置 VC++ 运行库 $crtCopied 个 DLL（System32 兜底）"
    } else {
        Write-Host '[package] 警告：未能内置 VC++ 运行库，目标机需自行安装 vc_redist.x64.exe' -ForegroundColor Yellow
    }
}

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
    '已内置 VC++ 运行库（msvcp140.dll / vcruntime140.dll 等），干净系统也不用另装，',
    '请不要单独删除 exe 同目录下的这些 dll，否则会提示找不到 MSVCP140.dll。',
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
