<#
    WRITTEN BY: Chip McElvain
    VERSION: 4.0 - Generic corp-accounts/corp-groups structure
    CSV Format: FirstName,MiddleInitial,LastName,ADGroup,admin
    Example: John,A,Smith,Engineering,no
#>

## USER VARIABLE EDIT SECTION ####
$FQDN = "galfed.com"
$CompanyName = "Galactic Federation"
$CSVPath = "C:\Users\Administrator\Desktop\SetupScripts\GFUsers.csv"
$RestorePolicy = $true
$Verbose = $true
## END USER VARIABLE EDIT SECTION ####

# Import Active Directory module
Import-Module ActiveDirectory

# Parse FQDN into DC components
$dcParts = $FQDN.Split('.')
$dcPath = $dcParts | ForEach-Object { "DC=$_" } -join ","

#######################################
# PASSWORD POLICY FUNCTIONS
#######################################

function Get-CurrentPasswordPolicy {
    return Get-ADDefaultDomainPasswordPolicy -ErrorAction Stop
}

function Set-WeakPasswordPolicy {
    Write-Host "Setting temporary weak password policy..." -ForegroundColor Yellow
    Set-ADDefaultDomainPasswordPolicy -Identity (Get-ADDefaultDomainPasswordPolicy).Name `
        -MinPasswordLength 1 `
        -PasswordHistoryCount 0 `
        -ComplexityEnabled $false `
        -ReversibleEncryptionEnabled $true `
        -ErrorAction Stop
}

function Restore-PasswordPolicy {
    Write-Host "Restoring default password policy..." -ForegroundColor Yellow
    Set-ADDefaultDomainPasswordPolicy -Identity (Get-ADDefaultDomainPasswordPolicy).Name `
        -MinPasswordLength 8 `
        -PasswordHistoryCount 24 `
        -ComplexityEnabled $true `
        -ReversibleEncryptionEnabled $false `
        -ErrorAction Stop
}

function Test-PasswordPolicyAllowsWeakPasswords {
    $policy = Get-CurrentPasswordPolicy
    $allowsWeak = $true

    if ($policy.MinPasswordLength -gt 6) {
        Write-Host "Password policy requires minimum $($policy.MinPasswordLength) characters (need 6)" -ForegroundColor Yellow
        $allowsWeak = $false
    }

    if ($policy.PasswordComplexityEnabled) {
        Write-Host "Password complexity is enabled (weak passwords may fail)" -ForegroundColor Yellow
        $allowsWeak = $false
    }

    return $allowsWeak
}

#######################################
# BUILD OU PATHS
#######################################

#Generic structure: corp-accounts (users/admins) and corp-groups
$corpAccountsOU = "OU=corp-accounts,$dcPath"
$corpGroupsOU = "OU=corp-groups,$dcPath"
$userAcctPath = "OU=users,$corpAccountsOU"
$adminAcctPath = "OU=admins,$corpAccountsOU"
$groupHomePath = $corpGroupsOU

#######################################
#MAIN SCRIPT
#######################################

Write-Host "=== Active Directory User Creation Script ===" -ForegroundColor Cyan
Write-Host ""

#Check and modify password policy
Write-Host "Checking password policy..." -ForegroundColor Cyan
$originalPolicy = Get-CurrentPasswordPolicy
Write-Host "Current policy: MinLength=$($originalPolicy.MinPasswordLength), Complexity=$($originalPolicy.PasswordComplexityEnabled)" -ForegroundColor Gray

if (-not (Test-PasswordPolicyAllowsWeakPasswords)) {
    Write-Host "Password policy too strict - modifying temporarily..." -ForegroundColor Yellow
    Set-WeakPasswordPolicy
    Write-Host "Temporary policy applied" -ForegroundColor Green
}
else {
    Write-Host "Password policy allows weak passwords" -ForegroundColor Green
}

