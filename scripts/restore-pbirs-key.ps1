function Get-ConfigSet() {
    return Get-WmiObject -namespace "root\Microsoft\SqlServer\ReportServer\RS_PBIRS\v15\Admin" -class MSReportServer_ConfigurationSetting -ComputerName localhost
}

# Allow importing of sqlps module
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force

# Retrieve the current configuration
$configset = Get-ConfigSet

$KeyPath = (Resolve-Path "C:\scripts\pbirs.key").ProviderPath

Write-Verbose "Checking if key file path is valid..."
if (-not (Test-Path $KeyPath))
{
    throw "No key was found at the specified location: $path"
}

try
{
    $keyBytes = [System.IO.File]::ReadAllBytes($KeyPath)
}
catch
{
    throw
}

Write-Verbose "Restoring encryption key..."
$restoreKeyResult = $configset.RestoreEncryptionKey($keyBytes, $keyBytes.Length, "DefaultPass123!")

if ($restoreKeyResult.HRESULT -eq 0)
{
    Write-Verbose "Success!"
}
else
{
    throw "Failed to restore the encryption key! Errors: $($restoreKeyResult.ExtendedErrors)"
}

Restart-Service PowerBIReportServer -ErrorAction SilentlyContinue
