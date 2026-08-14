param(
    [int]$Port = 8788
)

$ErrorActionPreference = 'Stop'
$gatewayRoot = Split-Path -Parent $PSScriptRoot
$stateRoot = Join-Path $gatewayRoot '.wrangler\local-relay'
$secretPath = Join-Path $stateRoot 'relay-secret.dpapi'
$relayPidPath = Join-Path $stateRoot 'relay.pid'
$tunnelPidPath = Join-Path $stateRoot 'tunnel.pid'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$relayOut = Join-Path $stateRoot "relay-$timestamp.out.log"
$relayErr = Join-Path $stateRoot "relay-$timestamp.err.log"
$tunnelOut = Join-Path $stateRoot "tunnel-$timestamp.out.log"
$tunnelErr = Join-Path $stateRoot "tunnel-$timestamp.err.log"

New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

function Stop-RecordedProcess {
    param(
        [string]$PidPath,
        [string[]]$AllowedNames
    )
    if (-not (Test-Path -LiteralPath $PidPath)) {
        return
    }
    $recordedPid = Get-Content -LiteralPath $PidPath -Raw
    if ($recordedPid -notmatch '^\d+\s*$') {
        throw "Invalid local relay PID state: $PidPath"
    }
    $process = Get-Process -Id ([int]$recordedPid.Trim()) -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        return
    }
    if ($AllowedNames -notcontains $process.ProcessName) {
        throw "Refusing to stop unexpected process $($process.ProcessName)."
    }
    Stop-Process -Id $process.Id
}

Stop-RecordedProcess -PidPath $relayPidPath -AllowedNames @('node')
Stop-RecordedProcess -PidPath $tunnelPidPath -AllowedNames @('cloudflared')

if (-not (Test-Path -LiteralPath $secretPath)) {
    $secretBytes = New-Object byte[] 48
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($secretBytes)
    $rng.Dispose()
    $plainSecret = [Convert]::ToBase64String($secretBytes)
    $secureSecret = ConvertTo-SecureString $plainSecret -AsPlainText -Force
    $secureSecret | ConvertFrom-SecureString | Set-Content -LiteralPath $secretPath
    $plainSecret = $null
}

$encryptedSecret = (Get-Content -LiteralPath $secretPath -Raw).Trim()
$secureSecret = ConvertTo-SecureString $encryptedSecret
$secretPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureSecret)
try {
    $relaySecret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretPointer)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer)
}

Push-Location $gatewayRoot
try {
    $relaySecret | pnpm.cmd wrangler secret put RELAY_SHARED_SECRET
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to configure RELAY_SHARED_SECRET.'
    }

    $env:RELAY_SHARED_SECRET = $relaySecret
    $env:RELAY_PORT = $Port.ToString()
    $relayProcess = Start-Process `
        -FilePath 'C:\Program Files\nodejs\node.exe' `
        -ArgumentList 'local-relay/server.mjs' `
        -WorkingDirectory $gatewayRoot `
        -WindowStyle Hidden `
        -RedirectStandardOutput $relayOut `
        -RedirectStandardError $relayErr `
        -PassThru
    Remove-Item Env:RELAY_SHARED_SECRET
    Remove-Item Env:RELAY_PORT
    $relaySecret = $null
    Set-Content -LiteralPath $relayPidPath -Value $relayProcess.Id

    $relayReady = $false
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        Start-Sleep -Milliseconds 250
        $status = curl.exe -sS -o NUL -w '%{http_code}' --max-time 2 "http://127.0.0.1:$Port/health"
        if ($status -eq '200') {
            $relayReady = $true
            break
        }
    }
    if (-not $relayReady) {
        throw 'Local relay did not become healthy.'
    }

    $existingTunnelPids = @(
        Get-Process -Name cloudflared -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Id
    )
    $tunnelCommand = "pnpm.cmd wrangler tunnel quick-start http://127.0.0.1:$Port --log-level info"
    $tunnelWrapper = Start-Process `
        -FilePath 'C:\Windows\System32\cmd.exe' `
        -ArgumentList @('/d', '/c', $tunnelCommand) `
        -WorkingDirectory $gatewayRoot `
        -WindowStyle Hidden `
        -RedirectStandardOutput $tunnelOut `
        -RedirectStandardError $tunnelErr `
        -PassThru

    $tunnelUrl = $null
    $cloudflaredPid = $null
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        Start-Sleep -Milliseconds 500
        $newTunnelProcess = Get-Process -Name cloudflared -ErrorAction SilentlyContinue |
            Where-Object { $existingTunnelPids -notcontains $_.Id } |
            Select-Object -First 1
        if ($null -ne $newTunnelProcess) {
            $cloudflaredPid = $newTunnelProcess.Id
        }
        $combinedLog = ''
        if (Test-Path -LiteralPath $tunnelOut) {
            $combinedLog += Get-Content -LiteralPath $tunnelOut -Raw
        }
        if (Test-Path -LiteralPath $tunnelErr) {
            $combinedLog += Get-Content -LiteralPath $tunnelErr -Raw
        }
        $match = [regex]::Match(
            $combinedLog,
            'https://[a-z0-9-]+\.trycloudflare\.com',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if ($match.Success) {
            $tunnelUrl = $match.Value
            break
        }
        if ($tunnelWrapper.HasExited) {
            throw 'Cloudflare Tunnel exited before producing a URL.'
        }
    }
    if ($null -eq $tunnelUrl -or $null -eq $cloudflaredPid) {
        throw 'Cloudflare Tunnel did not become ready.'
    }
    Set-Content -LiteralPath $tunnelPidPath -Value $cloudflaredPid

    $tunnelHealthy = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        $tunnelStatus = curl.exe -sS -o NUL -w '%{http_code}' --max-time 5 "$tunnelUrl/health"
        if ($tunnelStatus -eq '200') {
            $tunnelHealthy = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    if (-not $tunnelHealthy) {
        throw 'Cloudflare Tunnel health check failed.'
    }

    $tunnelUrl | pnpm.cmd wrangler secret put HIPSTER_RELAY_URL
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to configure HIPSTER_RELAY_URL.'
    }
    pnpm.cmd wrangler deploy
    if ($LASTEXITCODE -ne 0) {
        throw 'Worker deployment failed.'
    }

    Write-Output 'local_relay=running'
    Write-Output 'relay_health=200'
    Write-Output 'tunnel_health=200'
    Write-Output "tunnel_url=$tunnelUrl"
} finally {
    $relaySecret = $null
    Pop-Location
}
