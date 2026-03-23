# Run as Administrator

Write-Host "Resetting Windows Time Service..." -ForegroundColor Cyan

net stop w32time
w32tm /unregister
w32tm /register
net start w32time

# Use proper NTP flags (this is the part most scripts miss)
$ntpServers = "0.pool.ntp.org,0x8 1.pool.ntp.org,0x8 time.windows.com,0x8"

Write-Host "Configuring external NTP peers..." -ForegroundColor Yellow

w32tm /config /manualpeerlist:$ntpServers /syncfromflags:manual /reliable:yes /update

# Force rediscovery + sync
w32tm /config /update
w32tm /resync /rediscover /force

Start-Sleep -Seconds 5

Write-Host "`n=== TIME SOURCE ===" -ForegroundColor Green
w32tm /query /source

Write-Host "`n=== STATUS ===" -ForegroundColor Green
w32tm /query /status
