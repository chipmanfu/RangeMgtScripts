<# Powershell script for managing Ghost Traffic Generator
    WRITTEN BY: Chip McElvain 
    VERSION HISTORY: Version 1 3-3-2020
                     Version 2 1-21-2021 change all options into gridview selectable, also made all actions run in parallel.
                     Version 3 8-16-2022 Added remotely starting Ghosts.  Requires giving the script access to the user creds for each system you want ghost to run on, plus each user needs
                                         RDP permissions to the workstation.  
                                         GPO way to allow all user RDP.  Create GPO and add the following settings
                                         step 1 computer configuration > Admin templates > windows components > Remote Desktop Service > Remote Desktop Session host > connections 
                                                            Change "Allow users to connect remotely using Remote Desktop Service" to enabled.
                                         Step 2 Computer configuration > windows settings > security settings > windows firewall with advanced security > Inbound Rules
                                                            Right click > new rule > Predefined "Remote Desktop  then allow
                                         Step 3 Computer configuration > windows settings > security settings > Restricted Groups
                                                            Right click > Add Group > add Remote Desktop Users then for allowed groups add "Domain Users"

    TO BE EXECUTED ON: Primary Domain Controller
     
    NOTE: If you get "Not Digitally Signed" ERROR.  Then open the script in Powershell ISE, then make a simple edit and save it. 

    PRE-REQS: Powershell remoting has to be enabled for any of this to work against remote range systems.

    USES:  Install, uninstall, start, or stop ghosts on connectable clients.  Also removes or adds ghost/UE to registry run keys.
#>
#### USER SET VARIABLES SECTION ####
####--- INIIIAL VARIABLES ---#### NOTE: EDIT THESE ITEMS TO match your environment.  The rest of the code should work on most domain setups. 
#                                 The Only other section you need to modify is the StartGhost function.  See Note at the end of the section.
#
#   Variable Descriptions
#  "ProfileDir"       -- Profiles folder should contain folders named after the profile, in those folders should just be the specific config files.
#  "GhostsDir"        -- Directory where the Ghost application resides on the local computer
#  "remotedir"        -- Directory where you want to place Ghost on remote systems.  Script uses SMB, so you need to specify c$
#  "remoteProfileDir" -- Directory where the "Ghosts\config" folder resides on a remote system. Script uses SMB, so you need to specify c$
#  "credfile"         -- CSV of workstation,Username,Password to be used for local login Ghosts on workstations.
#  "domain"           -- Name of the domain.
#
### User Variable Section
$ProfileDir = "C:\Users\paul.soto.adm\Desktop\Ghosts\Profiles\"    
$GhostsDir = "C:\Users\paul.soto.adm\Desktop\Ghosts\Ghosts"
$remotedir = "c`$\Ghosts\"
$remoteProfileDir = "c`$\Ghosts\config\"
$credfile = "C:\Users\paul.soto.adm\Desktop\RangeManagement\GF_Users.csv"
$domain="galfed"
#### END USER SET VARIABLES SECTION ####

Import-Module PSWorkflow

$creds = Import-Csv -path $credfile

#### UpdateProfile Function START
function UpdateProfile( $UpdateProfileList, $profile, $locald, $remoted ) {
  $msg = "Updating ghost profile on selected systems `r`n  This is ran in parallel, results will be captured in a pop-up box.`r`n"
  $TBX_Progress.text = $msg
  $Form.Controls.add($TBX_Progress)
  $TBX_Progress.BringToFront()
  workflow parallelcopy {
    param ([string[]]$ComputerList,
           [string]$profilein,
           [string]$localdir,
           [string]$remotedir)
    foreach -parallel ($computer in $ComputerList){
      $localpath = $localdir + $profilein + "\*"
      $remotepath = "\\" + $computer + "\" + $remotedir
      try {
        Copy-Item $localpath -Destination $remotepath -Recurse -Force -ErrorAction Stop
        echo  " Profile updated on $computer`r`n"
       } catch {
        echo " Update failed on $computer`r`n"
       }
    }
    return $result
  }
  parallelcopy -ComputerList $UpdateProfileList -profilein $profile -localdir $locald -remotedir $remoted
  $Form.controls.add($BTN_Closedialog)
  $BTN_Closedialog.BringToFront()
}
#### UpdateProfile Function END

