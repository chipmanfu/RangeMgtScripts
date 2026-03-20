Import-Module GroupPolicy

$GPOName = "Prevent-Sleep"
$DomainDN = (Get-ADDomain).DistinguishedName

# Create GPO if it doesn't exist
$gpo = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue
if (-not $gpo) {
    $gpo = New-GPO -Name $GPOName -Comment "Prevent sleep/hibernate for lab VMs"
}

# Power policy GUIDs (standard across Windows)
$PowerKey = "HKLM\SOFTWARE\Policies\Microsoft\Power\PowerSettings"

# --- Sleep Settings ---
# Sleep after (plugged in) = 0 (never)
Set-GPRegistryValue -Name $GPOName `
    -Key "$PowerKey\238C9FA8-0AAD-41ED-83F4-97BE242C8F20\29F6C1DB-86DA-48C5-9FDB-F2B67B1F44DA" `
    -ValueName "ACSettingIndex" -Type DWord -Value 0

# Sleep after (battery) = 0 (never)
Set-GPRegistryValue -Name $GPOName `
    -Key "$PowerKey\238C9FA8-0AAD-41ED-83F4-97BE242C8F20\29F6C1DB-86DA-48C5-9FDB-F2B67B1F44DA" `
    -ValueName "DCSettingIndex" -Type DWord -Value 0

# --- Hibernate = Disabled ---
Set-GPRegistryValue -Name $GPOName `
    -Key "HKLM\SYSTEM\CurrentControlSet\Control\Power" `
    -ValueName "HibernateEnabled" -Type DWord -Value 0

# --- Turn off display (optional but useful for labs) ---
# Set to 0 = never
Set-GPRegistryValue -Name $GPOName `
    -Key "$PowerKey\7516B95F-F776-4464-8C53-06167F40CC99\3C0BC021-C8A8-4E07-A973-6B14CBCB2B7E" `
    -ValueName "ACSettingIndex" -Type DWord -Value 0

Set-GPRegistryValue -Name $GPOName `
    -Key "$PowerKey\7516B95F-F776-4464-8C53-06167F40CC99\3C0BC021-C8A8-4E07-A973-6B14CBCB2B7E" `
    -ValueName "DCSettingIndex" -Type DWord -Value 0

# --- Link GPO if not already linked ---
$link = Get-GPInheritance -Target $DomainDN
if ($link.GpoLinks.DisplayName -notcontains $GPOName) {
    New-GPLink -Name $GPOName -Target $DomainDN -Enforced:$false
}

Write-Host "GPO '$GPOName' configured successfully."
