```powershell
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Cleans all user mailbox email, performs an Exchange-aware VSS backup,
    offline-defragments each mailbox database, and remounts the databases.

.DESCRIPTION
    Designed for an on-premises Exchange Server cyber-range environment.

    Process:
        1. Delete all email from all user mailboxes
        2. Clear Recoverable Items
        3. Perform an Exchange-aware VSS backup
        4. Dismount each mailbox database
        5. Run ESEUTIL /D
        6. Mount each mailbox database
        7. Report database size before/after

    Exchange installation path, database names, EDB paths, and database
    locations are discovered dynamically.

.NOTES
    Run from the Exchange Management Shell as Administrator.

    IMPORTANT:
    $BackupTarget must be a separate volume/path with sufficient capacity
    for the backup. Do NOT point it at the Exchange database volume.

    ESEUTIL /D is an offline operation. Each database will be unavailable
    while it is being compacted.
#>

# ============================================================
# CONFIGURATION
# ============================================================

# Backup destination.
#
# IMPORTANT:
# This should be a separate volume or backup destination.
#
# Example:
#   E:\ExchangeRangeBackup
#
$BackupTarget = "E:\ExchangeRangeBackup"

# Set to $true if you want the script to actually run ESEUTIL /D.
$DefragDatabases = $true

# Number of messages deleted per EWS batch.
$BatchSize = 500


# ============================================================
# INITIAL VALIDATION
# ============================================================

Write-Host ""
Write-Host "============================================================" `
    -ForegroundColor Cyan

Write-Host "       EXCHANGE CYBER RANGE RESET" `
    -ForegroundColor Cyan

Write-Host "============================================================" `
    -ForegroundColor Cyan

Write-Host ""

if (-not $env:ExchangeInstallPath) {

    Write-Host "ERROR: ExchangeInstallPath environment variable not found." `
        -ForegroundColor Red

    exit 1
}

$ExchangePath = $env:ExchangeInstallPath

Write-Host "Exchange installation path:" -ForegroundColor Gray
Write-Host "  $ExchangePath" -ForegroundColor White

# Locate ESEUTIL dynamically
$Eseutil = Join-Path $ExchangePath "Bin\eseutil.exe"

if (-not (Test-Path $Eseutil)) {

    Write-Host ""
    Write-Host "ERROR: ESEUTIL not found:" -ForegroundColor Red
    Write-Host "  $Eseutil" -ForegroundColor Red

    exit 1
}

Write-Host "ESEUTIL:" -ForegroundColor Gray
Write-Host "  $Eseutil" -ForegroundColor White


# ============================================================
# LOAD EWS
# ============================================================

$EwsDll = Join-Path `
    $ExchangePath `
    "Bin\Microsoft.Exchange.WebServices.dll"

if (-not (Test-Path $EwsDll)) {

    Write-Host ""
    Write-Host "ERROR: EWS Managed API not found:" -ForegroundColor Red
    Write-Host "  $EwsDll" -ForegroundColor Red

    exit 1
}

Add-Type -Path $EwsDll


# ============================================================
# GET EXCHANGE DATABASES
# ============================================================

$Databases = @(Get-MailboxDatabase -Status)

if ($Databases.Count -eq 0) {

    Write-Host ""
    Write-Host "ERROR: No mailbox databases were found." `
        -ForegroundColor Red

    exit 1
}

Write-Host ""
Write-Host "Mailbox databases discovered:" -ForegroundColor Yellow

foreach ($Database in $Databases) {

    Write-Host ""
    Write-Host "  Database : $($Database.Name)" `
        -ForegroundColor White

    Write-Host "  EDB      : $($Database.EdbFilePath.PathName)" `
        -ForegroundColor Gray

    Write-Host "  Mounted  : $($Database.Mounted)" `
        -ForegroundColor Gray
}


# ============================================================
# GET EWS SERVICE
# ============================================================

function New-EwsService {

    $Service = New-Object `
        Microsoft.Exchange.WebServices.Data.ExchangeService(
            [Microsoft.Exchange.WebServices.Data.ExchangeVersion]::Exchange2016
        )

    # Running directly on Exchange under a domain account.
    $Service.UseDefaultCredentials = $true

    # Let EWS discover the correct endpoint.
    #
    # We intentionally do NOT hard-code:
    #   https://server/EWS/Exchange.asmx
    #
    return $Service
}