#### DeployGhost Function START
function DeployGhost( $DeployList, $locald, $remoted ) {
  $msg = "Deploying ghost on selected systems `r`n  This is ran in parallel, results will be captured in a pop-up box.`r`n  This will take a minute or two`r`n"
  $TBX_Progress.text = $msg
  $Form.Controls.add($TBX_Progress)
  $TBX_Progress.BringToFront()
  workflow parallelcopy {
    param ([string[]]$ComputerList,
           [string]$localdir,
           [string]$remotedir)
    foreach -parallel ($computer in $ComputerList){
     $remotepath = "\\" + $computer + "\" + $remotedir
      try {
        Copy-Item $localdir -Destination $remotepath -Recurse -Force -ErrorAction Stop
        echo " Ghost Deployed successful on $computer`r`n"
       } catch {
        echo " Deployment failed on $computer`r`n"
       }
    }
  }
  parallelcopy -ComputerList $DeployList -localdir $locald -remotedir $remoted
  $Form.controls.add($BTN_Closedialog)
  $BTN_Closedialog.BringToFront()
}
#### DeployGhost Function END

#### RemoveGhost Function START
function RemoveGhost( $RemoveList, $ghostdir ) {
  $msg = "Uninstalling ghost on selected systems `r`n This is ran in parallel, results will be captured in a pop-up box. `r`n  This will take a minute or two`r`n"
  $TBX_Progress.text = $msg
  $Form.Controls.add($TBX_Progress)
  $TBX_Progress.BringToFront()
  ## First you must kill ghost running on the host.
  $KSB = {
     if (Get-Process -Name "ghosts" -ErrorAction SilentlyContinue){ 
       Invoke-Expression -Command:"cmd.exe /c 'c:\Ghosts\Kill-ghosts.bat'" | Out-Null
     }
   }
  ICM $RemoveList $KSB
  ## Next remove ghost from remote systems.
  workflow parallelcopy {
    param ([string[]]$ComputerList,
           [string]$remotedir)
    foreach -parallel ($computer in $ComputerList){
     $remotepath = "\\" + $computer + "\" + $remotedir
      try {  
        # Check if installed
        if (Test-Path $remotepath){
          Remove-Item -Recurse -Force $remotepath
          echo " Ghost removed from $computer`r`n"
        } else {
          echo " Ghost wasn't installed on $computer`r`n"
        }
      } catch {
        echo " Script Error on $computer`r`n"
       }
    }
  }
  parallelcopy -ComputerList $RemoveList -remotedir $ghostdir
  $Form.controls.add($BTN_Closedialog)
  $BTN_Closedialog.BringToFront()
}
#### RemoveGhost Function END

#### StartGhost Function START
function StartGhost( $StartList ) {
  $msg = "Starting ghost on selected systems `r`n"
  $TBX_Progress.text = $msg
  $Form.Controls.add($TBX_Progress)
  $TBX_Progress.BringToFront()
  foreach ($startsystem in $StartList) {
    $TBX_Progress.AppendText(" Working on $startsystem `r`n")
    $user=
    $password=
    write-host $startsystem
    $finduser = $creds | Where-Object {$_.Workstation -like "$startsystem"}
    
    $password = $finduser.Password
    $user = $finduser.Username
    if ( ($user -eq $Null) -or ($password -eq $Null) ) {
      $TBX_Progress.AppendText("    ERROR! Couldn't find creds for $startsystem in $credfile `r`n")
      continue
    }
    $TBX_Progress.AppendText("    Disabling UE and adding Ghost to startup `r`n")
    ICM $startsystem { Set-ItemProperty -path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run -Name "UserEmulation Actuator" -Value ([byte[]](0x33,0x32,0xFF));
                       Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run -Name "Ghosts" -Value "c:\Ghosts\ghosts.exe" } 
    cmdkey /generic:TERMSRV/$startsystem /user:$domain\$user /pass:$password
    $TBX_Progress.AppendText("    Launching RDP session to $startsystem `r`n")
    mstsc /v:$startsystem /w:800 /h:600
    $IDavailable=$false
    $RDPID=""
    while ($IDavailable -eq $false){
      $UserQuery = quser /server:$startsystem 2>&1
      if ($UserQuery -match "rdp-tcp"){ 
        $RDPSession = $UserQuery | ForEach-Object -Process { $_ -replace '\s{2,}',',' } | convertFrom-CSv | where-object -FilterScript { $_.Username -eq $user -and $_.SESSIONNAME -like "rdp-tcp*" }
        $RDPID=$RDPSession.ID
        $IDavailable = $true
      } else {
        Start-Sleep -Seconds 1
      }
    }
    Start-Sleep -Seconds 4
    $TBX_Progress.AppendText("    Killing RDP session and transitioning to local session on $startSystem `r`n")
    ICM $startsystem { param($id,$pass) tscon $id /dest:console /password:$pass } -ArgumentList $RDPID, $password
    #Start-sleep -seconds 1
    stop-process -Name mstsc
    $TBX_Progress.AppendText(" $startsystem completed `r`n")
  }
  $TBX_Progress.AppendText("NOTE: Ghosts doesn't start up right away.  If the status shows not running,`r`n")
  $TBX_Progress.AppendText("      wait a minute or two and click 'refresh'`r`n")
  $Form.controls.add($BTN_Closedialog)
  $BTN_Closedialog.BringToFront()
}
#### StartGhost Function STOP

