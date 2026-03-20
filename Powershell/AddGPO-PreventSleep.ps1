# ============================
# CONFIG
# ============================
$GpoName = "Disable Sleep and Hibernate"
$OuName  = "Workstations"   # Only thing you change

# Auto-detect OU DN
$OuDn = (Get-ADOrganizationalUnit -LDAPFilter "(name=$OuName)").DistinguishedName

# ============================
# CREATE GPO
# ============================
$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
if (-not $gpo) {
    $gpo = New-GPO -Name $GpoName -Comment "Disables disk sleep, system sleep, standby, hibernation, and display timeout"
}

# ============================
# DISABLE DISK SLEEP
# ============================
Set-GPRegistryValue -Name $GpoName `
  -Key "HKLM\Software\Policies\Microsoft\Power\PowerSettings\4f971e89-eebd-4455-a8de-9e59040e7347\6738e2c4-e8a5-4a42-b16a-e040e769756e" `
  -ValueName "ACSettingIndex" -Type DWord -Value 0

Set-GPRegistryValue -Name $GpoName `
  -Key "HKLM\Software\Policies\Microsoft\Power\PowerSettings\4f971e89-eebd-4455-a8de-9e59040e7347\6738e2c4-e8a5-4a42-b16a-e040e769756e" `
  -ValueName "DCSettingIndex" -Type DWord -Value 0

# ============================
# DISABLE SYSTEM SLEEP
# ============================
Set-GPRegistryValue -Name $GpoName `
  -Key "HKLM\Software\Policies\Microsoft\Power\PowerSettings\238C9FA8-0AAD-41ED-83F4-97BE242C8F20\29F6C1DB-86DA-48C5-9FDB-F2B67B1F44DA" `
  -ValueName "ACSettingIndex" -Type DWord -Value 0

Set-GPRegistryValue -Name $GpoName `
  -Key "HKLM\Software\Policies\Microsoft\Power\PowerSettings\238C9FA8-0AAD-41ED-83F4-97BE242C8F20\29F6C1DB-86DA-48C5-9FDB-F2B67B1F44DA" `
  -ValueName "DCSettingIndex" -Type DWord -Value 0

# ============================
# DISABLE STANDBY (S1–S3)
# ============================
Set-GPRegistryValue -Name $GpoName `
  -Key "HKLM\Software\Policies\Microsoft\Windows\System\Power" `
  -ValueName "StandbyAllowed" -Type DWord -Value 0

# ============================
# DISABLE HIBERNATION TIMEOUT
# ============================
Set-GPRegistryValue -Name $GpoName `
  -Key "HKLM\Software\Policies\Microsoft\Power\PowerSettings\238C9FA8-0AAD-41ED-83F4-97BE242C8F20\9D7815A6-7EE4-497E-8888-515A05F02364" `
  -ValueName "ACSettingIndex" -Type DWord -Value 0

Set-GPRegistryValue -Name $GpoName `
  -Key "HKLM\Software\Policies\Microsoft\Power\PowerSettings\238C9FA8-0AAD-41ED-83F4-97BE242C8F20\9D7815A6-7EE4-497E-8888-515A05F02364" `
  -ValueName "DCSettingIndex" -Type DWord -Value 0

# ============================
# DISABLE DISPLAY TIMEOUT
# ============================
Set-GPRegistryValue -Name $GpoName `
  -Key "HKLM\Software\Policies\Microsoft\Power\PowerSettings\7516b95f-f776-4464-8c53-06167f40cc99\3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e" `
  -ValueName "ACSettingIndex" -Type DWord -Value 0

Set-GPRegistryValue -Name $GpoName `
  -Key "HKLM\Software\Policies\Microsoft\Power\PowerSettings\7516b95f-f776-4464-8c53-06167f40cc99\3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e" `
  -ValueName "DCSettingIndex" -Type DWord -Value 0

# ============================
# DEPLOY STARTUP SCRIPT: powercfg -h off
# ============================
$SysVolPath = "\\$env:USERDNSDOMAIN\SYSVOL\$env:USERDNSDOMAIN\Scripts"
$ScriptPath = Join-Path $SysVolPath "DisableHibernate.ps1"

if (-not (Test-Path $ScriptPath)) {
    Set-Content -Path $ScriptPath -Value 'powercfg.exe -h off'
}

Set-GPRegistryValue -Name $GpoName `
  -Key "HKLM\Software\Policies\Microsoft\Windows\System\Scripts\Startup\0" `
  -ValueName "Script" -Type String -Value "DisableHibernate.ps1"

# ============================
# LINK GPO
# ============================
New-GPLink -Name $GpoName -Target $OuDn -LinkEnabled Yes
