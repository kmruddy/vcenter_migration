###################################################
## vCenter Granual Migration Wizard
## VMworld Hackathon Team
##
$Version = "1.0"
$LastUpdated = "08/29/2017"

$ProgramDescription = "Assists with partial vCenter Migrations of specific items/objects"
$ProgramName = "vCenter Granular Migration Wizard"

$MigrationChoices = `
'vCenter Server Settings',`
'vCenter Alarm Migration',`
'VIRole Migration',`
'Folder Migration',`
'Permissions Migration',`
'Custom Attribute Migration',`
'Customization Spec Migration',`
'vSphere Tag Migration',`
'VUM Baseline Migration',`
'Distritubed Switch Migration',`
'Cluster Attribute Migration',`
'Exit'


#region Check System Requirements and Set PowerCLIConfig
if (!(Get-Module VMware.PowerCLI)) {
	Write-Host "[Loading PowerCLI]" -ForegroundColor Cyan
	Import-Module VMware.PowerCLI
}

# Setting PowerCLI Configuration and Load Additional Modules
try {
	Disconnect-VIServer * -Force -Confirm:$false -ErrorAction Ignore
} catch {}

Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -InvalidCertificateAction Ignore -Scope Session -Confirm:$false
#endregion

#region Helper Functions
###################################################################################
# Get-Selection : Takes a simple description and an array of objects to choose
###################################################################################
Function Get-Selection {
	[cmdletbinding()]
	param(
		[Parameter(Position=0, Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[String]$SelectionTitle,
		[Parameter(Position=1, Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		$SelectionList,
		[Parameter(Position=2)]
		$SelectionProperty,
		[Parameter(Position=3)]
		$Default
	)
	Write-Host $('*' * ($SelectionTitle.length + 2)) -ForegroundColor Cyan
	Write-Host " $SelectionTitle " -ForegroundColor Cyan
	Write-Host $('*' * ($SelectionTitle.length + 2 )) -ForegroundColor Cyan
	$MenuCount = 0
	foreach ($Item in $SelectionList) {
		## Add index
		$MenuCount++
		$SelectionList[$MenuCount-1] | Add-Member -MemberType noteproperty -Name ItemIndex -Value $MenuCount -Force
		
		## Build out MenuLine
		if (($SelectionProperty) -and ($Item.$SelectionProperty)) {
			Write-Host " $MenuCount`:".padright(3) "$($Item.$SelectionProperty)"
		} else {
			Write-Host " $MenuCount`:".padright(3) "$Item"
		}
	}
	Write-Host $('*' * ($SelectionTitle.length + 2)) -ForegroundColor Cyan
	Do {
		try {
			[int]$Selection = Read-Host "Choose an option from above (1-$MenuCount)[$Default]"
		} catch {}
		
		if (($Selection -eq "") -and ($Default)) {
			$Selection = $Default
		}

	} until (($Selection -ge 1) -and ($Selection -le $MenuCount))
	$SelectedItem = $SelectionList[$Selection-1]
	
	return $SelectedItem
}

###################################################################################
# Get-YesNo : Asks a y/n question and returns True/False based on response
###################################################################################
Function Get-YesNo {
	param(
		[Parameter(Position=0, Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[String]$Question,
		[Parameter(Position=1)]
		[ValidateNotNullOrEmpty()]
		[String]$Default
	)
	
	Do {
		$Answer = Read-Host "$Question (y/n)[$Default]"
		if (($Answer -eq "") -and ($Default)) {
			$Answer = "$Default"
		}
		switch ($Answer) {
			'y' { Return $true }
			'n' { Return $false }
			default { $Answer = $null }
		}
	} while ($Answer -eq $null)
}

#endregion



$MigrationData = "MigrationData"

########################################
## MAIN Section
########################################
Clear-Host
Write-Host "*************************************************" -ForegroundColor Green
Write-Host "** " -f Green -NoNewline ; Write-Host "$ProgramName" -ForegroundColor Cyan
Write-Host "** " -f Green -NoNewline ; Write-Host "Version:     $Version                        " -ForegroundColor Cyan
Write-Host "** " -f Green -NoNewline ; Write-Host "Last Update: $LastUpdated                    " -ForegroundColor Cyan
Write-Host "*************************************************" -ForegroundColor Green
Write-Host 
Write-Host  "WHAT THIS PROGRAM DOES:" -ForegroundColor Yellow
Write-Host 
Write-Host  "> $ProgramDescription"
Write-Host
Write-Host  "*******************************************************************************************" -ForegroundColor Green
Read-Host "Press <Enter> to begin"

## Connect to SOURCE and TARGET vCenters
Do {
	$SourceVC = Connect-VIServer (Read-Host "Type SOURCE vCenter") -User none
} while (!$SourceVC)

Do {
	$TargetVC = Connect-VIServer (Read-Host "Type TARGET vCenter") -User none
} while (!$TargetVC)

Do {
	## Select Migration Action
	Clear-Host
	$MigrationChoice = Get-Selection -SelectionTitle 'Please Select a migration action' -SelectionList $MigrationChoices
	Clear-Host
	
	switch -wildcard ($MigrationChoice) {
		VIRole* {
			Write-Host '[Launching VIRole Migration Wizard]' -ForegroundColor Cyan
			$SubScript = "./Module-RoleMigration.ps1"
			. $SubScript
		}
		
		Folder* {
			Write-Host '[Launching Folder Migration Wizard]' -ForegroundColor Cyan
			$SubScript = "./Module-FolderMigration.ps1"
			. $SubScript
		}
		
		
		
		Permissions* {
			Write-Host '[Launching Permissions Migration Wizard]' -ForegroundColor Cyan
			
		}
		
		Cluster* {
			Write-Host '[Launching Cluster Migration Wizard]' -ForegroundColor Cyan
		
		}
		
		default { Write-Host '[Exiting]' -ForegroundColor Cyan }
	}
} while ($MigrationChoice -ne 'Exit')