#### KillGhost Function START
function KillGhost( $KillList ) {
  $msg = "Killing ghost on selected systems `r`n  This is ran in parallel, it can take a minute or so.`r`n"
  $TBX_Progress.text = $msg
  $Form.Controls.add($TBX_Progress)
  $TBX_Progress.BringToFront()
  ## Create scriptblock variable - checks if ghosts is running, if it is, it will kill it and all processes owned by the user.
  $KSB = { 
    $killstat = @{}
    if (Get-Process -Name "ghosts" -ErrorAction SilentlyContinue){
      Invoke-Expression -Command:"cmd.exe /c 'c:\Ghosts\Kill-ghosts.bat 2> nul'" | Out-Null
      $killstat.Add('status',"Ghost Busted on ")
    } else { $killstat.Add('status',"wasn't running on ") }
    New-Object -TypeName PSObject -Property $killstat 
  }
  
  $killstatus = @()
  $killstatus += ICM $KillList $KSB 
  foreach ($kstatus in $killstatus){
    $status = $kstatus.status
    $ksystem = $kstatus.PSComputerName
    $TBX_Progress.AppendText($status + $ksystem +"`r`n")
  }
  $Form.controls.add($BTN_Closedialog)
  $BTN_Closedialog.BringToFront()
}
#### KillGhost Function END

#### RemoveGhostStart Function START
function RemoveGhostStart($computers){
  $msg = "Removing ghost from Startup on selected `r`n  This needs to remove a HKLM and HKCU run key.`r`n The HKCU needs to run serially,afterward the HKLM will be remove in parallel`r`n"
  $TBX_Progress.text = $msg
  $Form.Controls.add($TBX_Progress)
  $TBX_Progress.BringToFront()
  foreach ($removesystem in $computers){
    $TBX_Progress.AppendText("  Working on $removesystem `r`n")
    $user=
    $finduser = $creds | Where-Object {$_.Workstation -like "$removesystem.*"}
    $user = $finduser.Username
    if ( ($user -eq $Null) -or ($user -eq "") ) {
      $TBX_Progress.AppendText("    ERROR! Couldn't find username for $removesystem in $credfile `r`n")
      continue
    }
    $result = ICM $removesystem -ArgumentList $user { param($user)
                        try {
                           reg load HKU\$user c:\Users\$user\NTUSER.DAT
                           Remove-ItemProperty -Path Registry::HKU\$user\Software\Microsoft\Windows\CurrentVersion\Run -name "ghosts" -Force
                           reg unload HKU\$user
                           $rrstatus="`r`n    Removed HKCU key on"
                        } catch {
                           $rrstatus="`r`n    HKCU run key didn't exist on "
                        }
                        return $rrstatus
                        }
    $TBX_Progress.AppendText($result + $removesystem + "`r`n")
  }
  $TBX_Progress.AppendText("Next removing HKLM run keys `r`n")
  $RGSSB = {
    $removestat = @{}
    try {
        Remove-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run -name "Ghosts" -Force
        $removestat.Add('status',"Removed HKLM run key on ")
    } catch {
        $removestat.Add('status',"HKLM run key was removed previously on ")
    }
    New-Object -TypeName PSObject -Property $removestat
  }
  $removestatus = @()
  $removestatus += ICM $computers $RGSSB
  foreach ($rstatus in $removestatus){
    $status = $rstatus.status
    $rsystem = $rstatus.PSComputerName
    $TBX_Progress.AppendText($status + $rsystem + "`r`n")
  }
  $Form.controls.add($BTN_Closedialog)
  $BTN_Closedialog.BringToFront()
}
#### RemoveGhostStart Function END

#### EnableUE Function START
function EnableUE($computers){
  $msg = "Enabling UE run key on selected systems `r`n  This is ran in parallel, takes minute or less`r`n"
  $TBX_Progress.text = $msg
  $Form.Controls.add($TBX_Progress)
  $TBX_Progress.BringToFront()
  $EUESB = {
    $uestat = @{}
    Set-ItemProperty -path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run -Name "UserEmulation Actuator" -Value ([byte[]](0x02,00,00,00,00,00,00,00,00,00,00,00))
    $uestat.Add('status',"UE Enabled on ")
    New-Object -TypeName PSObject -Property $uestat
  }
  $uestatus = @()
  $uestatus += ICM $computers $EUESB
  foreach ($estatus in $uestatus){
    $status = $estatus.status
    $esystem = $estatus.PSComputerName
    $TBX_Progress.AppendText($status + $esystem + "`r`n")
  }
  $Form.controls.add($BTN_Closedialog)
  $BTN_Closedialog.BringToFront()
}
#### EnableUE Function END