# ============================================================
# AUTODISCOVER EWS URL
# ============================================================

function Set-EwsAutodiscover {

    param(
        [Parameter(Mandatory)]
        $Service,

        [Parameter(Mandatory)]
        [string]$SmtpAddress
    )

    try {

        $Service.AutodiscoverUrl(
            $SmtpAddress,
            {
                param($RedirectionUrl)

                return $RedirectionUrl.StartsWith(
                    "https://",
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            }
        )

        return $true

    }
    catch {

        Write-Host ""
        Write-Host "EWS Autodiscover failed for $SmtpAddress" `
            -ForegroundColor Red

        Write-Host $_.Exception.Message -ForegroundColor Red

        return $false
    }
}


# ============================================================
# DELETE ITEMS FROM A FOLDER
# ============================================================

function Remove-EwsFolderItems {

    param(
        [Parameter(Mandatory)]
        $Service,

        [Parameter(Mandatory)]
        $FolderId,

        [Parameter(Mandatory)]
        [string]$FolderName
    )

    $Deleted = 0

    do {

        $View = New-Object `
            Microsoft.Exchange.WebServices.Data.ItemView($BatchSize)

        $View.PropertySet = New-Object `
            Microsoft.Exchange.WebServices.Data.PropertySet(
                [Microsoft.Exchange.WebServices.Data.BasePropertySet]::IdOnly
            )

        try {

            $Results = $Service.FindItems(
                $FolderId,
                $View
            )
        }
        catch {

            Write-Host "      ERROR reading $FolderName" `
                -ForegroundColor Red

            Write-Host "      $($_.Exception.Message)" `
                -ForegroundColor Red

            break
        }

        if ($Results.Items.Count -eq 0) {
            break
        }

        $Ids = New-Object `
            System.Collections.Generic.List[
                Microsoft.Exchange.WebServices.Data.ItemId
            ]

        foreach ($Item in $Results.Items) {
            $Ids.Add($Item.Id)
        }

        try {

            $Responses = $Service.DeleteItems(
                $Ids,
                [Microsoft.Exchange.WebServices.Data.DeleteMode]::HardDelete,
                $null,
                $null
            )

            $Deleted += $Ids.Count

            Write-Host `
                "      $FolderName : $($Ids.Count) deleted" `
                -ForegroundColor DarkGray

        }
        catch {

            Write-Host `
                "      ERROR deleting from $FolderName" `
                -ForegroundColor Red

            Write-Host `
                "      $($_.Exception.Message)" `
                -ForegroundColor Red

            break
        }

    } while ($Results.MoreAvailable)

    return $Deleted
}


# ============================================================
# GET ALL MAIL FOLDERS
# ============================================================

function Get-EwsMailFolders {

    param(
        [Parameter(Mandatory)]
        $Service
    )

    $RootId = New-Object `
        Microsoft.Exchange.WebServices.Data.FolderId(
            [Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::MsgFolderRoot
        )

    $View = New-Object `
        Microsoft.Exchange.WebServices.Data.FolderView(1000)

    $View.Traversal =
        [Microsoft.Exchange.WebServices.Data.FolderTraversal]::Deep

    $View.PropertySet = New-Object `
        Microsoft.Exchange.WebServices.Data.PropertySet(
            [Microsoft.Exchange.WebServices.Data.BasePropertySet]::IdOnly
        )

    $View.PropertySet.Add(
        [Microsoft.Exchange.WebServices.Data.FolderSchema]::DisplayName
    )

    $View.PropertySet.Add(
        [Microsoft.Exchange.WebServices.Data.FolderSchema]::FolderClass
    )

    try {

        $Results = $Service.FindFolders(
            $RootId,
            $View
        )

        return @(
            $Results.Folders | Where-Object {
                $_.FolderClass -like "IPF.Note*"
            }
        )

    }
    catch {

        Write-Host "    ERROR enumerating mailbox folders:" `
            -ForegroundColor Red

        Write-Host $_.Exception.Message `
            -ForegroundColor Red

        return @()
    }
}


# ============================================================
# DELETE MAIL FROM ALL USER MAILBOXES
# ============================================================

Write-Host ""
Write-Host "============================================================" `
    -ForegroundColor Cyan

Write-Host "STEP 1: DELETE ALL MAILBOX EMAIL" `
    -ForegroundColor Yellow

Write-Host "============================================================" `
    -ForegroundColor Cyan

Write-Host ""

$Mailboxes = @(
    Get-Mailbox -ResultSize Unlimited |
    Where-Object {
        $_.RecipientTypeDetails -eq "UserMailbox"
    }
)

Write-Host "User mailboxes found: $($Mailboxes.Count)" `
    -ForegroundColor White

$TotalDeleted = 0
$MailboxNumber = 0

foreach ($Mailbox in $Mailboxes) {

    $MailboxNumber++

    $Smtp = $Mailbox.PrimarySmtpAddress.ToString()

    Write-Host ""
    Write-Host "[$MailboxNumber/$($Mailboxes.Count)] $Smtp" `
        -ForegroundColor Yellow

    $Service = New-EwsService

    if (-not (Set-EwsAutodiscover `
        -Service $Service `
        -SmtpAddress $Smtp)) {

        Write-Host "    Skipping mailbox." `
            -ForegroundColor Red

        continue
    }

    $Service.ImpersonatedUserId =
        New-Object `
        Microsoft.Exchange.WebServices.Data.ImpersonatedUserId(
            [Microsoft.Exchange.WebServices.Data.ConnectingIdType]::SmtpAddress,
            $Smtp
        )

    $Folders = Get-EwsMailFolders -Service $Service

    Write-Host "    Mail folders: $($Folders.Count)" `
        -ForegroundColor DarkGray

    $MailboxDeleted = 0

    foreach ($Folder in $Folders) {

        $Count = Remove-EwsFolderItems `
            -Service $Service `
            -FolderId $Folder.Id `
            -FolderName $Folder.DisplayName

        $MailboxDeleted += $Count
    }

    $TotalDeleted += $MailboxDeleted

    Write-Host ""
    Write-Host "    Mailbox total: $MailboxDeleted items" `
        -ForegroundColor Green
}

Write-Host ""
Write-Host "Total normal mailbox items deleted: $TotalDeleted" `
    -ForegroundColor Green


# ============================================================
# STEP 2 - CLEAR RECOVERABLE ITEMS
# ============================================================

Write-Host ""
Write-Host "============================================================" `
    -ForegroundColor Cyan

Write-Host "STEP 2: CLEAR RECOVERABLE ITEMS" `
    -ForegroundColor Yellow

Write-Host "============================================================" `
    -ForegroundColor Cyan

Write-Host ""

$RecoverableDeleted = 0

foreach ($Mailbox in $Mailboxes) {

    $Smtp = $Mailbox.PrimarySmtpAddress.ToString()

    Write-Host "Cleaning Recoverable Items: $Smtp" `
        -ForegroundColor Yellow

    try {

        # Exchange Management Shell provides the mailbox-aware
        # Recoverable Items interface.

        $Items = @(
            Get-RecoverableItems `
                -Identity $Mailbox.Identity `
                -ResultSize Unlimited
        )

        if ($Items.Count -eq 0) {

            Write-Host "    Nothing found." `
                -ForegroundColor DarkGray

            continue
        }

        Write-Host "    Found $($Items.Count) recoverable items." `
            -ForegroundColor DarkGray

        # Delete each recoverable item by EntryId.
        #
        # This intentionally uses Exchange's own cmdlets rather
        # than trying to guess the internal Recoverable Items
        # folder structure.

        foreach ($Item in $Items) {

            try {

                Remove-RecoverableItems `
                    -Identity $Mailbox.Identity `
                    -EntryID $Item.EntryID `
                    -Confirm:$false

                $RecoverableDeleted++
            }
            catch {

                Write-Host `
                    "    Could not delete EntryID $($Item.EntryID)" `
                    -ForegroundColor DarkYellow
            }
        }

    }
    catch {

        Write-Host `
            "    Recoverable Items cleanup failed:" `
            -ForegroundColor Red

        Write-Host `
            "    $($_.Exception.Message)" `
            -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Recoverable Items deleted: $RecoverableDeleted" `
    -ForegroundColor Green


# ============================================================
# STEP 3 - EXCHANGE-AWARE VSS BACKUP
# ============================================================

Write-Host ""
Write-Host "============================================================" `
    -ForegroundColor Cyan

Write-Host "STEP 3: EXCHANGE-AWARE VSS BACKUP" `
    -ForegroundColor Yellow

Write-Host "============================================================" `
    -ForegroundColor Cyan

Write-Host ""

Write-Host "Backup target:" -ForegroundColor Gray
Write-Host "  $BackupTarget" -ForegroundColor White

if (-not (Test-Path $BackupTarget)) {

    Write-Host ""
    Write-Host "Backup target does not exist." `
        -ForegroundColor Yellow

    Write-Host "Creating it..." -ForegroundColor Yellow

    New-Item `
        -ItemType Directory `
        -Path $BackupTarget `
        -Force | Out-Null
}

# Determine all volumes containing Exchange databases.
$DatabaseVolumes = @(
    $Databases |
    ForEach-Object {
        Split-Path $_.EdbFilePath.PathName -Qualifier
    } |
    Sort-Object -Unique
)

Write-Host ""
Write-Host "Database volumes:" -ForegroundColor Gray

$DatabaseVolumes | ForEach-Object {
    Write-Host "  $_"
}

Write-Host ""
Write-Host "Starting Windows Server Backup..." `
    -ForegroundColor Yellow

# Build volume include list.
$IncludeVolumes = ($DatabaseVolumes -join ",")

#
# IMPORTANT:
#
# wbadmin performs an actual VSS backup and therefore invokes
# the Exchange VSS writer rather than simply making an arbitrary
# shadow copy.
#

$WbadminArguments = @(
    "start"
    "backup"
    "-backupTarget:$BackupTarget"
    "-include:$IncludeVolumes"
    "-vssFull"
    "-quiet"
)

Write-Host ""
Write-Host "Running:" -ForegroundColor DarkGray
Write-Host "wbadmin $($WbadminArguments -join ' ')" `
    -ForegroundColor DarkGray

& wbadmin @WbadminArguments

$WbadminExitCode = $LASTEXITCODE

if ($WbadminExitCode -ne 0) {

    Write-Host ""
    Write-Host "VSS BACKUP FAILED." -ForegroundColor Red

    Write-Host "Exit code: $WbadminExitCode" `
        -ForegroundColor Red

    Write-Host ""
    Write-Host "Databases will NOT be defragmented." `
        -ForegroundColor Red

    exit 1
}

Write-Host ""
Write-Host "VSS BACKUP COMPLETED SUCCESSFULLY." `
    -ForegroundColor Green


# ============================================================
# STEP 4 / 5 / 6 - DEFRAG EACH DATABASE
# ============================================================

if (-not $DefragDatabases) {

    Write-Host ""
    Write-Host "Database defragmentation disabled." `
        -ForegroundColor Yellow

    Write-Host ""
    Write-Host "Cleanup complete." `
        -ForegroundColor Green

    exit 0
}

Write-Host ""
Write-Host "============================================================" `
    -ForegroundColor Cyan

Write-Host "STEP 4-6: DISMOUNT / ESEUTIL / MOUNT" `
    -ForegroundColor Yellow

Write-Host "============================================================" `
    -ForegroundColor Cyan

Write-Host ""

foreach ($Database in $Databases) {

    $DatabaseName = $Database.Name
    $EdbPath = $Database.EdbFilePath.PathName

    Write-Host ""
    Write-Host "------------------------------------------------------------" `
        -ForegroundColor DarkGray

    Write-Host "Database: $DatabaseName" `
        -ForegroundColor Yellow

    Write-Host "EDB:      $EdbPath" `
        -ForegroundColor Gray

    if (-not (Test-Path $EdbPath)) {

        Write-Host ""
        Write-Host "EDB file not found. SKIPPING." `
            -ForegroundColor Red

        continue
    }

    # --------------------------------------------------------
    # BEFORE SIZE
    # --------------------------------------------------------

    $BeforeBytes = (Get-Item $EdbPath).Length
    $BeforeGB = [math]::Round(
        $BeforeBytes / 1GB,
        2
    )

    Write-Host "Before:   $BeforeGB GB" `
        -ForegroundColor White

    # --------------------------------------------------------
    # CHECK FREE SPACE
    # --------------------------------------------------------

    $DatabaseDrive = Split-Path `
        $EdbPath `
        -Qualifier

    $Disk = Get-CimInstance Win32_LogicalDisk `
        -Filter "DeviceID='$DatabaseDrive'"

    $FreeGB = [math]::Round(
        $Disk.FreeSpace / 1GB,
        2
    )

    Write-Host "Free:     $FreeGB GB" `
        -ForegroundColor White

    #
    # ESEUTIL /D requires significant temporary workspace.
    # Use a conservative check here.
    #

    if ($Disk.FreeSpace -lt $BeforeBytes) {

        Write-Host ""
        Write-Host "INSUFFICIENT FREE SPACE." `
            -ForegroundColor Red

        Write-Host "Skipping database." `
            -ForegroundColor Red

        continue
    }

    # --------------------------------------------------------
    # STEP 4 - DISMOUNT
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Dismounting $DatabaseName..." `
        -ForegroundColor Yellow

    try {

        Dismount-Database `
            -Identity $DatabaseName `
            -Confirm:$false `
            -ErrorAction Stop

    }
    catch {

        Write-Host ""
        Write-Host "Dismount FAILED." `
            -ForegroundColor Red

        Write-Host $_.Exception.Message `
            -ForegroundColor Red

        continue
    }

    # Verify dismount
    $Status = Get-MailboxDatabase `
        -Identity $DatabaseName `
        -Status

    if ($Status.Mounted) {

        Write-Host ""
        Write-Host "Database is STILL MOUNTED." `
            -ForegroundColor Red

        Write-Host "ESEUTIL will NOT be run." `
            -ForegroundColor Red

        continue
    }

    # --------------------------------------------------------
    # STEP 5 - ESEUTIL /D
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Running ESEUTIL /D..." `
        -ForegroundColor Yellow

    Write-Host "This may take a significant amount of time." `
        -ForegroundColor DarkYellow

    Write-Host ""

    & $Eseutil /d $EdbPath

    $EseutilExitCode = $LASTEXITCODE

    Write-Host ""
    Write-Host "ESEUTIL exit code: $EseutilExitCode" `
        -ForegroundColor White

    # --------------------------------------------------------
    # STEP 6 - MOUNT
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Mounting $DatabaseName..." `
        -ForegroundColor Yellow

    try {

        Mount-Database `
            -Identity $DatabaseName `
            -Confirm:$false `
            -ErrorAction Stop

    }
    catch {

        Write-Host ""
        Write-Host "MOUNT FAILED." `
            -ForegroundColor Red

        Write-Host $_.Exception.Message `
            -ForegroundColor Red

        continue
    }

    # --------------------------------------------------------
    # VERIFY MOUNT
    # --------------------------------------------------------

    Start-Sleep -Seconds 5

    $Status = Get-MailboxDatabase `
        -Identity $DatabaseName `
        -Status

    if (-not $Status.Mounted) {

        Write-Host ""
        Write-Host "WARNING: Database did not mount." `
            -ForegroundColor Red

        continue
    }

    # --------------------------------------------------------
    # AFTER SIZE
    # --------------------------------------------------------

    $AfterBytes = (Get-Item $EdbPath).Length

    $AfterGB = [math]::Round(
        $AfterBytes / 1GB,
        2
    )

    $SavedGB = [math]::Round(
        ($BeforeBytes - $AfterBytes) / 1GB,
        2
    )

    Write-Host ""
    Write-Host "Database successfully mounted." `
        -ForegroundColor Green

    Write-Host "Before: $BeforeGB GB"
    Write-Host "After:  $AfterGB GB"

    if ($SavedGB -gt 0) {

        Write-Host "Saved:  $SavedGB GB" `
            -ForegroundColor Green
    }
    else {

        Write-Host "Saved:  $SavedGB GB" `
            -ForegroundColor Yellow
    }
}


# ============================================================
# FINAL STATUS
# ============================================================

Write-Host ""
Write-Host "============================================================" `
    -ForegroundColor Cyan

Write-Host "EXCHANGE CYBER RANGE RESET COMPLETE" `
    -ForegroundColor Green

Write-Host "============================================================" `
    -ForegroundColor Cyan

Write-Host ""
Write-Host "Mail items deleted       : $TotalDeleted"
Write-Host "Recoverable items deleted: $RecoverableDeleted"
Write-Host "Databases processed      : $($Databases.Count)"
Write-Host ""

Write-Host "Final database status:" `
    -ForegroundColor Yellow

Get-MailboxDatabase -Status |
    Select-Object Name, Mounted, EdbFilePath |
    Format-Table -AutoSize

Write-Host ""
Write-Host "============================================================" `
    -ForegroundColor Cyan
```

### Two things I'd change before you run this

There are two pieces here where I **don't want you to blindly run my first version**, because they have important Exchange-specific implications.

**1. The VSS backup target needs to be real.**

`wbadmin` isn't just creating a throwaway shadow copy; it is performing a VSS backup and involving the Exchange VSS writer. That's much closer to what you're describing than `vssadmin create shadow`. VSS is specifically designed to create consistent Exchange backups while Exchange is running.

So if your Exchange server has, for example:

```text
C:  OS
D:  Exchange databases
E:  Exchange backup
```

you could use:

```powershell
$BackupTarget = "E:\ExchangeRangeBackup"
```

But **the backup target cannot be the same volume you're backing up**.

**2. I'd actually reconsider clearing Recoverable Items with EWS.**

Microsoft explicitly warns that Recoverable Items cleanup has different behavior when **Single Item Recovery, Litigation Hold, or In-Place Hold** is enabled. Since this is your disposable range, that's probably something you deliberately want to override, but I don't want the script silently giving you a false impression that *all* retained data has disappeared.

Also, EWS supports hard deletion and Microsoft documents `DeleteItems` for batch deletion, which is why we're using that rather than your original `Search-Mailbox` approach.

### The database discovery portion is exactly the way I'd do it

The important part is:

```powershell
$Databases = @(Get-MailboxDatabase -Status)

$DatabaseName = $Database.Name

$EdbPath = $Database.EdbFilePath.PathName

$Eseutil = Join-Path $env:ExchangeInstallPath "Bin\eseutil.exe"
```

So if you move:

```text
Mailbox Database 1
```

from the default Exchange location to:

```text
D:\Exchange\DB01\WhateverYouCalledIt.edb
```

the script doesn't care. `Get-MailboxDatabase` gives us the actual configured EDB path. Microsoft documents `EdbFilePath` specifically for this purpose.

**One more thing:** I would not run `/d` on multiple databases simultaneously. The script deliberately does them **one at a time**, because ESEUTIL is extremely I/O intensive and each database has to be offline during compaction. Microsoft documentation describes `/d` as an offline compaction operation.

If you tell me **what you're currently using to create the shadow copy** (e.g. `diskshadow`, `vssadmin`, `wbadmin`, or a batch file), I can adapt the VSS portion to match what you already know works on your Exchange server rather than introducing `wbadmin` as a new dependency.