#Create destination AD Structures
Write-Host ""
Write-Host "Creating Organizational Units..." -ForegroundColor Cyan
New-ADOrganizationalUnit -Name "corp-accounts" -Path $dcPath -ErrorAction SilentlyContinue
New-ADOrganizationalUnit -Name "corp-groups" -Path $dcPath -ErrorAction SilentlyContinue
New-ADOrganizationalUnit -Name "users" -Path $corpAccountsOU -ErrorAction SilentlyContinue
New-ADOrganizationalUnit -Name "admins" -Path $corpAccountsOU -ErrorAction SilentlyContinue

#Create catchall groups
Write-Host "Creating default groups..." -ForegroundColor Cyan
New-ADGroup -Name "IT Support" -GroupScope Global -Path $groupHomePath -ErrorAction SilentlyContinue
New-ADGroup -Name "Executive" -GroupScope Global -Path $groupHomePath -ErrorAction SilentlyContinue

#Import user data
Write-Host ""
Write-Host "Importing users from $CSVPath" -ForegroundColor Cyan
$UserImport = Import-Csv $CSVPath

# Loop through users and create accounts
Write-Host "Creating $($UserImport.Count) user accounts..." -ForegroundColor Cyan
$UserImport | ForEach-Object {
    $givenName = $_.FirstName
    $initial = $_.MiddleInitial
    $surname = $_.LastName
    $fullName = "$givenName $initial $surname"
    $samName = "$($.FirstName).$($.LastName)"
    $email = "$samName@$FQDN"
    $pass = "$($_.LastName)Pass"
    $password = ConvertTo-SecureString $pass -AsPlainText -Force
    $adGroup = $_.ADGroup
    $isAdmin = $_.admin.ToLower()

    # Create standard user account
    New-ADUser `
        -GivenName $givenName `
        -Initials $initial `
        -Surname $surname `
        -Name $fullName `
        -Path $userAcctPath `
        -SamAccountName $samName `
        -EmailAddress $email `
        -AccountPassword $password `
        -ChangePasswordAtLogon $false `
        -PasswordNeverExpires $true `
        -Enabled $true `
        -Office $adGroup `
        -Company $CompanyName `
        -DisplayName $fullName

    if ($Verbose) { Write-Host "Created user: $samName (Password: $pass)" -ForegroundColor Green }

    # Create Domain Admin account if specified
    if ($isAdmin -eq "yes") {
        $adminSam = "$samName.adm"
        $newPass = "$($_.LastName)Admin"
        $adminPass = ConvertTo-SecureString $newPass -AsPlainText -Force

        New-ADUser `
            -Name "$fullName (Admin)" `
            -GivenName $givenName `
            -Initials $initial `
            -Surname $surname `
            -Path $adminAcctPath `
            -SamAccountName $adminSam `
            -AccountPassword $adminPass `
            -ChangePasswordAtLogon $false `
            -PasswordNeverExpires $true `
            -Enabled $true `
            -Description "Domain Admin account for $fullName" `
            -Company $CompanyName `
            -DisplayName "$fullName (Admin)"

        Add-ADGroupMember "Domain Admins" $adminSam
        Add-ADGroupMember "Enterprise Admins" $adminSam
        Add-ADGroupMember "IT Support" $samName

        if ($Verbose) { Write-Host "Created admin account: $adminSam (Password: $newPass)" -ForegroundColor Yellow }
    }

    # Handle group membership based on ADGroup column
    if ($adGroup -eq "Executive") {
        Add-ADGroupMember "Executive" $samName
    }
    elseif (-not (Get-ADGroup -Filter "Name -eq '$adGroup'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $adGroup -GroupScope Global -Path $groupHomePath
        Add-ADGroupMember $adGroup $samName
        if ($Verbose) { Write-Host "Created group: $adGroup" -ForegroundColor Cyan }
    }
    else {
        Add-ADGroupMember $adGroup $samName
    }
}

#cRestore password policy if requested
Write-Host ""
if ($RestorePolicy) {
    Restore-PasswordPolicy
    Write-Host "Password policy restored to defaults" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== User creation complete! ===" -ForegroundColor Green