#### LogOffUser Function START
function LogOffAllUsers($computers) {
  $msg = "Logging off all users from selected systems `r`n  This is ran in parallel, should take a minute or so`r`n"
  $TBX_Progress.text = $msg
  $Form.Controls.add($TBX_Progress)
  $TBX_Progress.BringToFront()
  $LOSB = {
      $logstat = @{} 
      $q = (query user) -split "\n" -replace '\s{18}\s+', "  blank  " 2>$Null
      if (!$q){
        $logstat.Add('status',"No users found logged into ")
      } else {
        $sessions = $q -split "\n" -replace '\s\s+', "," | convertfrom-csv
        foreach ($session in $sessions){ 
          $id = $session.ID 
          $userin = $session.USERNAME
          logoff $id 
          $logstat.Add('status',"User $userin was logged from ")  
        }
      }
      New-Object -TypeName PSObject -Property $logstat
    }
  $logstatus = @()
  $logstatus += ICM $computers $LOSB
  foreach ($lstatus in $logstatus){
    $status = $lstatus.status
    $lsystem = $lstatus.PSComputerName
    $TBX_Progress.AppendText($status + $lsystem + "`r`n")
  }
  $Form.controls.add($BTN_Closedialog)
  $BTN_Closedialog.BringToFront()
}
#### LogOffUsers Function STOP

#### RebootSystems Function START
function RebootSystems($computers) {
  $msg = "Rebooting selected systems `r`n  This is ran in parallel, should take a minute or so`r`n"
  $TBX_Progress.text = $msg
  $Form.Controls.add($TBX_Progress)
  $TBX_Progress.BringToFront()
  foreach($computer in $computers){
    Restart-Computer -Computername $computer -Force
    $TBX_Progress.AppendText("  Rebooting $computer `r`n")
  }
  $TBX_Progress.AppendText(" NOTE: This will make the rebooted systems unreachable.`r`n Go make a coffee or something before hitting the refresh button`r`n")
  $Form.controls.add($BTN_Closedialog)
  $BTN_Closedialog.BringToFront()
} 

#### GhostStatus Function START
function GhostStatus($computers) {
  ## Create a few arrays for storing data
  $statresult = @()
  $statuses = @()
  ## create scriptblock variable - checks is ghost is running, and if so gets the owner. If not checks if ghost is installed or not.  Saves data as array of objects.
  $CSB = {
    $stat = @{}
    if (($process = Get-process -name "ghosts" -IncludeUserName -ErrorAction SilentlyContinue | Select UserName, StartTime) -ne $NULL){
      $stat.Add('starttime',$process.StartTime)
      $stat.Add('Owner',$process.UserName)
    } elseif ((Get-Content "c:\Ghosts\ghosts.exe" -ErrorAction SilentlyContinue) -eq $NULL) { 
      $stat.Add('Error',"Ghost isn't installed") 
    } else { 
      $stat.Add('Error',"Not Running")
    }
    New-Object -TypeName PSObject -Property $stat  
  }
  ## Runs the scriptblock on all computers at the same time, results are returned to statuses object.
  $statuses = ICM $computers $CSB  -ThrottleLimit 20 
  ## processes the statuses object to put it in the format used by the datagridview used by the GUI to display the status
  foreach ($status in $statuses){
    $statProp = @{}
    if ($status.Error) {
      $Prop = [ordered]@{System = $status.PSComputerName
                Status = $status.Error
                Owner = "N/A"
                StartTime = "N/A"}
    } else {
      $Prop = [ordered]@{System = $status.PSComputerName
                Status ="Running"
                Owner =$status.Owner
                StartTime =$status.starttime}
    }
    $objin = New-Object -Type psobject -Property $Prop
    $statresult += $objin
  }
  ## Sorts the results by system name.
  $statresult | Sort-Object -Property "System"
}
#### GhostStatus Function END

#### updateGhostStatus Function START
function updateGhostStatus {
# Removes the current status datagridview and displays the updating label in its place.
$Form.controls.remove($TB_GhostStatus)
$Form.controls.Add($LBL_Update)
# gets status update from the GhostStatus function
$result = GhostStatus $alives
# Create an ArrayList object needed for the datagridview
$dresult = New-Object System.Collections.ArrayList
# Adds ghost status results to the Arraylist object
$dresult.AddRange($result)
# updates the datagridview form data with the results.
$TB_GhostStatus.DataSource = $dresult
#displays the datagridview and removes the updating label.
$Form.controls.Add($TB_GhostStatus)
$TB_GhostStatus.ClearSelection()
$Form.controls.remove($LBL_Update)
}
#### updateGhostStatus Function END

