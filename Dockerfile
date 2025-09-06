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

RUN Write-Host 'Téléchargement des médias SQL Server (CAB)...'; \
    Start-Process -FilePath 'C:\temp\SQL2025-SSEI-Eval.exe' \
    -ArgumentList '/ACTION=Download', '/MEDIAPATH=C:\setup\sql', '/MEDIATYPE=CAB', '/QUIET' \
    -Wait -NoNewWindow; \
    Write-Host 'Vérification du téléchargement...'; \
    if (Test-Path 'C:\setup\sql') { \
        Write-Host 'Médias SQL Server téléchargés avec succès'; \
        Get-ChildItem -Path 'C:\setup\sql' -Recurse | Select-Object Name, Length, FullName | Format-Table; \
    } else { \
        Write-Error 'Échec du téléchargement des médias SQL Server'; \
        exit 1; \
    }

RUN Write-Host 'Extraction des fichiers .exe/.box et installation de SQL Server 2025...'; \
    Write-Host 'Contenu du dossier téléchargé:'; \
    Get-ChildItem -Path 'C:\setup\sql' -Recurse | Select-Object Name, Length, FullName | Format-Table; \
    # Recherche du fichier .exe principal \
    $exeFile = Get-ChildItem -Path 'C:\setup\sql' -Filter '*.exe' -Recurse | Where-Object { $_.Name -notlike '*SSEI*' } | Select-Object -First 1; \
    if ($exeFile) { \
        Write-Host "Fichier EXE trouvé: $($exeFile.Name)"; \
        # Le fichier .exe peut être soit un setup direct, soit un extracteur \
        # Tentons d'abord une extraction avec /x \
        Write-Host 'Tentative d extraction du fichier EXE...'; \
        Start-Process -FilePath $exeFile.FullName \
        -ArgumentList '/x:C:\setup\extracted', '/q' \
        -Wait -NoNewWindow -ErrorAction SilentlyContinue; \
        # Vérifie si l extraction a fonctionné \
        if (Test-Path 'C:\setup\extracted') { \
            Write-Host 'Extraction réussie, recherche de setup.exe...'; \
            $setupPath = Get-ChildItem -Path 'C:\setup\extracted' -Filter 'setup.exe' -Recurse | Select-Object -First 1; \
        } else { \
            Write-Host 'Pas d extraction possible, le fichier EXE est peut-être setup.exe directement'; \
            # Vérifie si le .exe est directement setup.exe \
            if ($exeFile.Name -eq 'setup.exe' -or $exeFile.Name -like '*setup*') { \
                $setupPath = $exeFile; \
            } else { \
                # Tentons une extraction différente \
                Write-Host 'Tentative d extraction avec paramètres différents...'; \
                New-Item -ItemType Directory -Force -Path 'C:\setup\extracted2'; \
                Start-Process -FilePath $exeFile.FullName \
                -ArgumentList '/extract:C:\setup\extracted2', '/quiet' \
                -Wait -NoNewWindow -ErrorAction SilentlyContinue; \
                $setupPath = Get-ChildItem -Path 'C:\setup\extracted2' -Filter 'setup.exe' -Recurse | Select-Object -First 1; \
            }; \
        }; \
        if ($setupPath) { \
            Write-Host "Setup trouvé: $($setupPath.FullName)"; \
            # Lance l'installation \
            Start-Process -FilePath $setupPath.FullName \
            -ArgumentList '/IACCEPTSQLSERVERLICENSETERMS', \
                         '/ACTION=install', \
                         '/FEATURES=SQLENGINE', \
                         '/INSTANCENAME=MSSQLSERVER', \
                         '/SQLSVCACCOUNT="NT AUTHORITY\NETWORK SERVICE"', \
                         '/SQLSYSADMINACCOUNTS="BUILTIN\ADMINISTRATORS"', \
                         '/AGTSVCACCOUNT="NT AUTHORITY\NETWORK SERVICE"', \
                         '/SQLSVCSTARTUPTYPE=Automatic', \
                         '/AGTSVCSTARTUPTYPE=Automatic', \
                         '/BROWSERSVCSTARTUPTYPE=Automatic', \
                         '/TCPENABLED=1', \
                         '/NPENABLED=0', \
                         '/UPDATEENABLED=0', \
                         '/QUIET', \
                         '/INDICATEPROGRESS' \
            -Wait -NoNewWindow; \
            Write-Host 'Installation SQL Server terminée'; \
        } else { \
            Write-Error 'Setup.exe non trouvé après tentatives d extraction'; \
            Write-Host 'Contenu après extraction:'; \
            Get-ChildItem -Path 'C:\setup' -Recurse | Select-Object Name, FullName; \
            exit 1; \
        }; \
    } else { \
        Write-Error 'Aucun fichier EXE trouvé dans les médias téléchargés'; \
        exit 1; \
    }

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
