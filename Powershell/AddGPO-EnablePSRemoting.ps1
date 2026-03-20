Import-Module GroupPolicy

$GPOName = "Enable-PSRemoting"
$DomainDN = (Get-ADDomain).DistinguishedName

# Create GPO if it doesn't exist
$gpo = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue
if (-not $gpo) {
    $gpo = New-GPO -Name $GPOName -Comment "Enable PowerShell Remoting (Server 2019 compatible)"
}

# --- WinRM Service: Automatic ---
Set-GPRegistryValue -Name $GPOName `
    -Key "HKLM\SYSTEM\CurrentControlSet\Services\WinRM" `
    -ValueName "Start" -Type DWord -Value 2

# --- Allow remote server management through WinRM ---
Set-GPRegistryValue -Name $GPOName `
    -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service" `
    -ValueName "AllowAutoConfig" -Type DWord -Value 1

# Allow IPv4/IPv6 (same as GPO UI: *)
Set-GPRegistryValue -Name $GPOName `
    -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service" `
    -ValueName "IPv4Filter" -Type String -Value "*"

Set-GPRegistryValue -Name $GPOName `
    -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service" `
    -ValueName "IPv6Filter" -Type String -Value "*"

# --- Ensure WinRM starts ---
Set-GPRegistryValue -Name $GPOName `
    -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service" `
    -ValueName "AllowRemoteShellAccess" -Type DWord -Value 1

# --- Firewall (SUPPORTED METHOD for 2019) ---
# Enable predefined WinRM firewall rule via policy
Set-GPRegistryValue -Name $GPOName `
    -Key "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile\Services\WinRM" `
    -ValueName "Enabled" -Type DWord -Value 1

# --- Link GPO if not already linked ---
$link = Get-GPInheritance -Target $DomainDN
if ($link.GpoLinks.DisplayName -notcontains $GPOName) {
    New-GPLink -Name $GPOName -Target $DomainDN -Enforced:$false
}

Write-Host "GPO '$GPOName' configured successfully."
