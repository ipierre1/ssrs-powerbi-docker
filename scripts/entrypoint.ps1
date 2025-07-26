param(
    [string]$sa_password = $env:sa_password,
    [string]$ACCEPT_EULA = $env:ACCEPT_EULA,
    [string]$ssrs_user = $env:ssrs_user,
    [string]$ssrs_password = $env:ssrs_password
)

Write-Host "Starting SSRS Docker Container..."
Write-Host "SSRS User: $ssrs_user"

# Validate required environment variables
if (-not $sa_password) {
    Write-Error "sa_password environment variable is required"
    exit 1
}

if ($ACCEPT_EULA -ne "Y") {
    Write-Error "ACCEPT_EULA must be set to Y"
    exit 1
}

try {
    # Start SQL Server
    Write-Host "Starting SQL Server..."
    Start-Service MSSQLSERVER
    
    # Wait for SQL Server to be ready
    $timeout = 60
    $elapsed = 0
    do {
        try {
            $connection = New-Object System.Data.SqlClient.SqlConnection("Server=localhost;Database=master;User Id=sa;Password=$sa_password;")
            $connection.Open()
            $connection.Close()
            Write-Host "SQL Server is ready"
            break
        }
        catch {
            Start-Sleep 5
            $elapsed += 5
            Write-Host "Waiting for SQL Server... ($elapsed seconds)"
        }
    } while ($elapsed -lt $timeout)

    if ($elapsed -ge $timeout) {
        throw "SQL Server failed to start within timeout"
    }

    # Start SSRS
    Write-Host "Starting SSRS services..."
    Start-Service SQLServerReportingServices
    Start-Service ReportServer

    # Configure SSRS if not already configured
    $configPath = "C:\Program Files\Microsoft SQL Server Reporting Services\SSRS\ReportServer\rsreportserver.config"
    if (-not (Test-Path $configPath)) {
        Write-Host "Configuring SSRS for first time..."
        & C:\scripts\configure-ssrs.ps1 -SSRSUser $ssrs_user -SSRSPassword $ssrs_password
    }

    Write-Host "SSRS is ready!"
    Write-Host "Access SSRS at: http://localhost/reports"
    Write-Host "Login with: $ssrs_user"

    # Keep container running
    while ($true) {
        Start-Sleep 30
        
        # Health check
        try {
            $services = @("MSSQLSERVER", "SQLServerReportingServices")
            foreach ($service in $services) {
                $svc = Get-Service $service -ErrorAction SilentlyContinue
                if (-not $svc -or $svc.Status -ne "Running") {
                    Write-Warning "Service $service is not running, attempting to restart..."
                    Start-Service $service
                }
            }
        }
        catch {
            Write-Warning "Health check failed: $($_.Exception.Message)"
        }
    }
}
catch {
    Write-Error "Container startup failed: $($_.Exception.Message)"
    exit 1
}