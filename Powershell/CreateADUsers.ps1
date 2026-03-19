# This script is for adding users to an Active directory
## to keep things simple this script will create their passwords in the following format
##    Domain user account using example of a user named Joe Dirt
##        Login: Firstname.Last  - Joe.Dirt
##        Password: LastnamePass - DirtPass
##    Domain Admin account 
##        Login: Firstname.Lastname.Adm  - Joe.Dirt.Adm
##        Password: LastnameAdmin         - DirtAdmin

########### USER Variables - Change this to match your scenario
$UserOU = "WC-Accounts"
$GroupOU = "WC-Groups"
$OrgName = "Waterlab, Inc" 
$emailTLD = "com"
$usersFilePath = "c:\Users\Administrator\Desktop\RangeManagement\Users.csv"
## Your Users file should be in the example Users.csv format.  
## Note: In the users.csv is a special occupation called SysAdmin - every user that has this listed
## will get two accounts made - one as a normal domain user and one as a domain admin.
## All other Occupations will create a new domain group and the user will be added to that group.
########### END USER Variables 

## First we need to modify the default domain policy to disabled password complexity requirements,
## Eliminate maximum password age requirements and password histroy, and set minimum length to 6.
$domain = Get-ADDomain
Set-ADDefaultDomainPasswordPolicy -Identity $domain.DistinguishedName `
    -MaxPasswordAge ([TimeSpan]::Zero) `
    -MinPasswordLength 6 `
    -ComplexityEnabled $false `
    -PasswordHistoryCount 0
write-host "Default Domain Password Policy updated successfully." -ForegroundColor Green
 # Create destination AD Structures
 $DomainDN = $domain.DistinguishedName
 $SLD = $domain.NetBIOSName
 $UserOUDN = "OU=$UserOU,$DomainDN"
 $GroupOUDN = "OU=$GroupOU,$DomainDN"
if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$UserOUDN'" -ErrorAction SilentlyContinue)){
    New-ADOrganizationalUnit -name $UserOU -path $DomainDN
    New-ADOrganizationalUnit -name "Users" -path $UserOUDN
    New-ADOrganizationalUnit -name "Admins" -path $UserOUDN
}
if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$GroupOUDN'" -ErrorAction SilentlyContinue)){
    New-ADOrganizationalUnit -name $GroupOU -path $DomainDN
}
# Set custom parent AD Paths variables
$useracctpath = "OU=Users,$UserOUDN"
$adminacctpath = "OU=Admins,$UserOUDN"
$grouphomepath = "$GroupOUDN"

# Creatr catchall group for Similar occupations
New-ADGroup -Name "IT support" -GroupScope Global -Path $grouphomepath
New-ADGroup -Name "Executive" -GroupScope Global -Path $grouphomepath

# Grab user data
$UserImport = Import-CSV $UsersFilePath

# Loop through users and create accounts and set group memberships.
$UserImport | ForEach-Object {
  $givenname = $_.Firstname
  $initial = $_.MiddleInitial 
  $surname = $_.LastName
  $fullname = $_.FirstName + " " + $_.MiddleInitial + " " + $_.LastName
  $samname = $_.FirstName + "." + $_.LastName
  $email = $samname + "@" + $SLD + "." + $emailTLD
  $pass = $_.LastName + "Pass"
  $password = (ConvertTo-SecureString $pass -AsPlainText -Force)
  $group = $_.Occupation

  New-ADuser `
   -GivenName $givenname `
   -Initials $initial `
   -Surname $surname `
   -Name $fullname `
   -Path $useracctpath `
   -SamAccountName $samname `
   -EmailAddress $email `
   -AccountPassword $password `
   -ChangePasswordAtLogon $false `
   -PasswordNeverExpires $true `
   -Enabled $true `
   -Office $group `
   -Company $OrgName `
   -DisplayName $fullname `
   -Verbose 

# Check if System Admin, if so create second account for domain admin use.
  if ($_.Occupation -eq "SysAdmin"){
    # Create Domain Admin account - format First.Last.admin
    $adminsam = $samname + ".adm"
    $newpass = $_.LastName + "Admin"
    $displayname = $fullname + "Admin"
    $adminpass = (ConvertTo-SecureString $newpass -AsPlainText -Force)
    New-ADuser `
     -Name $fullname `
     -Path $adminacctpath `
     -SamAccountName $adminsam `
     -AccountPassword $adminpass `
     -ChangePasswordAtLogon $false `
     -PasswordNeverExpires $true `
     -Enabled $true `
     -Description $group `
     -Company $OrgName `
     -DisplayName $displayname `
     -Verbose 
    Add-ADGroupMember "Domain Admins" $adminsam -Verbose
    Add-ADGroupMember "Enterprise Admins" $adminsam -Verbose
    Add-ADGroupMember "IT support" $samname -Verbose
  } 
  ElseIf (-not (Get-ADGroup -Filter "Name -eq '$group'" -ErrorAction SilentlyContinue)){
    New-ADGroup -Name "$group" -GroupScope Global -Path $grouphomepath
    Add-ADGroupMember "$group" $samname -Verbose
  } else {
    Add-ADgroupMember "$group" $samname -Verbose
  }
}

