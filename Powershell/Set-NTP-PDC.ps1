# Run as Administrator

Write-Host "Configuring this server as authoritative NTP source (PDC)..." -ForegroundColor Cyan

# Set your NTP servers here
$ntpServers = "0.pool.ntp.org 1.pool.ntp.org time.windows.com"

# Configure Windows Time Service
w32tm /config /manualpeerlist:$ntpServers /syncfromflags:manual /reliable:yes /update

# Restart service
Write-Host "Restarting Windows Time Service..." -ForegroundColor Yellow
Stop-Service w32time -Force
Start-Service w32time

# Force resync
Write-Host "Forcing time sync..." -ForegroundColor Yellow
w32tm /resync /force

# Output status
Write-Host "`n=== TIME STATUS ===" -ForegroundColor Green
w32tm /query /status

Write-Host "`n=== TIME SOURCE ===" -ForegroundColor Green
w32tm /query /source