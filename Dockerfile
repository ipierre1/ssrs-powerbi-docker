# escape=`

FROM mcr.microsoft.com/windows/servercore:ltsc2022

LABEL maintainer="ipierre1" `
      org.opencontainers.image.title="PBIRS PowerBI 2025 Docker" `
      org.opencontainers.image.description="Power BI Reporting Services 2025 in Docker container" `
      org.opencontainers.image.source="https://github.com/ipierre1/ssrs-powerbi-docker" `
      org.opencontainers.image.licenses="MIT"

ARG BUILD_DATE
ARG VCS_REF
ARG VERSION

LABEL org.opencontainers.image.created=$BUILD_DATE `
      org.opencontainers.image.revision=$VCS_REF `
      org.opencontainers.image.version=$VERSION

ENV pbirs_user=pbirsAdmin `
    pbirs_password=DefaultPass123! `
    SA_PASSWORD="YourStrong@Passw0rd" `
    ACCEPT_EULA="Y" `
    MSSQL_PID="Developer"

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

COPY scripts/ C:/scripts/

# Set execution policy once
RUN Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force; `
    Write-Host 'Configuring admin accounts...'; `
    C:/scripts/configure-admin.ps1 -username $env:pbirs_user -password $env:pbirs_password -Verbose

# SQL Server - download, install, and clean in ONE layer
RUN Write-Host 'Creating directories...'; `
    New-Item -ItemType Directory -Force -Path C:\temp, C:\setup | Out-Null; `
    `
    Write-Host 'Downloading SQL Server 2025...'; `
    Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?linkid=2314611&clcid=0x409&culture=en-us&country=us' `
        -OutFile 'C:\temp\SQL2025-SSEI-Eval.exe' -UseBasicParsing; `
    `
    Write-Host 'Downloading SQL Server media (CAB)...'; `
    Start-Process -FilePath 'C:\temp\SQL2025-SSEI-Eval.exe' `
        -ArgumentList '/ACTION=Download', '/MEDIAPATH=C:\setup\sql', '/MEDIATYPE=CAB', '/QUIET' `
        -Wait -NoNewWindow; `
    `
    Write-Host 'Locating setup.exe...'; `
    $exeFile = Get-ChildItem -Path 'C:\setup\sql' -Filter '*.exe' -Recurse | `
        Where-Object { $_.Name -notlike '*SSEI*' } | Select-Object -First 1; `
    if (-not $exeFile) { throw 'No EXE found in downloaded media' }; `
    `
    Write-Host "Found: $($exeFile.Name) - attempting extraction..."; `
    Start-Process -FilePath $exeFile.FullName -ArgumentList '/x:C:\setup\extracted', '/q' `
        -Wait -NoNewWindow -ErrorAction SilentlyContinue; `
    `
    $setupPath = $null; `
    if (Test-Path 'C:\setup\extracted') { `
        $setupPath = Get-ChildItem -Path 'C:\setup\extracted' -Filter 'setup.exe' -Recurse | Select-Object -First 1; `
    }; `
    if (-not $setupPath) { `
        if ($exeFile.Name -like '*setup*') { `
            $setupPath = $exeFile; `
        } else { `
            New-Item -ItemType Directory -Force -Path 'C:\setup\extracted2' | Out-Null; `
            Start-Process -FilePath $exeFile.FullName -ArgumentList '/extract:C:\setup\extracted2', '/quiet' `
                -Wait -NoNewWindow -ErrorAction SilentlyContinue; `
            $setupPath = Get-ChildItem -Path 'C:\setup\extracted2' -Filter 'setup.exe' -Recurse | Select-Object -First 1; `
        }; `
    }; `
    if (-not $setupPath) { throw 'setup.exe not found after extraction attempts' }; `
    `
    Write-Host "Installing SQL Server from: $($setupPath.FullName)"; `
    Start-Process -FilePath $setupPath.FullName `
        -ArgumentList '/IACCEPTSQLSERVERLICENSETERMS', '/ACTION=install', '/FEATURES=SQLENGINE', `
                      '/INSTANCENAME=MSSQLSERVER', '/SAPWD=YourStrong@Passw0rd', `
                      '/SQLSYSADMINACCOUNTS=BUILTIN\Administrators', `
                      '/SQLSVCSTARTUPTYPE=Automatic', '/AGTSVCSTARTUPTYPE=Automatic', `
                      '/BROWSERSVCSTARTUPTYPE=Automatic', '/TCPENABLED=1', '/NPENABLED=0', `
                      '/UPDATEENABLED=0', '/SECURITYMODE=SQL', '/QUIET' `
        -Wait -NoNewWindow; `
    `
    Write-Host 'SQL Server installation done - cleaning up...'; `
    Remove-Item -Path C:\temp -Recurse -Force -ErrorAction SilentlyContinue; `
    Remove-Item -Path C:\setup -Recurse -Force -ErrorAction SilentlyContinue; `
    Write-Host 'SQL Server layer complete'

RUN Write-Host 'Configuration de SQL Server...'; `
    Start-Service -Name 'MSSQLSERVER' -ErrorAction SilentlyContinue; `
    $timeout = 60; `
    $elapsed = 0; `
    do { `
        Start-Sleep -Seconds 5; `
        $elapsed += 5; `
        $service = Get-Service -Name 'MSSQLSERVER' -ErrorAction SilentlyContinue; `
    } while ($service.Status -ne 'Running' -and $elapsed -lt $timeout); `
    if ($service.Status -eq 'Running') { `
        Write-Host 'SQL Server démarré avec succès'; `
    } else { `
        Write-Warning 'SQL Server pas encore démarré, continuons...'; `
    }

# PBIRS - download, install, and clean in ONE layer
RUN Write-Host 'Downloading Power BI Report Server 2025...'; `
    New-Item -ItemType Directory -Force -Path C:\temp | Out-Null; `
    Invoke-WebRequest -Uri 'https://aka.ms/pbireportserverexe' `
        -OutFile 'C:\temp\PowerBIReportServer.exe' -UseBasicParsing; `
    
    Write-Host 'Téléchargement terminé' `
    `
    Write-Host 'Installing Power BI Report Server...'; `
    Start-Process -FilePath 'C:\temp\PowerBIReportServer.exe' `
        -ArgumentList '/quiet', '/norestart', '/IAcceptLicenseTerms', '/Edition=Dev' `
        -Wait -NoNewWindow; `
    `
    Write-Host 'PBIRS installation done - cleaning up...'; `
    Remove-Item -Path C:\temp -Recurse -Force -ErrorAction SilentlyContinue; `
    Write-Host 'PBIRS layer complete'

# Configure PBIRS
RUN Write-Host 'Configuring PBIRS service...'; `
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force; `
    C:/scripts/install.ps1

HEALTHCHECK --interval=30s --timeout=10s --start-period=5m --retries=3 `
    CMD powershell -Command "try { Invoke-WebRequest -Uri 'http://localhost/reports' -UseBasicParsing -TimeoutSec 10 | Out-Null; exit 0 } catch { exit 1 }"

EXPOSE 1433 80 443

WORKDIR C:/

COPY scripts/entrypoint.ps1 C:/entrypoint.ps1
ENTRYPOINT ["powershell", "-File", "C:/entrypoint.ps1"]