####--- START GHOSTS FORM ---####
write-host "Ghost Management GUI initializing"
## get a list of all domain computers with the exception of the system is is running on.(Typically you run this from a DC)  
$self=hostname
$computers = Get-ADComputer -Filter "Name -ne '$self'" | Sort-Object -Property Name | Select Name 

# Check if PSRemoting enabled or if the system is reachable and generate a list of alives to run remote commands against.
$allcomputers = New-Object System.Collections.ArrayList
$alives = New-Object System.Collections.ArrayList
$deads = New-Object System.Collections.ArrayList

$allcomputers += $computers.Name
write-host "Getting list of all reachable systems"
$PScheck = ICM $computers.Name {1} -ErrorAction SilentlyContinue 
$alives += $PScheck.PSComputername
$deads = $allcomputers | where {$alives -notcontains $_}
if ( $deads -ne $Null){
  write-host "The following systems were unreachable $deads"
} else {
  write-host "all systems were reachable"
}
Add-Type -AssemblyName System.Windows.Forms

$Form = New-Object system.Windows.Forms.Form
$Form.Text = "Ghosts Manager"
$Form.AutoSize = $true

$result = GhostStatus $alives
$dresult = New-Object System.Collections.ArrayList
$dresult.AddRange($result)

$LBL_Update = New-Object System.Windows.Forms.Label
$LBL_Update.Text = "Updating ...."
$LBL_Update.AutoSize = $true
$LBL_Update.BorderStyle = 'FixedSingle'
$LBL_Update.Height = 25

$LBL_Update.TextAlign = "MiddleCenter"
$LBL_Update.location = new-object system.drawing.point(400,110)
$LBL_Update.Font = "Microsoft Sans Serif,12"

$TB_GhostStatus = New-Object System.Windows.Forms.DataGridView
$TB_GhostStatus.ReadOnly = $true
$TB_GhostStatus.DataSource = $dresult
$TB_GhostStatus.AutoSizeColumnsMode = 6
$TB_GhostStatus.Width = 0
$TB_GhostStatus.Height = 0
$TB_GhostStatus.AutoSize = $true
$TB_GhostStatus.BorderStyle = 'None'
$TB_GhostStatus.BackgroundColor = 'control'
$TB_GhostStatus.RowHeadersVisible = $false
$TB_GhostStatus.AllowUserToResizeRows = $false
$TB_GhostStatus.AllowUserToResizeColumns = $false
$TB_GhostStatus.location = new-object system.drawing.point(320,90)
$TB_GhostStatus.Font = "Microsoft Sans Serif,10"
$Form.controls.Add($TB_GhostStatus)

$LBL_SystemSel = New-Object System.Windows.Forms.Label
$LBL_SystemSel.Text = "* Select systems from the grid below then actions from the left"
$LBL_SystemSel.AutoSize = $true
$LBL_SystemSel.BorderStyle = "none"
$LBL_SystemSel.location = new-object System.Drawing.Point(320,75)
$LBL_SystemSel.font = "Microsoft Sans Serif,8"
$Form.Controls.Add($LBL_SystemSel)

$BTN_Refresh = New-Object system.windows.Forms.Button
$BTN_Refresh.Text = "Refresh Status"
$BTN_Refresh.Autosize = $true
$BTN_Refresh.Height = 30
$BTN_Refresh.BackColor = "gray"
$BTN_Refresh.ForeColor = "white"
$BTN_Refresh.FlatStyle = "Popup"
$BTN_Refresh.Top = $true
$BTN_Refresh.Add_Click({
    updateGhostStatus
})
$BTN_Refresh.location = new-object system.drawing.point(650,55)
$BTN_Refresh.Font = "Microsoft Sans Serif,10"
$Form.controls.Add($BTN_Refresh)

$LBL_GhostControl = New-Object System.Windows.Forms.Label
$LBL_GhostControl.Text = "Ghost Control"
$LBL_GhostControl.AutoSize = $true
$LBL_GhostControl.Height = 25
$LBL_GhostControl.TextAlign = "MiddleCenter"
$LBL_GhostControl.location = new-object system.drawing.point(20,65)
$LBL_GhostControl.Font = "Microsoft Sans Serif,12"
$Form.controls.Add($LBL_GhostControl)

$LBL_Sel_profile = New-Object system.windows.Forms.Label
$LBL_Sel_profile.Text = "Select a Profile:"
$LBL_Sel_profile.width = 110
$LBL_Sel_profile.Height = 25
$LBL_Sel_profile.BackColor = "lightgray"
$LBL_Sel_profile.TextAlign = "MiddleRight"
$LBL_Sel_profile.location = new-object system.drawing.point(25,100)
$LBL_Sel_profile.Font = "Microsoft Sans Serif,10"
$LBL_Sel_profile.BringToFront()
$Form.controls.Add($LBL_Sel_profile)

