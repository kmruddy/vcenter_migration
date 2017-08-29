<#
.SYNOPSIS
Imports vCenter permissions for purposes of migration or backup
To be used with Export-vCenter-Permissions.ps1

.DESCRIPTION
The script imports a json file containing all permissions entries for the given vCenter and applies those permissions if they do not exist

.PARAMETER VIServer
Specifies the vCenter FQDN

.PARAMETER ImportFile
Specifies the JSON file to import settings from

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
 * Script will alert to the skipped folder and vm objects

.EXAMPLE
Import all permissions for vCenter vcenter.domain.com

PS> Import-vCenter-Permissions.ps1 -VIServer vcenter.domain.com -ImportFile vCenter-permissions-20170824.json

.LINK
Reference: https://github.com/ScottHaas/vcenter-migration-scripts

#>
[CmdletBinding()]
Param(
  [Parameter(Mandatory=$true, Position=0, HelpMessage="FQDN of vCenter")]
  [ValidateNotNullOrEmpty()]
  [string]$VIServer,
  [Parameter(Mandatory=$true, Position=1, HelpMessage="Which file to import permissions from?")]
  [ValidateNotNullOrEmpty()]
  [string]$ImportFile
)

if ((Test-Path $ImportFile) -eq $false){
    Write-Host -ForegroundColor Red "Import file $ImportFile not found.  Please check filename.  Exiting..."
    Exit
    }

Write-Host "`n`nConnecting to $VIServer..."
Connect-VIServer -Server $VIServer -ErrorAction Stop
Write-Host "`n`n"

$ImportedPermissions = Get-Content $ImportFile | ConvertFrom-Json

Write-Host "`nImporting permissions from $ImportFile to $VIserver...`n`n"


