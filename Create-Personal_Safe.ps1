################################### GET-HELP #############################################
<#
.SYNOPSIS
 	This script will create a new safe based on input from the user or a .csv file.
 
.EXAMPLE
 	.\Create-Personal_Safe.ps1 -bulk $false
	.\Create-Personal_Safe.ps1 -bulk $true -csvPath "C:\temp\onboard.csv"
 
.INPUTS  
	-bulk $true/$false
	-csvPath <Path to .csv containing users to create safes for>
	
.OUTPUTS
	None
	
.NOTES
	AUTHOR:  
	Randy Brown

	VERSION HISTORY:
	1.0 03/19/2019 - Initial release
#>
##########################################################################################

param (
	[Parameter(Mandatory=$true)][bool]$bulk,
	[string]$csvPath
)

######################## IMPORT MODULES/ASSEMBLY LOADING #################################



######################### GLOBAL VARIABLE DECLARATIONS ###################################

$baseURL = "https://components.cyberarkdemo.com"
$PVWAURI = "PasswordVault"

#$ldapDIR = "ActiveDirectory"
$adminGroup = "CyberarkVaultAdmins"

#$address = "cyberarkdemo.com"
$deviceType = "Operating System"
$platformId = "WinDomain"
$cpmUser = "PasswordManager"

$finalURL = $baseURL + "/" + $PVWAURI
$errorOccured = $false

########################## START FUNCTIONS ###############################################

Function EPV-Login($user, $pass) {
	$data = @{
		username=$user
		password=$pass
		useRadiusAuthentication=$false
	}

	$loginData = $data | ConvertTo-Json

	Try {
		Write-Host "Logging into EPV as $user..." -NoNewLine
		
		$ret = Invoke-RestMethod -Uri "$finalURL/WebServices/auth/Cyberark/CyberArkAuthenticationService.svc/Logon" -Method Post -Body $loginData -ContentType 'application/json'		
		
		Write-Host "Success!" -ForegroundColor Green
	} Catch {
		ErrorHandler "Login was not successful" $_.Exception.Message $_ $false
	}
	return $ret
}

Function EPV-Logoff {
	Try {
		Write-Host "Logging off..." -NoNewline		
		
		Invoke-RestMethod -Uri "$finalURL/WebServices/auth/Cyberark/CyberArkAuthenticationService.svc/Logoff" -Method POST -Headers $header -ContentType 'application/json'
		
		Write-Host "Logged off!" -ForegroundColor Green
	} Catch {
		ErrorHandler "Log off was not successful" $_.Exception.Message $_ $false
	}
}

Function EPV-GetAPIAccount {
	$ret = Invoke-RestMethod -Uri "$baseURI/AIMWebService/api/Accounts?AppID=UnlockUser&Safe=Unlock Users&Object=UserUnlock" -Method GET -ContentType 'application/json'

	return $ret
}

Function EPV-CreateSafe($safeName, $description) {
	$safeExists = $false
	
	$existingSafes = Invoke-RestMethod -Uri "$finalURL/WebServices/PIMServices.svc/Safes?query=$safeName" -Method Get -Headers $header -ContentType 'application/json'
	
	ForEach ($sName in $existingSafes.SearchSafesResult.SafeName) {
		If ($sName.ToLower() -eq $safeName.ToLower()) {
			$safeExists = $true
		}
	}
	
	If (!($safeExists)) {		
		$data = @{
			safe = @{
				SafeName=$safeName
				Description=$description
				OLACEnabled=$false
				ManagingCPM=$cpmUser
				NumberOfVersionsRetention=5
			}
		}		
		$data = $data | ConvertTo-Json
		
		Try {
			Write-Host "Safe $safeName does not exist creating it..." -NoNewline
			$ret = Invoke-RestMethod -Uri "$finalURL/WebServices/PIMServices.svc/Safes" -Method Post -Body $data -Headers $header -ContentType 'application/json'
		
			If ($ret.safe.SafeName.ToLower() -eq $safeName.ToLower()) {
				Write-Host "Success" -ForegroundColor Green
			} Else {
				Write-Host "Safe $safeName was not created" -ForegroundColor Red
			}
		} Catch {
			ErrorHandler "Something went wrong, $safeName was not created" $_.Exception.Message $_ $true
		}
	} Else {
		Write-Host "Safe $safeName exists skipping creation" -ForegroundColor Yellow
	}
}

