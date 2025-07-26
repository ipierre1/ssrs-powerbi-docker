param(
    [string]$SSRSUser = $env:ssrs_user,
    [string]$SSRSPassword = $env:ssrs_password
)

Write-Host "Configuring SSRS with user: $SSRSUser"

try {
    # Import SSRS PowerShell module
    Import-Module "C:\Program Files\Microsoft SQL Server Reporting Services\SSRS\PowerShell\SqlServerReportingServices" -Force

    # Get SSRS configuration
    $rsConfig = Get-RsConfigConnection -ComputerName localhost

    if ($rsConfig) {
        Write-Host "SSRS configuration connection established"
        
        # Configure database connection
        Set-RsDatabaseConnection -ReportServerInstance $rsConfig -DatabaseServerName "localhost" -DatabaseName "ReportServer" -Username "sa" -Password $env:sa_password

        # Initialize report server
        Initialize-Rs -ReportServerInstance $rsConfig

        # Set service account
        Set-RsServiceAccount -ReportServerInstance $rsConfig -ServiceAccount "NetworkService"

        # Configure URLs
        Set-RsUrlReservation -ReportServerInstance $rsConfig -Application "ReportServerWebService" -VirtualDirectory "reportserver" -Url "http://+:80"
        Set-RsUrlReservation -ReportServerInstance $rsConfig -Application "ReportManager" -VirtualDirectory "reports" -Url "http://+:80"

        # Create SSRS admin user
        if ($SSRSUser -and $SSRSPassword) {
            # Add user to system administrators
            Grant-RsSystemRole -Identity $SSRSUser -RoleName "System Administrator"
            Write-Host "SSRS admin user configured: $SSRSUser"
        }

        Write-Host "SSRS configuration completed successfully"
    }
    else {
        throw "Could not establish SSRS configuration connection"
    }
}
catch {
    Write-Error "SSRS configuration failed: $($_.Exception.Message)"
    throw
}