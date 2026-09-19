<# Powershell Script for removing all emails from Exchange.
    WRITTEN BY: Chip McElvain
    VERSION HISTORY: Version 3 - Fully automated, no manual steps

    TO BE EXECUTED ON: Windows Server running Exchange 2019, 2016, or 2013

    PRE-REQs: Exchange admin rights and Domain Admin
#>

USER VARIABLE EDIT SECTION ####
$AutoRun = $true  # Set to $false to be prompted before each step
$Verbose = $true
END USER VARIABLE EDIT SECTION ####

Check admin rights
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Insufficient permissions. Open PowerShell as Administrator and run again."
    exit 1
}

Load Exchange module
try {
    Add-Module ExchangeManagement -ErrorAction Stop
}
catch {
    try {
        Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn -ErrorAction Stop
    }
    catch {
        Write-Host "Failed to load Exchange module: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host "=== Exchange Email Deletion Script ===" -ForegroundColor Cyan
Write-Host ""

#######################################
STEP 1: DELETE ALL EMAILS
#######################################

if ($AutoRun -or (Read-Host "Continue to Step 1 (delete all emails)? [Y/N]") -eq "Y") {
    Write-Host "Step 1: Deleting all emails from all mailboxes..." -ForegroundColor Yellow
    Get-Mailbox | Search-Mailbox -DeleteContent -Force -Confirm:$false
    Write-Host "Email deletion complete." -ForegroundColor Green
}
else {
    Write-Host "Step 1 cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""

#######################################
STEP 2: PURGE AND DEFRAG DATABASE
#######################################

if ($AutoRun -or (Read-Host "Continue to Step 2 (defrag database)? [Y/N]") -eq "Y") {

    # Get database info
    $db = Get-MailboxDatabase
    $dbName = $db.Name
    $edbPath = $db.EdbFilePath
    $logDrive = $db.LogFolderPath.Split(':')[0]

    Write-Host "Database: $dbName" -ForegroundColor Cyan
    Write-Host "EDB Path: $edbPath" -ForegroundColor Cyan
    Write-Host "Log Drive: $logDrive" -ForegroundColor Cyan
    Write-Host ""

    # ========== AUTOMATED DISKSHADOW ==========
    Write-Host "Creating shadow copy (fake backup)..." -ForegroundColor Yellow

    # Create DiskShadow script
    $diskShadowScript = @"
set context persistent nowriters
add volume=$logDrive name=vol1
begin backup
create
end backup
delete volumes vol1
"@
    $scriptPath = "$env:TEMP\diskshadow_$dbName.txt"
    Set-Content -Path $scriptPath -Value $diskShadowScript -Force

    # Run DiskShadow silently
    $null = & diskshadow /s "$scriptPath" 2>&1 | Out-Null

    # Cleanup
    Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue

    Write-Host "Shadow copy created successfully." -ForegroundColor Green
    Write-Host ""

    # ========== DISMOUNT DATABASE ==========
    Write-Host "Dismounting database: $dbName" -ForegroundColor Yellow
    Dismount-Database $dbName -Confirm:$false

    # Wait for dismount
    $maxWait = 30
    $counter = 0
    while ((Get-MailboxDatabase $dbName).Mounted -eq $true -and $counter -lt $maxWait) {
        Start-Sleep -Seconds 1
        $counter++
    }

    if ((Get-MailboxDatabase $dbName).Mounted) {
        Write-Host "Database failed to dismount." -ForegroundColor Red
        exit 1
    }
    Write-Host "Database dismounted." -ForegroundColor Green

    # ========== DEFRAG DATABASE ==========
    Write-Host "Defragging database... (this may take several minutes)" -ForegroundColor Yellow
    $null = & eseutil /d $edbPath 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Database defragmentation complete." -ForegroundColor Green
    }
    else {
        Write-Host "Defrag completed with exit code: $LASTEXITCODE" -ForegroundColor Yellow
    }

    # ========== MOUNT DATABASE ==========
    Write-Host "Mounting database: $dbName" -ForegroundColor Yellow
    Mount-Database $dbName -Confirm:$false

    # Wait for mount
    $maxWait = 60
    $counter = 0
    while ((Get-MailboxDatabase $dbName).Mounted -eq $false -and $counter -lt $maxWait) {
        Start-Sleep -Seconds 2
        $counter++
    }

    if (-not (Get-MailboxDatabase $dbName).Mounted) {
        Write-Host "Database failed to mount." -ForegroundColor Red
        exit 1
    }
    Write-Host "Database mounted successfully." -ForegroundColor Green

    # Show final size
    $finalSize = (Get-Item $edbPath).Length / 1GB
    Write-Host ""
    Write-Host "=== Final Database Size: $([math]::Round($finalSize, 2)) GB ===" -ForegroundColor Cyan
}
else {
    Write-Host "Step 2 cancelled." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Exchange Email Deletion Complete ===" -ForegroundColor Green