Function EPV-AddSafeMember($owner, $permsType) {
    $userExists = $false
	
	Try {
		Write-Host "Getting members of $safeToCreate..." -NoNewline
		$existingUser = Invoke-RestMethod -Uri "$finalURL/WebServices/PIMServices.svc/Safes/$safeToCreate/Members" -Method Get -Headers $header -ContentType 'application/json'
		Write-Host "Sucess" -ForegroundColor Green
	} Catch {
		ErrorHandler "Something went wrong, $owner was not added as a member of $safeToCreate..." $_.Exception.Message $_ $true
	}
	
	Write-Host "Parsing safe members..."
	ForEach ($user in $existingUser.members.UserName) {
		If ($user.ToLower() -like $owner.ToLower()) {
			Write-Host "User $owner is already a member..." -ForegroundColor Yellow
			$userExists = $true
		}
	}
	
	If (!($userExists)) {
		$body = (Get-SafePermissions $owner $permsType)
		$body = $body -replace '\s',''
		
		Try {
			Write-Host "Adding $owner as member of $safeToCreate..." -NoNewline
			
			$ret = Invoke-RestMethod -Uri "$finalURL/WebServices/PIMServices.svc/Safes/$safeToCreate/Members" -Method Post -Body $body -Headers $header -ContentType 'application/json'
			
			Write-Host "Success" -ForegroundColor Green
		} Catch {			
			ErrorHandler "Something went wrong, $owner was not added as a member of $safeToCreate..." $_.Exception.Message $_ $true
		}
	}
}

Function EPV-DeleteSafeMemeber($safe, $safeMember) {
	Try {
		Write-Host "Removing $safeMember from $safe..." -NoNewline
		
		Invoke-RestMethod -Uri "$finalURL/WebServices/PIMServices.svc/Safes/$safe/Members/$safeMember" -Method Delete -ContentType 'application/json' -Headers $header
		
		Write-Host "Success" -ForegroundColor Green
	} Catch {
		ErrorHandler "Something went wrong, $safeMember was not removed from $safe." $_.Exception.Message $_ $true
	}
}

Function Get-SafePermissions($owner, $type, $DIR) {
	Switch ($type.ToLower()) {
		"all" { $PERMISSIONS = @{
				member = @{
					MemberName="$owner"
					SearchIn="$DIR"
					MembershipExpirationDate=""
					Permissions = @(
						@{Key="UseAccounts"
						Value=$true}
						@{Key="RetrieveAccounts"
						Value=$true}
						@{Key="ListAccounts"
						Value=$true}
						@{Key="AddAccounts"
						Value=$true}
						@{Key="UpdateAccountContent"
						Value=$true}
						@{Key="UpdateAccountProperties"
						Value=$true}
						@{Key="InitiateCPMAccountManagementOperations"
						Value=$true}
						@{Key="SpecifyNextAccountContent"
						Value=$true}
						@{Key="RenameAccounts"
						Value=$true}
						@{Key="DeleteAccounts"
						Value=$true}
						@{Key="UnlockAccounts"
						Value=$true}
						@{Key="ManageSafe"
						Value=$true}
						@{Key="ManageSafeMembers"
						Value=$true}
						@{Key="BackupSafe"
						Value=$true}
						@{Key="ViewAuditLog"
						Value=$true}
						@{Key="ViewSafeMembers"
						Value=$true}
						@{Key="RequestsAuthorizationLevel"
						Value=0}
						@{Key="AccessWithoutConfirmation"
						Value=$true}
						@{Key="CreateFolders"
						Value=$true}
						@{Key="DeleteFolders"
						Value=$true}
						@{Key="MoveAccountsAndFolders"
						Value=$true}
					)
				}
			}
			$PERMISSIONS = $PERMISSIONS | ConvertTo-Json -Depth 3
			return $PERMISSIONS; break }
		"admin" { $PERMISSIONS = @{
				member = @{
					MemberName="$owner"
					SearchIn="$DIR"
					MembershipExpirationDate=""
					Permissions = @(
						@{Key="UseAccounts"
						Value=$false}
						@{Key="RetrieveAccounts"
						Value=$false}
						@{Key="ListAccounts"
						Value=$true}
						@{Key="AddAccounts"
						Value=$true}
						@{Key="UpdateAccountContent"
						Value=$false}
						@{Key="UpdateAccountProperties"
						Value=$true}
						@{Key="InitiateCPMAccountManagementOperations"
						Value=$true}
						@{Key="SpecifyNextAccountContent"
						Value=$false}
						@{Key="RenameAccounts"
						Value=$false}
						@{Key="DeleteAccounts"
						Value=$true}
						@{Key="UnlockAccounts"
						Value=$true}
						@{Key="ManageSafe"
						Value=$true}
						@{Key="ManageSafeMembers"
						Value=$true}
						@{Key="BackupSafe"
						Value=$true}
						@{Key="ViewAuditLog"
						Value=$true}
						@{Key="ViewSafeMembers"
						Value=$true}
						@{Key="RequestsAuthorizationLevel"
						Value=0}
						@{Key="AccessWithoutConfirmation"
						Value=$false}
						@{Key="CreateFolders"
						Value=$true}
						@{Key="DeleteFolders"
						Value=$true}
						@{Key="MoveAccountsAndFolders"
						Value=$true}
					)
				}
			}
			$PERMISSIONS = $PERMISSIONS | ConvertTo-Json -Depth 3
			return $PERMISSIONS; break }
	}
}

