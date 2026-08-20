& {
    $logPath = "D:\Wuthering Waves\Wuthering Waves Game\Client\Saved\Logs\Client.log"

    if (-not (Test-Path $logPath)) {
        Write-Host "未找到 Client.log" -ForegroundColor Red
        return
    }

    # 读取
    $fs = [System.IO.File]::Open(
        $logPath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )

    try {
        $ms = New-Object System.IO.MemoryStream
        $fs.CopyTo($ms)
        $bytes = $ms.ToArray()
        $ms.Dispose()
    }
    finally {
        $fs.Dispose()
    }

    # 解密
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $b = $bytes[$i]

        if ((($b -band 0x0F) % 2) -eq 1) {
            $bytes[$i] = $b -bxor 0xA5
        }
        else {
            $bytes[$i] = $b -bxor 0xEF
        }
    }

    $text  = [System.Text.Encoding]::UTF8.GetString($bytes)
    $lines = [regex]::Split($text, '\r?\n')

    # 判断
    $greyMissing =
        $text -match 'JSON does not have\s+GrayBoxCSharpEnvironment\s+field'

    $greyDisabled =
        $text -match 'Sharphereal is disabled by grey request error'

    $greyStopped =
        $text -match 'Sharphereal tick stop by startup'

    $greyStarted =
        $text -match 'Sharphereal startTick'

    $positiveGreyField = $false

    foreach ($line in $lines) {
        if (
            $line -match 'GrayBoxCSharpEnvironment' -and
            $line -notmatch 'does not have\s+GrayBoxCSharpEnvironment'
        ) {
            $positiveGreyField = $true
            break
        }
    }

    $csharpRuntime =
        $text -match 'InitRuntimeEnvironment' -or
        $text -match 'mono_jit' -or
        $text -match 'CSharpScript\.dll' -or
        $text -match 'ScriptAssemblies[\\/].*\.dll' -or
        $text -match 'MonoEnvironment.*(Init|Start|Runtime)'

    # 原始依据
    $evidencePattern =
        'Kuro\.Script\.EnableCSharpEnv|' +
        'C#环境开关|' +
        'Sharphereal startTick|' +
        'GrayBoxCSharpEnvironment|' +
        'Sharphereal is disabled by grey request error|' +
        'Sharphereal tick stop by startup|' +
        'InitRuntimeEnvironment|' +
        'mono_jit|' +
        'MonoEnvironment|' +
        'CSharpScript\.dll|' +
        'ScriptAssemblies|' +
        'PuertsModule: Normal Mode started!|' +
        'V8ThreadHelper'

    $evidence = @(
        foreach ($line in $lines) {
            if ($line -match $evidencePattern) {
                $line.Trim()
            }
        }
    ) | Select-Object -Unique

    Write-Host ""
    Write-Host "=============== 原始判断依据 ===============" -ForegroundColor Cyan

    if ($evidence.Count -gt 0) {
        foreach ($line in ($evidence | Select-Object -First 40)) {
            Write-Host $line
        }

        if ($evidence.Count -gt 40) {
            Write-Host "... 共命中 $($evidence.Count) 条，仅显示前 40 条" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "未发现相关日志字段" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "================ 检测结论 ================="

    if ($greyMissing -or $greyDisabled) {

        Write-Host "未命中 C# 灰度" -ForegroundColor Red

        if ($greyMissing) {
            Write-Host "依据：GrayBoxCSharpEnvironment 字段未下发" -ForegroundColor Yellow
        }

        if ($greyDisabled) {
            Write-Host "依据：Sharphereal 被 grey request 明确禁用" -ForegroundColor Yellow
        }

        if ($greyStopped) {
            Write-Host "依据：Sharphereal 启动流程已停止" -ForegroundColor Yellow
        }

    } elseif ($csharpRuntime) {

        Write-Host "已命中 C# 灰度" -ForegroundColor Green
        Write-Host "依据：未发现灰度禁用结果，并检测到 C# Runtime 实际启动痕迹" -ForegroundColor Green

        if ($positiveGreyField) {
            Write-Host "依据：同时检测到有效 GrayBoxCSharpEnvironment 记录" -ForegroundColor Green
        }

    } elseif ($positiveGreyField -and $greyStarted) {

        Write-Host "疑似已命中 C# 灰度，但暂不能完全确认" -ForegroundColor Yellow
        Write-Host "依据：检测到 GrayBoxCSharpEnvironment，但未发现明确的 C# Runtime 启动日志" -ForegroundColor Yellow

    } elseif ($greyStarted) {

        Write-Host "暂时无法确定" -ForegroundColor Yellow
        Write-Host "Sharphereal 灰度检测已启动，但尚未看到明确结果"

    } else {

        Write-Host "暂时无法确定" -ForegroundColor Yellow
        Write-Host "日志中尚未出现 Sharphereal 灰度检测"
    }

    Write-Host "============================================"
    Write-Host ""
}
