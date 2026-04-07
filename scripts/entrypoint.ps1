param(
    [string]$sa_password    = $env:SA_PASSWORD,
    [string]$ACCEPT_EULA    = $env:ACCEPT_EULA,
    [string]$attach_dbs     = $env:attach_dbs,
    [string]$pbirs_user     = $env:pbirs_user,
    [string]$pbirs_password = $env:pbirs_password
)

# ── UI helpers ────────────────────────────────────────────────────────────────

function Write-Banner {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║     PBIRS Docker Container  v2026        ║" -ForegroundColor Magenta
    Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  User    " -NoNewline -ForegroundColor DarkGray
    Write-Host $pbirs_user -ForegroundColor White
    Write-Host "  SA pwd  " -NoNewline -ForegroundColor DarkGray
    Write-Host "****" -ForegroundColor White
    Write-Host "  Started " -NoNewline -ForegroundColor DarkGray
    Write-Host (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -ForegroundColor White
    Write-Host ""
}

function Write-Stage {
    param([int]$n, [int]$total, [string]$label)
    Write-Host "  ► Stage $n/$total" -NoNewline -ForegroundColor Cyan
    Write-Host " — $label" -ForegroundColor DarkGray
}

function Write-Ok {
    param([string]$msg, [string]$detail = "")
    Write-Host "  ✔ " -NoNewline -ForegroundColor Green
    Write-Host $msg -NoNewline -ForegroundColor Green
    if ($detail) { Write-Host "  $detail" -ForegroundColor DarkGray } else { Write-Host "" }
}

function Write-Warn {
    param([string]$msg)
    Write-Host "  ⚠ $msg" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$msg)
    Write-Host "  ✖ $msg" -ForegroundColor Red
}

function Write-Info {
    param([string]$label, [string]$value)
    Write-Host "  $label" -NoNewline -ForegroundColor DarkGray
    Write-Host $value -ForegroundColor Cyan
}

function Write-Separator {
    Write-Host "  ────────────────────────────────────────" -ForegroundColor DarkGray
}

function Write-Ready {
    Write-Host ""
    Write-Separator
    Write-Info "Reports  " "http://localhost/reports"
    Write-Info "API      " "http://localhost/reports/api/v2.0"
    Write-Info "SQL      " "localhost:1433"
    Write-Info "User     " $pbirs_user
    Write-Info "Password " $pbirs_password
    Write-Separator
    Write-Host ""
}

function Write-HealthLine {
    param([string]$elapsed, [hashtable]$services)
    $line = "  ♥ Health check"
    Write-Host $line -NoNewline -ForegroundColor DarkGray
    foreach ($name in $services.Keys) {
        $ok = $services[$name]
        Write-Host "  $name " -NoNewline -ForegroundColor DarkGray
        if ($ok) { Write-Host "✔" -NoNewline -ForegroundColor Green }
        else      { Write-Host "✖" -NoNewline -ForegroundColor Red   }
    }
    Write-Host "  ($elapsed)" -ForegroundColor DarkGray
}

# ── Main ──────────────────────────────────────────────────────────────────────

try {
    Write-Banner

    # Stage 1 - SQL Server
    Write-Stage 1 4 "SQL Server"
    C:/scripts/start-mssql.ps1 -sa_password $sa_password -ACCEPT_EULA $ACCEPT_EULA -attach_dbs \"$attach_dbs\"
    Write-Ok "SQL Server service started"

    $timeout = 60
    $elapsed = 0
    $connected = $false
    do {
        try {
            $conn = New-Object System.Data.SqlClient.SqlConnection(
                "Server=localhost;Database=master;User Id=sa;Password=$sa_password;TrustServerCertificate=true;Encrypt=false;"
            )
            $conn.Open()
            $conn.Close()
            $connected = $true
        } catch {
            Start-Sleep 5
            $elapsed += 5
            Write-Host "  … waiting for MSSQLSERVER ($elapsed s)" -ForegroundColor DarkGray
        }
    } while (-not $connected -and $elapsed -lt $timeout)

    if (-not $connected) { throw "SQL Server failed to start within ${timeout}s" }
    Write-Ok "Connection established" "localhost:1433"
    Write-Host ""

    # Stage 2 - PBIRS service
    Write-Stage 2 4 "PBIRS service"
    Start-Service PowerBIReportServer -ErrorAction SilentlyContinue
    Write-Ok "PowerBIReportServer started"
    Write-Host ""

    # Stage 3 - Configuration
    Write-Stage 3 4 "Configuration"
    C:/scripts/configure-pbirs.ps1
    Write-Ok "PBIRS configured"

    C:/scripts/configure-admin.ps1 -username $pbirs_user -password $pbirs_password
    Write-Ok "Admin account provisioned" $pbirs_user

    C:/scripts/restore-pbirs-key.ps1
    Write-Ok "Encryption key restored"
    Write-Host ""

    # Stage 4 - Health loop
    Write-Stage 4 4 "Health loop"
    Write-Ok "Container ready"
    Write-Ready

    $uptimeSeconds = 0
    while ($true) {
        Start-Sleep 30
        $uptimeSeconds += 30
        $uptime = if ($uptimeSeconds -ge 3600) {
            "{0}h {1}m" -f [math]::Floor($uptimeSeconds/3600), [math]::Floor(($uptimeSeconds%3600)/60)
        } else {
            "{0}m" -f [math]::Floor($uptimeSeconds/60)
        }

        $statuses = [ordered]@{}
        foreach ($svc in @("MSSQLSERVER", "PowerBIReportServer")) {
            $s = Get-Service $svc -ErrorAction SilentlyContinue
            $statuses[$svc] = ($s -and $s.Status -eq "Running")
            if (-not $statuses[$svc]) {
                Write-Warn "Service $svc is down, restarting..."
                try { Start-Service $svc -ErrorAction Stop }
                catch { Write-Fail "Could not restart $svc - $($_.Exception.Message)" }
            }
        }

        Write-HealthLine $uptime $statuses
    }
}
catch {
    Write-Host ""
    Write-Fail "Container startup failed: $($_.Exception.Message)"
    exit 1
}