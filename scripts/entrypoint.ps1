param(
    [string]$sa_password = $env:SA_PASSWORD,
    [string]$ACCEPT_EULA = $env:ACCEPT_EULA,
    [string]$attach_dbs = $env:attach_dbs,
    [string]$pbirs_user = $env:pbirs_user,
    [string]$pbirs_password = $env:pbirs_password
)

Write-Host "Starting PBIRS Docker Container..."
Write-Host "PBIRS User: $pbirs_user"


try {
    # Start SQL Server
    Write-Host "Starting SQL Server..."
    C:/scripts/start-mssql.ps1 -sa_password $sa_password -ACCEPT_EULA $ACCEPT_EULA -attach_dbs \"$attach_dbs\" -Verbose
    
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

    # Start PBIRS
    Write-Host "Starting PBIRS services..."
    Start-Service PowerBIReportServer

    # Configure PBIRS if not already configured
    C:/scripts/configure-pbirs.ps1 -Verbose

    C:/scripts/configure-admin.ps1 -username $pbirs_user -password $pbirs_password -Verbose

    Write-Host "PBIRS is ready!"
    Write-Host "Access PBIRS at: http://localhost/reports"
    Write-Host "Login with: $pbirs_user"

    # Keep container running
    while ($true) {
        Start-Sleep 30
        
        # Health check
        try {
            $services = @("MSSQLSERVER", "PowerBIReportServer")
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