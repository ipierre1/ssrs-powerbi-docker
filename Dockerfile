# Escape directive pour Windows
# escape=\

FROM mcr.microsoft.com/windows/servercore:ltsc2022

# Metadata labels
LABEL maintainer="ipierre1" \
      org.opencontainers.image.title="PBIRS PowerBI 2022 Docker" \
      org.opencontainers.image.description="SQL Server Reporting Services 2022 in Docker container" \
      org.opencontainers.image.source="https://github.com/ipierre1/ssrs-powerbi-docker" \
      org.opencontainers.image.licenses="MIT"

# Build arguments
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION

# Add build metadata
LABEL org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.revision=$VCS_REF \
      org.opencontainers.image.version=$VERSION

# Environment variables pour PBIRS
ENV pbirs_user=pbirsAdmin
ENV pbirs_password=DefaultPass123!

# Définit les variables d'environnement
ENV SA_PASSWORD="YourStrong@Passw0rd" \
    attach_dbs="[]" \
    ACCEPT_EULA="Y" \
    MSSQL_PID="Evaluation"

# Configure PowerShell comme shell par défaut
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# Installe les outils nécessaires
# RUN Set-ExecutionPolicy Bypass -Scope Process -Force; \
#     [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; \
#     iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1')); \
#     choco install -y 7zip

# Crée les répertoires de travail
RUN New-Item -ItemType Directory -Force -Path C:\temp, C:\setup

# Télécharge SQL Server 2025 Evaluation
RUN Write-Host 'Téléchargement de SQL Server 2025...'; \
    Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?linkid=2314611&clcid=0x409&culture=en-us&country=us' \
    -OutFile 'C:\temp\SQL2025-SSEI-Eval.exe' -UseBasicParsing; \
    Write-Host 'Téléchargement terminé'

# Télécharge les média SQL Server complets
RUN Write-Host 'Extraction des médias et installation SQL Server...'; \
    Start-Process -FilePath 'C:\temp\SQL2025-SSEI-Eval.exe' \
    -ArgumentList '/ACTION=Install', \
                  '/INSTANCENAME=MSSQLSERVER', \
                  '/MEDIAPATH=C:\setup\sql', \
                  '/QUIET', \
                  '/ENU', \
                  '/IAcceptSQLServerLicenseTerms', \
                  '/Language=en-US' \
                #   '/FEATURES=SQLEngine', \
                  '/SQLSVCACCOUNT="NT AUTHORITY\System"', \
                  '/SQLSYSADMINACCOUNTS="BUILTIN\ADMINISTRATORS"', \
    -Wait -NoNewWindow; \
    Write-Host 'Installation SQL Server terminée'

# Configure SQL Server
RUN Write-Host 'Configuration de SQL Server...'; \
    # Démarre le service SQL Server si ce n'est pas fait
    Start-Service -Name 'MSSQLSERVER' \
    # Start-Service -Name 'MSSQLSERVER' -ErrorAction SilentlyContinue; \
    # Configure le port TCP
    Import-Module SqlServer -ErrorAction SilentlyContinue; \
    Write-Host 'SQL Server configuré'

# Télécharge Power BI Report Server 2025
RUN Write-Host 'Téléchargement de Power BI Report Server 2025...'; \
    Invoke-WebRequest -Uri 'https://aka.ms/pbireportserverexe' \
    -OutFile 'C:\temp\PowerBIReportServer.exe' -UseBasicParsing; \
    Write-Host 'Téléchargement terminé'

# Installe Power BI Report Server
RUN Write-Host 'Installation de Power BI Report Server 2025...'; \
    Start-Process -FilePath 'C:\temp\PowerBIReportServer.exe' \
    -ArgumentList '/QUIET', \
                  '/IACCEPTLICENSETERMS', \
                  '/EDITION=Dev', \
                  '/INSTANCENAME=PBIRS', \
                  '/INSTALLPATH="C:\Program Files\Microsoft Power BI Report Server"', \
                  '/DATABASESERVERNAME=localhost', \
                  '/DATABASENAME=ReportServer', \
                  '/RSINSTALLMODE=DefaultNativeMode' \
    -Wait -NoNewWindow; \
    Write-Host 'Installation Power BI Report Server terminée'

# Nettoie les fichiers temporaires
RUN Remove-Item -Path C:\temp -Recurse -Force; \
    Remove-Item -Path C:\setup -Recurse -Force

# Copy configuration scripts
COPY scripts/ C:/scripts/

# Make scripts executable and configure PBIRS
RUN powershell -Command \
    # Set execution policy \
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force; \
    \
    # Configure PBIRS service \
    Write-Host 'Configuring PBIRS service...'; \
    C:/scripts/entrypoint.ps1;

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5m --retries=3 \
    CMD powershell -Command "try { Invoke-WebRequest -Uri 'http://localhost/reports' -UseBasicParsing -TimeoutSec 10 | Out-Null; exit 0 } catch { exit 1 }"

# Expose ports
EXPOSE 1433 80 443

# Set working directory
WORKDIR C:/

# Entry point
COPY scripts/entrypoint.ps1 C:/entrypoint.ps1
ENTRYPOINT ["powershell", "-File", "C:/entrypoint.ps1"]