$DD_Sel_profile = New-Object System.Windows.Forms.ComboBox
$DD_Sel_profile.AutoSize = $true
$DD_Sel_profile.Height = 30
$DD_Sel_profile.location = new-object system.drawing.point(150,100)
$pdirs = Get-ChildItem -Path $ProfileDir -Directory | Select Name
foreach ($pdir in $pdirs) { $DD_Sel_profile.Items.Add($pdir.Name) }
$Form.controls.Add($DD_Sel_profile)

$BTN_UpdateProfile = New-Object system.windows.Forms.Button
$BTN_UpdateProfile.Text = "Update Profile"
$BTN_UpdateProfile.width = 130
$BTN_UpdateProfile.BackColor = "gray"
$BTN_UpdateProfile.ForeColor = "white"
$BTN_UpdateProfile.FlatStyle = "Popup"
$BTN_UpdateProfile.Height = 30
$BTN_UpdateProfile.Add_Click({
  $profilein = $DD_Sel_profile.SelectedItem 
  if (($selected = $TB_GhostStatus.SelectedCells.RowIndex | select -Unique | sort) -ne $NULL -AND $profilein -ne $NULL){ 
    $cpus = @()
    foreach ($sel in $selected){ $cpus += $TB_GhostStatus.Rows[$sel].Cells[0].value;  }
    $updateresults = UpdateProfile $cpus $profilein $ProfileDir $remoteProfileDir
    [System.Windows.MessageBox]::show("$updateresults")
    $TB_GhostStatus.ClearSelection()
  } else {
    if ( $selected -eq $NULL -and $profilein -eq $NULL){
      $msg = "You didn't select a system to update and you didn't select a profile."
    } elseif ( $selected -ne $NULL ){
      $msg = "You didn't select a profile, use the profile dropdown and try again"
    } else { $msg = "You didn't select a system to update with profile $profilein, select a system and try again" } 
    [System.Windows.MessageBox]::show("$msg")
  }
})

$BTN_UpdateProfile.location = new-object system.drawing.point(150,130)
$BTN_UpdateProfile.Font = "Microsoft Sans Serif,10"
$Form.controls.Add($BTN_UpdateProfile)

$TBX_Progress = New-object System.Windows.Forms.TextBox
$TBX_Progress.Width = 500
$TBX_Progress.Height = 500
$TBX_Progress.ScrollBars = "Vertical"
$TBX_Progress.Multiline = $true
$TBX_Progress.Location = New-Object System.Drawing.Point(30,30)
$TBX_Progress.font = "Microsoft Sans Serif, 8"
$TBX_Progress.Add_Click({$Forms.controls.Remove($TBX_Progress)})
$BTN_Closedialog = New-Object System.Windows.Forms.Button 
$BTN_Closedialog.Location = New-Object System.Drawing.Point(430,490)
$BTN_Closedialog.text = "Close"
$BTN_Closedialog.Autosize = $true
$BTN_Closedialog.Height = 30
$BTN_Closedialog.add_click({
  $Form.Controls.Remove($BTN_Closedialog)
  $Form.Controls.Remove($TBX_Progress)
})

$BTN_Start = New-Object system.windows.Forms.Button
$BTN_Start.Text = "Start Ghost"
$BTN_Start.width = 130
$BTN_Start.Height = 30
$BTN_Start.FlatStyle = "Popup"
$BTN_Start.BackColor = "green"
$BTN_Start.ForeColor = "white"
$BTN_Start.Add_Click({
  if (($selected = $TB_GhostStatus.SelectedCells.RowIndex | select -Unique | sort) -ne $NULL){ 
    $cpus = @()
    foreach ($sel in $selected){ $cpus += $TB_GhostStatus.Rows[$sel].Cells[0].value;  }
    StartGhost $cpus 
    updateGhostStatus
    $TB_GhostStatus.ClearSelection()
  } else {
    [System.Windows.MessageBox]::show("You didn't select a system to start")
  }
})
$BTN_Start.location = new-object system.drawing.point(150,170)
$BTN_Start.Font = "Microsoft Sans Serif,10"
$Form.controls.Add($BTN_Start)

$BTN_Kill = New-Object system.windows.Forms.Button
$BTN_Kill.Text = "Kill Ghost"
$BTN_Kill.width = 130
$BTN_Kill.Height = 30
$BTN_Kill.BackColor = 'red'
$BTN_Kill.FlatStyle = "Popup"
$BTN_Kill.Add_Click({
  if (($selected = $TB_GhostStatus.SelectedCells.RowIndex | select -Unique | sort) -ne $NULL){ 
    $cpus = @()
    foreach ($sel in $selected){ $cpus += $TB_GhostStatus.Rows[$sel].Cells[0].value;  }
    KillGhost $cpus 
    updateGhostStatus
    $TB_GhostStatus.ClearSelection()
  } else {
    [System.Windows.MessageBox]::show("You didn't select a system to kill")
  }
})
$BTN_Kill.location = new-object system.drawing.point(150,210)
$BTN_Kill.Font = "Microsoft Sans Serif,10"
$Form.controls.Add($BTN_Kill)