foreach ($Permission in $ImportedPermissions){

    # If permission is on a Datacenter, Host, Cluster, Datastore Cluster, or Datastore
    #   Objects are uniquely named, so no special work is needed to identify their path or parent objects
    if ($Permission.Type -in "Datacenter","HostSystem","ClusterComputeResource","StoragePod","Datastore"){

        Switch ($Permission.Type){
            Datacenter {$Entity = Get-Datacenter $Permission.Entity -ErrorAction SilentlyContinue}
            HostSystem {$Entity = Get-VMHost $Permission.Entity -ErrorAction SilentlyContinue}
            ClusterComputeResource {$Entity = Get-Cluster $Permission.Entity -ErrorAction SilentlyContinue}
            StoragePod {$Entity = Get-DatastoreCluster $Permission.Entity -ErrorAction SilentlyContinue}
            Datastore {$Entity = Get-Datastore $Permission.Entity -ErrorAction SilentlyContinue}
            }
            
        if ($Entity -eq $null){
            Write-Host -ForegroundColor Yellow "  SKIPPED - Object" $Permission.Entity "does not exist; cannot create permission for" $Permission.Principal "with role" $Permission.Role
            Continue
            }

        $VerifyPermission = Get-VIPermission -entity $Permission.Entity | Where-Object {($_.Entity.Name -eq $Permission.Entity) -and ($_.Role -eq $Permission.Role) -and ($_.Principal -eq $Permission.Principal)}
        
        if ($VerifyPermission -eq $null){
            New-VIPermission -Entity $Entity -Principal $Permission.Principal -Role $Permission.Role -Propagate $Permission.Propagate -WarningAction SilentlyContinue | Out-Null
            Write-Host -ForegroundColor Green "ADDED - Permission entry on" $Permission.Type "-" $Permission.Entity "for" $Permission.Principal "with role" $Permission.Role "and propagation" $Permission.Propagate 
            }

        else {
        Write-Host "  VERIFIED - Permission entry on" $Permission.Type "-" $Permission.Entity "for" $Permission.Principal "with role" $Permission.Role "and propagation" $Permission.Propagate "already exists"
        }
    }

    # If permission is on a Distributed Virtual Port Group
    #   DVPGs can have the same name in different datacenters, so we need to identify their parent VDSwitch
    elseif ($Permission.Type -eq "DistributedVirtualPortGroup"){
        $Entity = Get-VDSwitch $Permission.VDSwitch -ErrorAction SilentlyContinue | Get-VDPortgroup $Permission.Entity -ErrorAction SilentlyContinue
        
        if ($Entity -eq $null){
            Write-Host -ForegroundColor Yellow "  SKIPPED - Object" $Permission.Entity "on" $Permission.VDSwitch "does not exist; cannot create permission for" $Permission.Principal "with role" $Permission.Role
            Continue
            }
        
        $VerifyPermission = Get-VIPermission -entity $Entity | Where-Object {($_.Entity.Name -eq $Permission.Entity) -and ($_.Role -eq $Permission.Role) -and ($_.Principal -eq $Permission.Principal)}

        if ($VerifyPermission -eq $null){
            New-VIPermission -Entity $Entity -Principal $Permission.Principal -Role $Permission.Role -Propagate $Permission.Propagate -WarningAction SilentlyContinue | Out-Null
            Write-Host -ForegroundColor Green "ADDED - Permission entry on DVPG" $Permission.Entity "on" $Permission.VDSwitch "for" $Permission.Principal "with role" $Permission.Role "and propagation" $Permission.Propagate 
            }
       
        else {
            Write-Host "  VERIFIED - Permission entry on on DVPG" $Permission.Entity "on" $Permission.VDSwitch "for" $Permission.Principal "with role" $Permission.Role "and propagation" $Permission.Propagate "already exists"
        }
    }

    # If permission is on the root vCenter folder only
    #  We do not need to identify datacenter, since this folder is higher up the tree
    elseif ($Permission.Type -eq "Folder" -and $Permission.Path -eq "vCenterRoot"){
        $VerifyPermission = Get-VIPermission -entity (Get-Folder -Id Folder-group-d1) | Where-Object {($_.Entity.Name -eq $Permission.Entity) -and ($_.Role -eq $Permission.Role) -and ($_.Principal -eq $Permission.Principal)}
            if ($VerifyPermission -eq $null){
                New-VIPermission -Entity (Get-Folder -Id Folder-group-d1) -Principal $Permission.Principal -Role $Permission.Role -Propagate $Permission.Propagate -WarningAction SilentlyContinue | Out-Null
                Write-Host -ForegroundColor Green "ADDED - Permission entry on" $Permission.Type "-" $Permission.Entity "for" $Permission.Principal "with role" $Permission.Role "and propagation" $Permission.Propagate
                }
            else {
            Write-Host "  VERIFIED - Root vCenter level permission entry for" $Permission.Principal "with role" $Permission.Role "and propagation" $Permission.Propagate "already exists"
            }
    }

    # If permission exists on a folder
    #  Then we need to traverse the full path of the folder down from the its datacenter
    elseif ($Permission.Type -eq "Folder"){
        Write-Host -Foregroundcolor Yellow "  SKIPPED - "$Permission.Type "-" $Permission.Entity "for" $Permission.Principal "with role" $Permission.Role "and propagation" $Permission.Propagate "(Folder Permissions not yet implemented)"
        }
    # If permission exists on a VM
    #  VM names do not need to be unique
    #  We need to traverse the full path of the VM down from its datacenter
    elseif ($Permission.Type -eq "VirtualMachine"){
        Write-Host -Foregroundcolor Yellow "  SKIPPED - "$Permission.Type "-" $Permission.Entity "for" $Permission.Principal "with role" $Permission.Role "and propagation" $Permission.Propagate "(VM Permissions not yet implemented)"
    }
    
    # Alert if permission is on another object type not yet implemented
    else {
        Write-Host -ForegroundColor Yellow "  SKIPPED - unsupported object type" $Permission.Type "not yet implemented"
    }
}

Write-Host "Disconnecting from $VIserver..."
Disconnect-VIServer -Server $VIServer -Confirm:$False