<# Powershell script for internal range management and testing.  
     WRITTEN BY: Chip McElvain 
     Created: Sep 24, 2024
     Updated by:
     Updated date:
#>

function Range-Check($hostin) {
######## USER SET VARIABLES SECTION ####

  # The following settings enables or disables a check, 1 enables and 0 disables.
  $timecheck = 1                 # Returns Host timezone, its current date/time, then computes the offset between its time and the DC's
  $licensecheck = 1              # Returns Windows license status for the OS and Office and checks for activation
  $drivecheck = 1                # Returns the Free space available on the C drive
  $ipcheck = 1                   # Returns the IP address, and Network Interface Profile
  $graycheck = 1                 # Checks if the host can reach grayspace (test DNS and grayspace connectivity)
  $crowdstrikecheck = 1          # Returns Crowdstrike Version and if its running
  $sepcheck = 1                  # Returns SEP Version and if its running
  $taniumcheck = 0               # Returns Tanium Version and if its running

  $testwebsite = "redbook.com"   # This should be a website in the grayspace that should be reachable from bluespace
######## END USER SET VARIABLES SECTION ####

  write-host "The range Check has started, it can take up to a minute for results to come back"
  # get localhost to exclude from script, you can't run remote commands on the localhost. Testing the localhost is at the end of this function.
  $self=hostname
  # Check to see if a argument was passed to the script, this allows you to run the script against a specific host, otherwise it will grab all domain computers except itself.
  if ($hostin -eq $NULL){
    $computers = Get-ADComputer -Filter "Name -ne '$self'" | Sort-Object -Property Name
  } else {
    $computers = Get-ADComputer -Filter "Name -eq '$hostin'"
  }
  # Create Arrays to capture parse out what systems are reachable (PSRemoting enabled) and which aren't (PSRemoting Disabled, or unreachable for other reasons)
  $allcomputers = New-Object System.Collections.ArrayList
  $alives = New-Object System.Collections.ArrayList
  $deads = New-Object System.Collections.ArrayList

  # Put all computers found in Get-ADComputer in the all computers array
  $allcomputers += $computers.Name
  # Run a quick check to see which ones are reachable via PS-Remoting.
  write-host "  Getting list of all reachable systems . . ." -NoNewline
  $PScheck = ICM $computers.Name {1} -ErrorAction SilentlyContinue 
  
  # Put all reachable computers into the alives array.
  $alives += $PScheck.PSComputername
  $totalalive = $alives.count 
  # Compare the alives array from the allcomputers array to list all the unreachable computers and put those in the dead array.
  $deads = $allcomputers | where {$alives -notcontains $_}
  $totaldead = $deads.count
  write-host " Completed! ($totalalive found) ($totaldead unreachable)"
  # Get local time from the system this is ran on, typically the DC, to compare remote system time against to determine time offsets.
  $dcdate = Get-Date
  
  # Run remote commands against all alives in Parallel using ICM (short hand use of invoke-command). Providing a list against this forces parallel execution.  All outputs are
  # placed into an Results array of objects for each system.
  # based on user selections, build out list of commands to be ran within a invoke-command (IMC).

  ###### Adding checks to the IMC Section #######
  # Set up base command
  $command = "`$system = hostname`n"
  # Set up output PSobject - This will put the resulting output into its own object to process later.
  $outputpso = "New-Object PSObject -Property @{`n"
  $outputpso += "`   'Systemin' = `$system`n" 

  # if time check is selected, add IMC commands to $command and add the output of these commands to the output object.
  if ($timecheck -eq 1){
    $command += "`$date = Get-Date`n"
    $command += "`$TZ = [timezoneinfo]::local.DisplayName`n"
    $outputpso += "`  'TZ' = `$TZ`n"
    $outputpso += "`  'datein' = `$date`n"
  }	  

  # if license check is selected, add IMC commands to $command and add the output of these commands to the output object.
  if ($licensecheck -eq 1){
    $command += "`$searcher = New-Object -TypeName System.management.ManagementObjectSearcher(`"Select Name, LicenseStatus, GracePeriodRemaining FROM SoftwareLicensingProduct WHERE ProductKeyID != Null`")`n"
	$command += "`$LStatus = `$searcher.get()`n"
    $outputpso += "`  'LStatus' = `$LStatus`n"
  }

  # if drive check is selected, add IMC commands to $command and add the output of these commands to the output object.
  if ($drivecheck -eq 1){
    $command += "`$Dspace = Get-WmiObject -class Win32_LogicalDisk -Filter `"DeviceID ='c:'`" | Select-Object -Property DeviceID, @{ Name ='percent';Expression = {[int](`$_.Freespace*100/`$_.size)}}`n"
    $outputpso += "`  'Dspace' = `$Dspace`n"
  }

  # if IP check is selected, add IMC commands to $command and add the output of these commands to the output object.
  if ($ipcheck -eq 1){
    $command += "`$ipobj = Get-NetIPAddress | Where { `$_.IPAddress -notlike `"10.10.*`" -and `$_.IPAddress -notlike `"127.0.0.*`" -and `$_.AddressFamily -eq `"IPv4`" } | Select-Object -First 1`n"
    $command += "`$ip = `$ipobj.IPAddress`n"
    $command += "`$IntIndex = `$ipobj.InterfaceIndex`n"
    $command += "`$netobj = Get-NetConnectionProfile -InterfaceIndex `$IntIndex`n"
    $command += "`$netprofile = `$netobj.NetworkCategory`n"
    $outputpso += "  'netprofile' = `$netprofile`n"
    $outputpso += "  'ip' = `$ip`n"
  }

  # if gray check is selected, add IMC commands to $command and add the output of these commands to the output object.
  if ($graycheck -eq 1){
    $command += "`if (Test-Connection -Computername `"$testwebsite`" -count 1 -ErrorAction Silentlycontinue){ `$gray = `"yes`" } else { `$gray = `"no`" }`n" 
    $outputpso += "  'gray' = `$gray`n"
  }

  # if crowdstrike check is selected, add IMC commands to $command and add the output of these commands to the output object.
  if ($crowdstrikecheck -eq 1){
    $command += "`$CSVersion = Get-Package -Name `"CrowdStrike Windows Sensor`" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue`n"
    $command += "if (`$CSVersion) { `$CSVer = `$CSVersion.Version } else { `$CSVer = `"0.0.0.0`" }`n"
    $command += "if (Get-Process -Name `"CSFalconService`" -ErrorAction SilentlyContinue) { `$CSRunning = `"yes`" } else { `$CSRunning = `"no`" }`n"
    $outputpso += "  'CSver' = `$CSVer`n"
    $outputpso += "  'CSRunning' = `$CSRunning`n"
  }

  # if SEP check is selected, add IMC commands to $command and add the output of these commands to the output object.
  if ($sepcheck -eq 1){
    $command += "`$SEPVersion = Get-Package -Name `"Symantec Endpoint Protection`" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue`n"
    $command += "if (`$SEPVersion) { `$SEPVer = `$SEPVersion.Version } else { `$SEPVer = `"0.0.0.0`" }`n"
    $command += "if (Get-Process -Name `"ccSvcHst`" -ErrorAction SilentlyContinue) { `$SEPRunning = `"yes`" } else { `$SEPRunning = `"no`" }`n"
    $outputpso += "  'SEPver' = `$SEPVer`n"
    $outputpso += "  'SEPRunning' = `$SEPRunning`n"
  }

  # if $tanium check is selected, add IMC commands to $command and add the output of these commands to the output object.
  if ($taniumcheck -eq 1){
    $command += "`$TMVersion = Get-Package -Name `"*Tanium*`" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue`n"
    $command += "if (`$TMVersion) { `$TMVer = `$TMVersion.Version } else { `$TMVer = `"0.0.0.0`" }`n"
    $command += "if (Get-Process -Name `"TaniumCX`" -ErrorAction SilentlyContinue) { `$TMRunning = `"yes`" } else { `$TMRunning = `"no`" }`n"
    $outputpso += "  'TMver' = `$TMVer`n"
    $outputpso += "  'TMRunning' = `$TMRunning`n"
  }
  ###### End checks to the IMC Section #######
  # Close out the output object 
  $outputpso += "}"
  ## Next we need to modify the command and outputpso so it can be ran locally, you can't run IMC against the local host.
  # First we create the variable $hostpso and copy the $commands into it.
  $hostpso = $command
  # Next we add $Results += before the output object.  This put append the localhost ran psobject output to the results array from all the IMC calls.
  $hostpso += "`$Results += "
  # Next we put the output psobject code in to capture the output from the local host ran commands.
  $hostpso += $outputpso

  # Now we combine the $commands with the output psobject so we can put this inside out IMC call.
  $command += $outputpso

  # Then we run the combined commands with output psobject creation agains all of our $alives systems using ICM which will run in parallel.  The output PSobject is used to organize and collect the results.
  write-host "  Running checks against all reachable systems . . . " -NoNewline
  $Results = ICM $alives { 
    Invoke-Expression $args[0]
  } -ArgumentList $command
  write-host "Complete!!"
  # next we run the combind commands with output psobject against the local host, this will also append the results to the $Results array.
  write-host "  Running checks against local host . . . " -NoNewline
  Invoke-Expression $hostpso
  write-host "Complete!!"

  # Set up array to capture issues to display at the end of the individual status output.
  $warnings = New-Object System.Collections.ArrayList
  $issues = New-Object System.Collections.ArrayList

  # Sort Results by computername so that the script output will be ordered by hostname.
  $sortedResults = $Results | Sort-Object PSComputerName

  # if crowdstrike check is enable, this will look for the newest version and put that in a variable to check against all systems.
  if ($crowdstrikecheck -eq 1){    
    $CSVersionArray = $sortedResults | ForEach-Object { [version]$_.CSVer }
    $SortedCSV = $CSVersionArray | Where-Object { $_ -ne "Not Installed" } | Sort-Object -Descending
    $HighestCSV = $SortedCSV[0]
  }
  # if SEP check is enable, this will look for the newest version and put that in a variable to check against all systems.
  if ($sepcheck -eq 1){
    $SEPVersionArray = $sortedResults | ForEach-Object { [version]$_.SEPver }
    $SortedSEPV = $SEPVersionArray | Where-Object { $_ -ne "Not Installed" } | Sort-Object -Descending
    $HighestSEPV =  $SortedSEPV[0]
  }
  # if tanium check is enable, this will look for the newest version and put that in a variable to check against all systems.
  if ($taniumcheck -eq 1){
    $TMVersionArray = $sortedResults | ForEach-Object { [version]$_.TMVer }
    $SortedTMV = $TMVersionArray | Where-Object { $_ -ne "Not Installed" } | Sort-Object -Descending
    $HighestTMV = $SortedTMV[0]
  }

  # Process through the sorted results array of objects.  
  write-host "  Processing results for output"
  foreach ($item in $sortedResults){
    $currenthost = $item.Systemin
    write-host "Results for" $currenthost -ForegroundColor Green 
    if ($timecheck -eq 1){
      write-host " Timezone   : " -ForegroundColor Yellow -NoNewline;
      write-host $item.TZ
      write-host " Date/Time  : " -ForegroundColor Yellow -NoNewline 
      write-host $item.datein
      $offset = New-TimeSpan -Start ($dcdate) -end ($item.datein) | select TotalSeconds
      $aoffset = [math]::Round($offset.TotalSeconds,2)
      write-host " Time Offset: " -ForegroundColor Yellow -NoNewline; 
      if ($aoffset -gt 3000) { 
        write-host "ERROR! Time offset is greater than 5 minutes.  Offset is"$aoffset -ForegroundColor Red 
        [void]$issues.Add("$currenthost has time sync off by $aoffset seconds")
      } elseif ($aoffset -gt 60) { 
        write-host "Warning!! Time offset is off by over a minute. Offset is"$aoffset -ForegroundColor Yellow 
        [void]$issues.Add("$currenthost has time sync off by $aoffset seconds")
      } else { write-host $aoffset" seconds"}
    }
    if ($licensecheck -eq 1){
	  foreach ($license in $item.LStatus) {
        $licensename = $license.Name
        write-host " License    : " -ForegroundColor Yellow -NoNewline
        if ($license.LicenseStatus -eq 1) {
          if ($license.GracePeriodRemaining -eq 0) { write-host $licensename"is " -NoNewline; write-host "Permentantly Activated" -ForegroundColor green }
          else { 
		    $DaysLeft = [int]($license.GracePeriodRemaining/60/24)
            write-host $licensename" expires in " -NoNewline
            if ($DaysLeft -le 30) {
              write-host $DaysLeft -ForegroundColor Red -NoNewline 
              [void]$issues.Add("$currenthost $licensename expires in $DaysLeft") 
            } else { write-host $DaysLeft -ForegroundColor Green -NoNewline }
            write-host " days" }
        } else { 
          write-host $license.Name -NoNewLine; write-host " (Expired)" -ForegroundColor red
          [void]$issues.Add("$currenthost $licensename is Expired")
        }
      }
    }
    if ($drivecheck -eq 1){
      foreach ($obj in $item.Dspace) {
        $drive = $obj.DeviceID
        $freespace = $obj.percent
        if ($obj.percent -lt 15 ) { 
          write-host " WARNING - Free space : " -ForegroundColor Red -NoNewline; write-host $obj.DeviceID$obj.percent"%" 
          [void]$issues.Add("$currenthost drive $drive only has $freespace % Free Space")
        } else { 
          write-host " Free space : " -ForegroundColor Yellow -NoNewline; write-host $obj.DeviceID$obj.percent"%" 
        }
      }
    }
    if ($ipcheck -eq 1){
      write-host " Net Profile: " -ForegroundColor Yellow -NoNewline
      $netprofilein = [string]$item.netprofile
      if ($netprofilein -ne "DomainAuthenticated"){
        write-host $netprofilein -ForegroundColor Red 
        [void]$issues.Add("$currenthost Network Profile isn't correct.  Currently set to $netprofilein")
      } else { write-host $netprofilein }
      write-host " IP Address : " -ForegroundColor Yellow -NoNewline
      write-host $item.ip 
    }
    if ($graycheck -eq 1){
      write-host "  Grayspace : " -ForegroundColor Yellow -NoNewline
      if ($item.gray -ne "yes"){
        write-host "Can't Reach Grayspace (redbook.com)" -ForegroundColor Red
        [void]$issues.Add("$currenthost Can't reach Grayspace.")
      } else { write-host "Connected" }
    }
    if ($crowdstrikecheck -eq 1){
      write-host "CrowdStrike : " -ForegroundColor Yellow -NoNewline
      $CSV = $item.CSVer 
      if ($CSV -eq "0.0.0.0"){
        write-host "Not Installed"
        [void] $issues.Add("$currenthost doesn't have Crowd Strike Installed")
      } else { 
        if ($CSV -ne $HighestCSV){ 
          write-host "$CSV "  -ForegroundColor Red -NoNewline
          [void] $warnings.Add("$currenthost has older version of CS installed, shows $CSV, current highest Version found is $HighestCSV")
        } else {
          write-host "$CSV " -ForegroundColor White -NoNewLine
        }
        if ($item.CSRunning -eq "no"){
          write-host "(Not running)" -ForegroundColor Red 
          [void] $issues.Add("$currenthost Crowdstrike process not running")
        } else {
          write-host "(running)" -ForegroundColor White
        }
      }
    }
    if ($sepcheck -eq 1){
      write-host "        SEP : " -ForegroundColor Yellow -NoNewline
      $SEPV = $item.SEPVer
      if ($SEPV -eq "0.0.0.0"){
        write-host "Not Installed"
        [void] $issues.Add("$currenthost doesn't have SEP Installed")
      } else { 
        if ($SEPV -ne $HighestSEPV){ 
          write-host "$SEPV " -ForegroundColor Red -NoNewline
          [void] $warnings.Add("$currenthost has old version of SEP installed, shows $SEPV, current highest Version found is $HighestSEPV")
        } else {
          write-host "$SEPV " -ForegroundColor White -NoNewLine
        }
        if ($item.SEPRunning -eq "no"){
          write-host "(Not running)" -ForegroundColor Red 
          [void] $issues.Add("$currenthost SEP process not running")
        } else {
          write-host "(running)" -ForegroundColor White
        }
      }
    }
    if ($taniumcheck -eq 1){
      write-host "     Tanium : " -ForegroundColor Yellow -NoNewline
      $TMV = $item.TMVer
      if ($TMV -eq "0.0.0.0"){
        write-host "Not Installed"
        [void] $issues.Add("$currenthost doesn't have Tanium Installed")
      } else { 
        if ($TMV -ne $HighestTMV){ 
          write-host "$TMV " -ForegroundColor Red -NoNewline
          [void] $warnings.Add("$currenthost has old version of Taniuum installed, shows $TMV, current highest Version found is $HighestTMV")
        } else {
          write-host "$TMV " -ForegroundColor White -NoNewLine
        }
        if ($item.TMRunning -eq "no"){
          write-host "(Not running)" -ForegroundColor Red 
          [void] $issues.Add("$currenthost Tanium process not running")
        } else {
          write-host "(running)" -ForegroundColor White
        }
      }
    }
  }
  
  # Next list all warnings found
  write-host "`nSummary of Results" -ForegroundColor Green 
  write-host "   $totalalive reachable" -ForegroundColor White
  write-host "   $totaldead unreachable" -ForegroundColor Gray
  if ($warnings -ne $null){
    write-host "The Following warnings were found" -ForegroundColor Yellow
    foreach ($warning in $warnings){
      write-host `t$warning -ForegroundColor White
    }
  } else {
    write-host "No warnings found on reachable systems" -ForegroundColor Green
  }
  # Next list all issues found
  if ($issues -ne $null){
    write-host "The following issues were found" -ForeGroundColor Red
    $netprofilewarning =0
    foreach ($issue in $issues){
      if ($issue -like "*Network Profile*" -and $netprofilewarning -eq 0){
        Write-Host "If Network profile errors show currently set to private, try logging into the system, open powershell and run Get-netconnectionprofile" -ForegroundColor Cyan
        $netprofilewarning=1
      }
      write-host `t$issue -ForegroundColor Yellow
    }   
  } else {
    write-host "No Issues found on reachable systems" -ForegroundColor Green
  }
  # Lastly list any systems that were unreachable.
  if ($deads -ne $null){
    write-host "The following systems were unreachable ($totaldead)" -ForegroundColor Red
    foreach ($system in $deads){
      write-host `t$system -ForegroundColor Magenta
    }
  } else {
    write-host "All Systems were reachable" -ForegroundColor Green
  }
}
#### Range-Check Funtion END ####
function fgpupdate($hostin){
  $self=hostname
  # Check to see if a argument was passed to the script, this allows you to run the script against a specific host, otherwise it will grab all domain computers except itself.
  if ($hostin -eq $NULL){
    $computers = Get-ADComputer -Filter "Name -ne '$self'" | Sort-Object -Property Name
  } else {
    $computers = Get-ADComputer -Filter "Name -eq '$hostin'"
  }
  # Create Arrays to capture parse out what systems are reachable (PSRemoting enabled) and which aren't (PSRemoting Disabled, or unreachable for other reasons)
  $allcomputers = New-Object System.Collections.ArrayList
  $alives = New-Object System.Collections.ArrayList
  $deads = New-Object System.Collections.ArrayList

  # Put all computers found in Get-ADComputer in the all computers array
  $allcomputers += $computers.Name
  # Run a quick check to see which ones are reachable via PS-Remoting.
  write-host "  Getting list of all reachable systems . . ." -NoNewline
  $PScheck = ICM $computers.Name {1} -ErrorAction SilentlyContinue 
  
  # Put all reachable computers into the alives array.
  $alives += $PScheck.PSComputername
  ICM $alives { gpupdate /force }
}
#### GPUpdate Function START ####
#fgpupdate
Range-Check
