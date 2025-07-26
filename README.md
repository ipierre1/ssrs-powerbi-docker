# SSRS-Docker

[![Build and Publish](https://github.com/ipierre1/ssrs-powerbi-docker/actions/workflows/docker-build.yml/badge.svg)](https://github.com/ipierre1/ssrs-powerbi-docker/actions/workflows/docker-build.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/ipierre1/ssrs-powerbi)](https://hub.docker.com/r/ipierre1/ssrs-powerbi)
[![GitHub release](https://img.shields.io/github/release/ipierre1/ssrs-powerbi-docker)](https://github.com/ipierre1/ssrs-powerbi-docker/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

SQL Server Reporting Services (SSRS) Power BI 2022 containerized for development and testing environments.

> ⚠️ **Important**: This container is designed for development and testing purposes only. It is **NOT recommended for production use**.

## 🏗️ Project History and Credits

This project is a modernized fork that builds upon the excellent work of previous contributors:

### Original Work
- **Original Repository**: [Microsoft/mssql-docker](https://github.com/Microsoft/mssql-docker/tree/master/windows/mssql-server-windows-developer) - Microsoft's official SQL Server Docker images
- **SSRS Implementation**: [SaViGnAnO/SSRS-Docker](https://github.com/SaViGnAnO/SSRS-Docker) - Initial SSRS containerization by [@SaViGnAnO](https://github.com/SaViGnAnO)

## Quick Start

### Pull and Run
```bash
docker pull yourusername/ssrs:latest

docker run -d \
  --name ssrs-dev \
  -p 1433:1433 \
  -p 80:80 \
  -e ACCEPT_EULA=Y \
  -e sa_password="YourStrong@Password123" \
  -e ssrs_user="SSRSAdmin" \
  -e ssrs_password="Admin@Password123" \
  --memory 6048mb \
  yourusername/ssrs:latest
```

### Access SSRS
- **Report Manager**: http://localhost/reports
- **Web Service**: http://localhost/reportserver
- **SQL Server**: localhost:1433

**Default Login**: Use the credentials specified in `ssrs_user` and `ssrs_password` environment variables.

## Requirements

### System Requirements
- **OS**: Windows containers support (Windows 10/11 or Windows Server)
- **Memory**: Minimum 6GB RAM allocated to Docker
- **Storage**: ~8GB available disk space
- **Docker**: Docker Desktop with Windows containers enabled

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ACCEPT_EULA` | ✅ Yes | - | Must be set to `Y` to accept SQL Server EULA |
| `sa_password` | ✅ Yes | - | SQL Server SA password (must meet complexity requirements) |
| `ssrs_user` | ❌ No | `SSRSAdmin` | SSRS administrator username |
| `ssrs_password` | ❌ No | `DefaultPass123!` | SSRS administrator password |

### Password Requirements
- Minimum 8 characters
- Must contain uppercase, lowercase, numbers, and special characters
- Cannot contain the username

## Configuration

### Docker Compose Example
```yaml
version: '3.8'

services:
  ssrs:
    image: yourusername/ssrs:latest
    container_name: ssrs-dev
    ports:
      - "1433:1433"
      - "80:80"
    environment:
      - ACCEPT_EULA=Y
      - sa_password="YourStrong@Password123"
      - ssrs_user=SSRSAdmin
      - ssrs_password="Admin@Password123"
    deploy:
      resources:
        limits:
          memory: 6G
    volumes:
      - ssrs_data:/var/opt/mssql
      - reports_temp:/temp
    restart: unless-stopped

volumes:
  ssrs_data:
  reports_temp:
```

### Custom Configuration
To use custom SSRS configurations, mount your configuration files:

```bash
docker run -d \
  --name ssrs-custom \
  -p 1433:1433 -p 80:80 \
  -v /path/to/custom/rsreportserver.config:/Program Files/Microsoft SQL Server Reporting Services/SSRS/ReportServer/rsreportserver.config \
  -e ACCEPT_EULA=Y \
  -e sa_password="YourPassword" \
  yourusername/ssrs:latest
```

## API Testing and Development

### SSRS Web Service Endpoints
The container exposes standard SSRS SOAP endpoints:

- **ReportService2010**: `http://localhost/reportserver/ReportService2010.asmx?WSDL`
- **ReportExecution2005**: `http://localhost/reportserver/ReportExecution2005.asmx?WSDL`
- **ReportService2006**: `http://localhost/reportserver/ReportService2006.asmx?WSDL`

### PowerShell Example
```powershell
# Install SSRS PowerShell module
Install-Module -Name ReportingServicesTools

# Connect to SSRS
$credential = Get-Credential # Use your ssrs_user credentials
$proxy = New-WebServiceProxy -Uri "http://localhost/reportserver/ReportService2010.asmx?WSDL" -Credential $credential

# List reports
$reports = $proxy.ListChildren("/", $true)
$reports | Where-Object { $_.TypeName -eq "Report" }
```

### REST API Testing
```bash
# Test basic connectivity
curl -u "SSRSAdmin:Admin@Password123" \
  -H "Content-Type: application/json" \
  http://localhost/reports/api/v2.0/folders

# Get report list
curl -u "SSRSAdmin:Admin@Password123" \
  http://localhost/reports/api/v2.0/reports
```

## Development Usage

### For API Discovery and Mocking
This container is perfect for:
- **API Discovery**: Explore SSRS endpoints for integration projects
- **Mock Development**: Generate OpenAPI specifications from real SSRS responses
- **Testing**: Validate report generation and deployment workflows
- **CI/CD Integration**: Automated testing of SSRS-dependent applications

### Integration with Testing Frameworks
```dockerfile
# Use in your test Dockerfile
FROM yourusername/ssrs:latest AS ssrs-test

# Copy test reports
COPY test-reports/ /test-reports/

# Your test application
FROM node:16 AS test-runner
# ... your test setup
```

## Available Images and Tags

### DockerHub Repository
All images are available at: [`yourusername/ssrs`](https://hub.docker.com/r/ipierre/ssrs-powerbi)

### Tag Strategy
- `latest` - Latest stable build from main branch
- `v1.0.0`, `v1.1.0` - Semantic version releases
- `main-YYYYMMDD-<sha>` - Development builds with date and commit
- `pr-123` - Pull request builds for testing

### Image Information
- **Base Image**: `mcr.microsoft.com/mssql/server:2022-latest`
- **SSRS Version**: SQL Server Reporting Services 2022
- **Platform**: `windows/amd64`
- **Size**: ~8GB (includes full SQL Server + SSRS)

## 🔍 Monitoring and Health Checks

### Built-in Health Check
The container includes automatic health monitoring:
```bash
# Check container health
docker inspect --format='{{.State.Health.Status}}' ssrs-dev

# View health check logs
docker inspect --format='{{range .State.Health.Log}}{{.Output}}{{end}}' ssrs-dev
```

### Manual Health Verification
```bash
# Test SQL Server connection
docker exec ssrs-dev powershell "Invoke-Sqlcmd -Query 'SELECT @@VERSION' -ServerInstance localhost -Username sa -Password 'YourPassword'"

# Test SSRS web interface
docker exec ssrs-dev powershell "Invoke-WebRequest -Uri 'http://localhost/reports' -UseBasicParsing"
```

## Troubleshooting

### Common Issues

#### Container Won't Start
```bash
# Check Docker resources
docker system df
docker system prune  # Clean up if needed

# Verify memory allocation (should be >= 6GB)
docker info | grep -i memory
```

#### SSRS Not Accessible
```bash
# Check service status inside container
docker exec ssrs-dev powershell "Get-Service | Where-Object {$_.Name -like '*Report*' -or $_.Name -like '*SQL*'}"

# View container logs
docker logs ssrs-dev --tail 50

# Interactive troubleshooting
docker exec -it ssrs-dev powershell
```

#### Database Connection Issues
```bash
# Test SA password
docker exec ssrs-dev powershell "sqlcmd -S localhost -U sa -P 'YourPassword' -Q 'SELECT 1'"

# Check SQL error logs
docker exec ssrs-dev powershell "Get-Content 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\Log\ERRORLOG'"
```

### Performance Optimization
```bash
# Increase memory if needed
docker update --memory 8g ssrs-dev

# Monitor resource usage
docker stats ssrs-dev
```

## Building from Source

### Prerequisites
- Windows machine with Docker Desktop
- Git for cloning the repository

### Build Process
```bash
# Clone this repository
git clone https://github.com/yourusername/SSRS-Docker.git
cd SSRS-Docker

# Build the image
docker build -t ssrs-local .

# Run your custom build
docker run -d \
  --name ssrs-local-test \
  -p 1433:1433 -p 80:80 \
  -e ACCEPT_EULA=Y \
  -e sa_password="YourPassword" \
  ssrs-local
```

### Custom Builds
To modify the container:
1. Edit `Dockerfile` for base image changes
2. Modify `scripts/configure-ssrs.ps1` for SSRS configuration
3. Update `scripts/entrypoint.ps1` for startup behavior

## Security Considerations

### For Development Use Only
- **Never use in production** - This container uses evaluation licenses
- **Default passwords** - Always change default credentials
- **Network exposure** - Be careful about port exposure in production networks

### Security Features
- **Vulnerability scanning** with Trivy on every build
- **SBOM generation** for supply chain transparency  
- **Health monitoring** to detect service issues
- **No hardcoded secrets** in the image

### Best Practices
```bash
# Use strong passwords
export SA_PASSWORD="$(openssl rand -base64 32)"
export SSRS_PASSWORD="$(openssl rand -base64 32)"

# Limit network exposure
docker run -p 127.0.0.1:1433:1433 -p 127.0.0.1:80:80 ...

# Use Docker secrets in production-like environments
echo "$SA_PASSWORD" | docker secret create sa_password -
```

## Contributing

We welcome contributions! This project builds on the foundation laid by [@SaViGnAnO](https://github.com/SaViGnAnO) and aims to keep the SSRS Docker community thriving.

### How to Contribute
1. **Fork** this repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Areas for Contribution
- 🐛 Bug fixes and stability improvements
- 📚 Documentation enhancements
- 🧪 Additional test scenarios
- 🔧 Configuration options
- 🚀 Performance optimizations
- 🔒 Security improvements

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Third-Party Licenses
- **Microsoft SQL Server**: Subject to Microsoft licensing terms
- **Original SSRS-Docker**: MIT License by [@SaViGnAnO](https://github.com/SaViGnAnO)

### Community
- **Original Project**: [SaViGnAnO/SSRS-Docker](https://github.com/SaViGnAnO/SSRS-Docker)
- **Microsoft Docs**: [SQL Server in containers](https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-docker-container-deployment)
- **SSRS Documentation**: [Microsoft SSRS Docs](https://docs.microsoft.com/en-us/sql/reporting-services/)
