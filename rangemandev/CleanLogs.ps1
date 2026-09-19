<# Powershell Script for clearing out exchange logs. Best to run this via scheduled tasks once a week to prevent exchange from filling up.
    WRITTEN BY: Chip McElvain
    VERSION HISTORY: version 2 - Dynamic path discovery
    CREDIT:  This script is mostly derived from two sources
        - https://gallery.technet.microsoft.com/office/Clear-Exchange-2013-Log-71abba44#content
        - https://ephams.com/2018/09/powershell-how-to-delete-exchange-transation-logs/

    TO BE EXECUTED ON: Windows Server running Exchange 2019, 2016, 2013, or 2010

   NOTE: If you get "Not Digitally Signed" ERROR.
   Then open the script in Powershell ISE, then make a simple edit and save it.

   PRE-REQs: N/A - Script auto-discovers all Exchange log paths
#>

USER SET VARIABLES SECTION ####
$days = 0
$Verbose = $true
END USER VARIABLE EDIT SECTION ####

Load Exchange SnapIn
try {
    Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn -ErrorAction Stop
    Write-Host "Exchange SnapIn loaded successfully" -ForegroundColor Green
}
catch {
    Write-Host "Failed to load Exchange SnapIn: $_" -ForegroundColor Red
    exit 1
}

CleanLogfiles function START
Function CleanLogfiles($TargetFolder, $Extensions = @(".log", ".blg", ".etl")) {
    if (Test-Path $TargetFolder) {
        $Now = Get-Date
        $LastWrite = $Now.AddDays(-$days)
        $Files = Get-ChildItem $TargetFolder -Recurse -ErrorAction SilentlyContinue |
                 Where-Object { $.Extension -in $Extensions -and $.LastWriteTime -le $LastWrite }

        foreach ($File in $Files) {
            $FullFileName = $File.FullName
            if ($Verbose) { Write-Host "Deleting file $FullFileName" -ForegroundColor "Yellow" }
            Remove-Item $FullFileName -ErrorAction SilentlyContinue | Out-Null
        }
        Write-Host "Cleaned $($Files.Count) files from $TargetFolder" -ForegroundColor Green
    }
    Else {
        Write-Host "The folder $TargetFolder doesn't exist!" -ForegroundColor Red
    }
}
CleanLogfiles function END

CleanTransactionLogs function START
function CleanTransactionLogs {
    $dbs = Get-MailboxDatabase -Status
    foreach ($db in $dbs) {
        if ($db.LogFolderPath -eq $null) { continue }

        $logPath = $db.LogFolderPath
        $logPrefix = $db.LogFilePrefix
        $chkFile = "$logPath\$logPrefix.chk"

        if (-not (Test-Path $chkFile)) {
            Write-Host "Checkpoint file not found for $($db.Name)" -ForegroundColor Yellow
            continue
        }

        $checkpointFind = eseutil /mk $chkFile | Select-String 'Checkpoint:'
        if ($checkpointFind -ne $null) {
            $checkpoint = $checkpointFind[1].ToString().Split(',')[0].Split('x')[1]
            $zeros = "0" * (8 - $checkpoint.Length)
            $chkFilename = $logPrefix + $zeros + $checkpoint + ".log"
            $chkFileObj = Get-ChildItem -Path $logPath -Filter $chkFilename -ErrorAction SilentlyContinue

            if ($chkFileObj) {
                $info = "Last checkpoint for $($db.Name): $($chkFileObj.Name) (written: $($chkFileObj.LastWriteTime))"
                Write-Host $info -ForegroundColor Cyan

                $files = Get-ChildItem -Path $logPath -Filter "*.log" |
                        Where-Object { $.Name -ne "$logPrefix.log" -and $.Name -notlike "tmp" -and $_.LastWriteTime -lt $chkFileObj.LastWriteTime }

                foreach ($File in $files) {
                    if ($Verbose) { Write-Host "Deleting file $($File.FullName)" -ForegroundColor "Yellow" }
                    Remove-Item $File.FullName -ErrorAction SilentlyContinue | Out-Null
                }
                Write-Host "Completed clearing $($files.Count) committed Transaction Logs for $($db.Name)" -ForegroundColor Green
            }
        }
    }
}
CleanTransactionLogs function END

Discover Exchange Installation Paths
Write-Host "=== Discovering Exchange Log Paths ===" -ForegroundColor Cyan
Write-Host ""

$exchangePaths = @{}

Get Exchange Server object
$exchangeServer = Get-ExchangeServer | Where-Object { $_.Name -eq $env:COMPUTERNAME }

if ($exchangeServer) {
    # Get Exchange Install Directory
    $exchangeInstallDir = $exchangeServer.InstallDirectory
    Write-Host "Exchange Install Directory: $exchangeInstallDir" -ForegroundColor Green

    # Standard Exchange logging paths (constructed from install directory)
    $exchangePaths['ExchangeLogging'] = Join-Path $exchangeInstallDir "Logging"

    # ETL/Ceres logging paths (varies by version)
    $exchangePaths['ETLLogging'] = Join-Path $exchangeInstallDir "Bin\Search\Ceres\Diagnostics\Logs"

    # Transport service logs
    $exchangePaths['TransportLogging'] = Join-Path $exchangeInstallDir "TransportRoles\Logs"

    # IIS logs (standard location)
    $exchangePaths['IISLogs'] = "C:\inetpub\logs\LogFiles"
}
else {
    Write-Host "Could not determine local Exchange server" -ForegroundColor Yellow
}

Get Mailbox Database paths (transaction logs)
$dbs = Get-MailboxDatabase -Status
foreach ($db in $dbs) {
    Write-Host "Database: $($db.Name)" -ForegroundColor Cyan
    if ($db.LogFolderPath) {
        Write-Host "  Transaction Log Path: $($db.LogFolderPath)" -ForegroundColor Green
        $exchangePaths["DB_$($db.Name)"] = $db.LogFolderPath
    }
    if ($db.EdbFilePath) {
        $edbDir = Split-Path $db.EdbFilePath -Parent
        Write-Host "  Database File Path: $edbDir" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "=== Starting Log Cleanup ===" -ForegroundColor Cyan
Write-Host ""

Execution Section
CleanLogfiles($exchangePaths['IISLogs'])
CleanLogfiles($exchangePaths['ExchangeLogging'])
CleanLogfiles($exchangePaths['ETLLogging'])
CleanLogfiles($exchangePaths['TransportLogging'])
CleanTransactionLogs

Write-Host ""
Write-Host "=== Exchange Log Cleanup Complete ===" -ForegroundColor Green