Function EPV-AddAccount($address) {
	$name = $deviceType + "-" + $platformId + "-" + $address + "-" + $safeToCreate
	
	$data = @{
		account = @{
			safe=$safeToCreate
			platformID=$platformId
			address=$address
			accountName=$name
			password="Sup3r5ecretP@ssword!"
			username=$priv
			disableAutoMgmt=$false		
		}
	}
	
	$data = $data | ConvertTo-Json
	
	Try {
		Write-Host "Vaulting account $priv..." -NoNewline
		
		$ret = Invoke-RestMethod -Uri "$finalURL/WebServices/PIMServices.svc/Account" -Method Post -Body $data -Headers $header -ContentType 'application/json'
		
		Write-Host "Success" -ForegroundColor Green
	} Catch {		
		ErrorHandler "Something went wrong, $priv was not vaulted..." $_.Exception.Message $_ $true
	}
}

Function ErrorHandler($message, $exceptionMessage, $fullMessage, $logoff) {
	Write-Host $message -ForegroundColor Red
	Write-Host "Exception Message:"
	Write-Host $exceptionMessage -ForegroundColor Red
	Write-Host "Full Error Message:"
	Write-Host $fullMessage -ForegroundColor Red
	Write-Host "Stopping script" -ForegroundColor Yellow
	
	If ($logoff) {
		EPV-Logoff
	}
	Exit 1
}

Function MAIN($mortal, $privAccount, $safeDescription, $address, $user, $ldapDIR) {
	EPV-CreateSafe $mortal $safeDescription

	EPV-AddSafeMember $mortal "all"
	
	EPV-AddSafeMember $adminGroup "admin"
	
	EPV-AddAccount $address
	
	EPV-DeleteSafeMemeber $mortal $user
	
	Write-Host "Script complete!"
}

########################## END FUNCTIONS #################################################

########################## MAIN SCRIPT BLOCK #############################################

#$cred = EPV-GetAPIAccount
#$user = $cred.UserName
#$user = "Safe_Creator"
Write-Host "Please log into EPV;"
$user = Read-Host "EPV User Name"
$securePassword = Read-Host "Password" -AsSecureString

$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
$unsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

$login = EPV-Login $user $unsecurePassword
$unsecurePassword = ""
#$login = EPV-Login $cred.UserName $cred.Content
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Authorization", $login.CyberArkLogonResult)

If ($bulk) {
	$csvObject = (Import-Csv $csvPath)
	
	ForEach ($item in $csvObject) {
		$safeToCreate = $item.Name
		$priv = $item."Privliged Account"
		$addy = $item.Domain
		$ldapDIR = $item.dirMap
		$description = "Personal safe for " + $safeToCreate + "."
		
		MAIN $safeToCreate $priv $description $addy $user $ldapDIR
	}
} Else {
	$safeToCreate = Read-Host "What is the name of the user that needs the safe"
	$priv = Read-Host "What is the privliged account for this user to be stored in the safe"
	$addy = Read-Host "What is the full domain the privliged account is in (EX: cyberarkdemo.com)"
	$ldapDIR = Read-Host "What is the Directory map name the user in"
	$description = "Personal safe for " + $safeToCreate + "."
	
	MAIN $safeToCreate $priv $description $addy $user $ldapDIR
}

EPV-Logoff

########################### END SCRIPT ###################################################