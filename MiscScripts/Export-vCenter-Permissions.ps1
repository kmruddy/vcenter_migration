<#
.SYNOPSIS
Export vCenter permissions for purposes of migration or backup
To be used with Import-vCenter-Permissions.ps1

.DESCRIPTION
The script produces a json file containing all permissions entries for the given vCenter
(except for vCenter-instance specific vpxd/vsphere-webclient entries which are automatically created in a new vCenter)

.PARAMETER VIServer
Specifies the vCenter FQDN

.NOTES
Authors: Mark Wolfe and Scott Haas
Website: www.definebroken.com

Changelog:
6-July-2017
 * Initial Script
24-Aug-2017
 * Adjusted script for public consumption on github

Todo:
 * Folder and VM Objects are not yet working for import. Full path logic is needed since duplicates can exist.

.EXAMPLE
Export all permissions for vCenter vcenter.domain.com

PS> Export-vCenter-Permissions.ps1 -VIServer vcenter.domain.com

.LINK
Reference: https://github.com/ScottHaas/vcenter-migration-scripts

#>
[CmdletBinding()]
Param(
  [Parameter(Mandatory=$true, Position=0, HelpMessage="FQDN of vCenter")]
  [ValidateNotNullOrEmpty()]
  [string]$VIServer
)

$PermissionsOut = @()
$FolderTypes = "VM","HostAndCluster","Network","Datastore"  # Array of valid folder types
$SystemFolderNames = "vm","host","datastore","network"      # Array of system folder names automatically created inside each datacenter
$VIServerShortName = $VIServer.Split(".")[0]
$FileDate = Get-Date -Format FileDate  
$ExportFileName = $VIServerShortName + "-permissions-" + $FileDate + ".json"

Write-Host "`n`nConnecting to $VIServer..."
Connect-VIServer -Server $VIServer -ErrorAction Stop
Write-Host "`n`n"
Write-Host "Gathering Permissions...`n`n"

$PermissionsIn = Get-VIPermission

foreach ($Permission in $PermissionsIn){
    
    $i++
    $ThisPermType = $Permission.EntityID.Split("-")[0]
    $CurrentOperation = $ThisPermType + ": " + $Permission.Entity.Name
    Write-Progress -activity "Gathering Permissions..." -CurrentOperation $CurrentOperation -PercentComplete (($i / $PermissionsIn.count)  * 100)

    if (($Permission.Principal -like "VSPHERE.LOCAL\vpxd-*") -or ($Permission.Principal -like "VSPHERE.LOCAL\vsphere-webclient-*")){
        Write-Host "Skipping" $Permission.Principal "entry; not applicable to new vCenter"
        Continue
        }

    $ThisPerm = New-Object -TypeName PsObject
    $ThisPerm | Add-Member -MemberType NoteProperty -Name Entity -Value $Permission.Entity.Name
    $ThisPerm | Add-Member -MemberType NoteProperty -Name Type -Value $ThisPermType
    $ThisPerm | Add-Member -MemberType NoteProperty -Name Principal -Value $Permission.Principal
    $ThisPerm | Add-Member -MemberType NoteProperty -Name Propagate -Value $Permission.Propagate
    $ThisPerm | Add-Member -MemberType NoteProperty -Name Role -Value $Permission.Role

    if ($ThisPerm.Type -eq "DistributedVirtualPortGroup"){
        $VDPG = Get-VDPortgroup -Id $Permission.EntityID
        $ThisPerm | Add-Member -MemberType NoteProperty -Name VDSwitch -Value $VDPG.VDSwitch.Name
        $ThisPerm | Add-Member -MemberType NoteProperty -Name Path -Value "Use DVSWitch to identify"
        }

    elseif ($ThisPerm.Type -in "Datacenter","HostSystem","ClusterComputeResource","StoragePod","Datastore"){
        $ThisPerm | Add-Member -MemberType NoteProperty -Name Path -Value "Object type has globally unique names, path not needed"
        }
    elseif ($ThisPerm.Type -in "Folder"){
        
        # If the folder is the root "Datacenters" default folder (i.e. root vCenter permission), then set path to vCenterRoot
        if ($ThisPerm.Entity -like "Datacenters" -and $Permission.EntityId -like "Folder-group-d1"){
            $ThisPerm | Add-Member -MemberType NoteProperty -Name Path -Value "vCenterRoot"
            }
        }
    elseif ($ThisPerm.Type -in "VirtualMachine"){
        
        $ThisPerm | Add-Member -MemberType NoteProperty -Name Path -Value "NeedsAPath"
        }
    
    else {
        Write-Host "Error; Object Type $ThisPermType not accounted for or exported."
        }

    $PermissionsOut += $ThisPerm
}

Write-Host -ForegroundColor Green "Writing Permissions to $ExportFileName...`n`n"
$PermissionsOut | Sort-Object Type, Entity, Principal, VDSwitch | ConvertTo-Json | Out-File $ExportFileName

Write-Host "Disconnecting from $VIserver..."
Disconnect-VIServer -Server $VIServer -Confirm:$False