$BOX_GhostControl = New-object System.Windows.Forms.Label
$BOX_GhostControl.BackColor = "lightgray"
$BOX_GhostControl.height = 160
$BOX_GhostControl.Width = 280
$BOX_GhostControl.BorderStyle = "fixedSingle"
$BOX_GhostControl.Location = new-object system.drawing.point(24,90)
$Form.Controls.Add($BOX_GhostControl)
$BOX_GhostControl.SendToBack()

$LBL_GhostAppMgt = New-Object System.Windows.Forms.Label
$LBL_GhostAppMgt.Text = "System Management"
$LBL_GhostAppMgt.AutoSize = $true
$LBL_GhostAppMgt.Height = 25
$LBL_GhostAppMgt.TextAlign = "MiddleCenter"
$LBL_GhostAppMgt.location = new-object system.drawing.point(20,255)
$LBL_GhostAppMgt.Font = "Microsoft Sans Serif,12"
$Form.controls.Add($LBL_GhostAppMgt)

$BTN_Deploy = New-Object system.windows.Forms.Button
$BTN_Deploy.Text = "Install Ghost"
$BTN_Deploy.width = 130
$BTN_Deploy.Height = 30
$BTN_Deploy.FlatStyle = "Popup"
$BTN_Deploy.BackColor = "gray"
$BTN_Deploy.ForeColor = "white"
$BTN_Deploy.Add_Click({
  if (($selected = $TB_GhostStatus.SelectedCells.RowIndex | select -Unique | sort) -ne $NULL ){ 
    $cpus = @()
    foreach ($sel in $selected){ $cpus += $TB_GhostStatus.Rows[$sel].Cells[0].value;  }
    $deployresults = DeployGhost $cpus $GhostsDir $remotedir 
    [System.Windows.MessageBox]::show("$deployresults")
    $TB_GhostStatus.ClearSelection()
    updateGhostStatus
  } else {
    [System.Windows.MessageBox]::show("You didn't select a system to deploy ghost on.")
  }
})
$BTN_Deploy.location = new-object system.drawing.point(30,290)
$BTN_Deploy.Font = "Microsoft Sans Serif,10"
$Form.controls.Add($BTN_Deploy)

$BTN_Remove = New-Object system.windows.Forms.Button
$BTN_Remove.Text = "Uninstall Ghost"
$BTN_Remove.width = 130
$BTN_Remove.Height = 30
$BTN_Remove.FlatStyle = "Popup"
$BTN_Remove.BackColor = "orange"
$BTN_Remove.Add_Click({
   if (($selected = $TB_GhostStatus.SelectedCells.RowIndex | select -Unique | sort) -ne $NULL ){ 
    $cpus = @()
    foreach ($sel in $selected){ $cpus += $TB_GhostStatus.Rows[$sel].Cells[0].value;  }
    $removeresults = RemoveGhost $cpus $remotedir 
    [System.Windows.MessageBox]::show("$removeresults")
    $TB_GhostStatus.ClearSelection()
    updateGhostStatus
  } else {
    [System.Windows.MessageBox]::show("You didn't select a system to remove ghost on.")
  }
})
$BTN_Remove.location = new-object system.drawing.point(30,330)
$BTN_Remove.Font = "Microsoft Sans Serif,10"
$Form.controls.Add($BTN_Remove)

$BTN_RemoveGhostStartup = New-Object System.Windows.Forms.Button
$BTN_RemoveGhostStartup.Text = "Remove Ghost Startup "
$BTN_RemoveGhostStartup.width = 130
$BTN_RemoveGhostStartup.Height = 30
$BTN_RemoveGhostStartup.BackColor = "gray"
$BTN_RemoveGhostStartup.ForeColor = "white"
$BTN_RemoveGhostStartup.FlatStyle = "Popup"
$BTN_RemoveGhostStartup.Add_Click({
  if (($selected = $TB_GhostStatus.SelectedCells.RowIndex | select -Unique | sort) -ne $NULL){ 
    $cpus = @()
    foreach ($sel in $selected){ $cpus += $TB_GhostStatus.Rows[$sel].Cells[0].value;  }
    $answer = [system.Windows.MessageBox]::show("This will log off users first.  Do you want to continue?","warning",4)
    if ($answer -eq 'Yes'){
      LogOffAllUsers $cpus
      RemoveGhostStart $cpus 
    } else {
      [system.Windows.MessageBox]::show("Cancelling Removal of Ghost from Run keys!")
    }
    $TB_GhostStatus.ClearSelection()
  } else {
    [System.Windows.MessageBox]::show("You didn't select a system to remove Ghost from Startup")
  }
})
$BTN_RemoveGhostStartup.Location = new-object System.Drawing.Point(165,290)
$Form.controls.Add($BTN_RemoveGhostStartup)

