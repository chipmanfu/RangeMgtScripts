# Variables
$GpoName = "Enable PowerShell Remoting"
$OuDn = "OU=Servers,DC=yourdomain,DC=com"

# Create GPO
$gpo = New-GPO -Name $GpoName -Comment "Enables WinRM for PowerShell Remoting"

# Enable WinRM service
Set-GPRegistryValue -Name $GpoName `
  -Key "HKLM\Software\Policies\Microsoft\Windows\WinRM\Service" `
  -ValueName "AllowAutoConfig" -Type DWord -Value 1

# Allow remote management
Set-GPRegistryValue -Name $GpoName `
  -Key "HKLM\Software\Policies\Microsoft\Windows\WinRM\Service" `
  -ValueName "AllowUnencryptedTraffic" -Type DWord -Value 0

# Enable listeners
Set-GPRegistryValue -Name $GpoName `
  -Key "HKLM\Software\Policies\Microsoft\Windows\WinRM\Service\WinRM" `
  -ValueName "IPv4Filter" -Type String -Value "*"

# Firewall exception
Set-GPRegistryValue -Name $GpoName `
  -Key "HKLM\Software\Policies\Microsoft\Windows\Firewall\DomainProfile\AuthorizedApplications\List" `
  -ValueName "WinRM" -Type String -Value "%SystemRoot%\system32\svchost.exe:LocalSubnet:Enabled:WinRM"

# Link GPO
New-GPLink -Name $GpoName -Target $OuDn -LinkEnabled Yes
