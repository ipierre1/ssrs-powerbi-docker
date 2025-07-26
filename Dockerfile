# Escape directive pour Windows
# escape=`

FROM mcr.microsoft.com/mssql/server:2022-latest

# Metadata labels
LABEL maintainer="ipierre1" `
      org.opencontainers.image.title="SSRS PowerBI 2022 Docker" `
      org.opencontainers.image.description="SQL Server Reporting Services 2022 in Docker container" `
      org.opencontainers.image.source="https://github.com/ipierre1/ssrs-powerbi-docker" `
      org.opencontainers.image.licenses="MIT"

# Build arguments
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION

# Add build metadata
LABEL org.opencontainers.image.created=$BUILD_DATE `
      org.opencontainers.image.revision=$VCS_REF `
      org.opencontainers.image.version=$VERSION

# Environment variables pour SSRS
ENV ssrs_user=SSRSAdmin
ENV ssrs_password=DefaultPass123!

# Switch to root pour l'installation
USER root

# Install SSRS
RUN powershell -Command `
    # Download SSRS installer `
    $ProgressPreference = 'SilentlyContinue'; `
    Write-Host 'Downloading SSRS installer...'; `
    Invoke-WebRequest -Uri 'https://download.microsoft.com/download/8/3/2/832616ff-af64-42b5-a0b1-5eb07f71dec9/SQLServerReportingServices.exe' -OutFile 'C:\SQLServerReportingServices.exe'; `
    `
    # Install SSRS silently `
    Write-Host 'Installing SSRS...'; `
    Start-Process -FilePath 'C:\SQLServerReportingServices.exe' -ArgumentList '/quiet', '/norestart', '/IAcceptLicenseTerms', '/Edition=Dev' -Wait -PassThru -Verbose; `
    `
    # Clean up installer `
    Remove-Item -Path 'C:\SQLServerReportingServices.exe' -Force; `
    Write-Host 'SSRS installation completed.';

# Copy configuration scripts
COPY scripts/ C:/scripts/

# Make scripts executable and configure SSRS
RUN powershell -Command `
    # Set execution policy `
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force; `
    `
    # Configure SSRS service `
    Write-Host 'Configuring SSRS service...'; `
    C:/scripts/configure-ssrs.ps1;

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5m --retries=3 `
    CMD powershell -Command "try { Invoke-WebRequest -Uri 'http://localhost/reports' -UseBasicParsing -TimeoutSec 10 | Out-Null; exit 0 } catch { exit 1 }"

# Expose ports
EXPOSE 1433 80 443

# Set working directory
WORKDIR C:/

# Entry point
COPY scripts/entrypoint.ps1 C:/entrypoint.ps1
ENTRYPOINT ["powershell", "-File", "C:/entrypoint.ps1"]