$BTN_EnableUEStartup = New-Object System.Windows.Forms.Button
$BTN_EnableUEStartup.Text = "Enable UE on Startup"
$BTN_EnableUEStartup.width = 130
$BTN_EnableUEStartup.Height = 30
$BTN_EnableUEStartup.FlatStyle = "Popup"
$BTN_EnableUEStartup.BackColor = "gray"
$BTN_EnableUEStartup.ForeColor = "white"
$BTN_EnableUEStartup.Add_Click({
  if (($selected = $TB_GhostStatus.SelectedCells.RowIndex | select -Unique | sort) -ne $NULL){ 
    $cpus = @()
    foreach ($sel in $selected){ $cpus += $TB_GhostStatus.Rows[$sel].Cells[0].value;  }
    EnableUE $cpus 
    
    $TB_GhostStatus.ClearSelection()
  } else {
    [System.Windows.MessageBox]::show("You didn't select a system to Enable UE on")
  }
})
$BTN_EnableUEStartup.Location = new-object System.Drawing.Point(165,330)
$Form.controls.Add($BTN_EnableUEStartup)

$BTN_LogOff = New-Object System.Windows.Forms.Button
$BTN_LogOff.text = "Log off all users"
$BTN_LogOff.width = 130
$BTN_LogOff.Height = 30
$BTN_LogOff.BackColor = "red"
$BTN_LogOff.FlatStyle = "Popup"
$BTN_LogOff.Add_Click({
  if (($selected = $TB_GhostStatus.SelectedCells.RowIndex | select -Unique | sort) -ne $NULL){ 
    $cpus = @()
    foreach ($sel in $selected){ $cpus += $TB_GhostStatus.Rows[$sel].Cells[0].value;  }
    LogOffAllUsers $cpus 
    $TB_GhostStatus.ClearSelection()
  } else {
    [System.Windows.MessageBox]::show("You didn't select a system to log users off of")
  }
})
$BTN_LogOff.Location = new-object System.Drawing.Point(30,370)
$Form.controls.Add($BTN_LogOff)

$BTN_Reboot = New-Object System.Windows.Forms.Button
$BTN_Reboot.text = "Reboot Computer"
$BTN_Reboot.width = 130
$BTN_Reboot.Height = 30
$BTN_Reboot.BackColor = "red"
$BTN_Reboot.FlatStyle = "Popup"
$BTN_Reboot.Add_Click({
  if (($selected = $TB_GhostStatus.SelectedCells.RowIndex | select -Unique | sort) -ne $NULL){ 
    $cpus = @()
    foreach ($sel in $selected){ $cpus += $TB_GhostStatus.Rows[$sel].Cells[0].value;  }
    RebootSystems $cpus 
    $TB_GhostStatus.ClearSelection()
  } else {
    [System.Windows.MessageBox]::show("You didn't select a system to reboot")
  }
})
$BTN_Reboot.Location = New-Object System.Drawing.Point(165,370)
$Form.controls.Add($BTN_Reboot)

$BOX_GhostAppMgt = New-object System.Windows.Forms.Label
$BOX_GhostAppMgt.BackColor = "lightgray"
$BOX_GhostAppMgt.height = 130
$BOX_GhostAppMgt.Width = 280
$BOX_GhostAppMgt.BorderStyle = "fixedSingle"
$BOX_GhostAppMgt.Location = new-object system.drawing.point(24,280)
$Form.Controls.Add($BOX_GhostAppMgt)
$BOX_GhostAppMgt.SendToBack()

$BTN_Exit = New-Object system.windows.Forms.Button
$BTN_Exit.Text = "Exit"
$BTN_Exit.width = 130
$BTN_Exit.Height = 30
$BTN_Exit.BackColor = "gray"
$BTN_Exit.ForeColor = "white"
$BTN_Exit.FlatStyle = "Popup"
$BTN_Exit.Add_Click({
    $Form.Close()
})
$BTN_Exit.location = new-object system.drawing.point(100,430)
$BTN_Exit.Font = "Microsoft Sans Serif,10"
$Form.controls.Add($BTN_Exit)

$Form.add_shown({$TB_GhostStatus.ClearSelection()})
[void]$Form.ShowDialog()
$Form.Dispose()