<#
.SYNOPSIS
Exports vCenter folder names and paths for purposes of migration or backup
To be used with Import-vCenter-Folders.ps1

.DESCRIPTION
The script produces four files for each datacenter, one each detailing the VM, HostAndCluster, Network, and Datastore folder layouts
Datacenter-level folders are not compatible with the current version of this script.  This is due to the change in object type (from Folder to Datacenter) when
iterating up a folder path.  It could be added but was not necessary for our purposes at this time.

.PARAMETER VIServer
Specifies the vCenter FQDN

.NOTES
Authors: Mark Wolfe and Scott Haas
Website: www.definebroken.com

Changelog:
14-May-2017
 * Initial Script
24-Aug-2017
 * Adjusted script for public consumption on github

Todo:
 * Add parameter to specify exporting a single datacenter only
 * Additional error checking
 * Simplify script, remove array declarations if not needed

.EXAMPLE
Export all folders to json files from vCenter vcenter.domain.com

PS> Export-vCenter-Folders.ps1 -VIServer vcenter.domain.com

.LINK
Reference: https://github.com/ScottHaas/vcenter-migration-scripts

#>
[CmdletBinding()]
Param(
  [Parameter(Mandatory=$true, Position=0, HelpMessage="FQDN of vCenter")]
  [ValidateNotNullOrEmpty()]
  [string]$VIServer
)

Write-Host "`n`nConnecting to $VIServer...`n`n"
Connect-VIServer -Server $VIServer -ErrorAction Stop
Write-Host "`n`n"

$DataCenters = Get-Datacenter                               # All datacenter objects
$DataCenterTypeFolders = Get-Folder -Type Datacenter        # All folder objects of type datacenter
$AllVMFolderPaths = @()                                     # Empty Array
$AllHostFolderPaths = @()                                   # Empty Array
$AllNetworkFolderPaths = @()                                # Empty Array
$AllDatastoreFolderPaths = @()                              # Empty Array
$FolderTypes = "VM","HostAndCluster","Network","Datastore"  # Array of valid folder types
$SystemFolderNames = "vm","host","datastore","network"      # Array of system folder names automatically created inside each datacenter
$VIServerShortName = $VIServer.Split(".")[0]                # vCenter hostname, taken by splitting FQDN and selecting first array element


# If there are any folders of type datacenter that have a parent of type datacenter, exit
# Script was not designed to handle datacenter level folders due to added complexity of iterating a folder path up through datacenter (non-folder) objects

If ($DataCenterTypeFolders.parent.type -contains "Datacenter"){
    Write-Host "vCenter contains Datacenter folders."
    Write-Host "Script not designed to handle such folders."
    Write-Host "Exiting."
    Disconnect-VIServer $VIServer -Confirm:$False
    Exit
}

# Work on one Datacenter at a time, and for the purposes of this script consider the datacenter the root level of a folder's path
ForEach ($Datacenter in $Datacenters) {
    Write-Host "Working on $Datacenter..."
    $AllDataCenterChildFolders = Get-Folder -Location $DataCenter

    ForEach ($Folder in $AllDataCenterChildFolders){              # Iterate through each folder in the Datacenter
        
        $FolderType = $Folder.Type

        # If the folder is one of the hidden system folders in the datacenter, break from loop and move on to the next folder
        # We do not need to recreate, and therefore record and export on, the hidden system folders
        if ($SystemFolderNames -contains $Folder.Name){
            Continue
            }

        #Put the first folder name in the path, it will end up at the end of the path
        $FolderPath = $Folder.Name

        #Follow the parents up through the path, but stop when you get to the root vm, network, datastore, or host folder
        while ($SystemFolderNames -notcontains $Folder.Parent.Name){  #While the $Folder.Parent.Name is not a system folder name, meaning iterate until reaching "root" folder (vm, network, storage, datastore)
            $Folder = Get-Folder -Id $Folder.Parent.Id      #Replace the object in $Folder with its parent
            $FolderPath = $Folder.Name + "/" + $FolderPath  #Add the parent folder name +/ to $Folderpath
             }
 
        if ($FolderType -eq "VM") {$AllVMFolderPaths += $FolderPath}  #If Folder is of type VM, add it to the array of all VM folder paths
        if ($FolderType -eq "HostAndCluster") {$AllHostFolderPaths += $FolderPath}  #If Folder is of type HostAndCluster, add it to the array of all host folder paths
        if ($FolderType -eq "Network") {$AllNetworkFolderPaths += $FolderPath}  #If Folder is of type Network, add it to the array of all Network folder paths
        if ($FolderType -eq "Datastore") {$AllDatastoreFolderPaths += $FolderPath}  #If Folder is of type Datastore, add it to the array of all Datastore folder paths
    }

    $VMFilename = "$VIServerShortName.$Datacenter.VMfolders.json"
    $HostFileName = "$VIServerShortName.$Datacenter.Hostfolders.json"
    $NetworkFileName = "$VIServerShortName.$Datacenter.Networkfolders.json"
    $DatastoreFileName = "$VIServerShortName.$Datacenter.Datastorefolders.json"
    Write-Host "  Exporting $Datacenter VM folders to $VMFilename..."
    $AllVMFolderPaths | Sort-Object | ConvertTo-Json | Out-File $VMFilename
    Write-Host "  Exporting $Datacenter host folders to $HostFilename..."
    $AllHostFolderPaths | Sort-Object | ConvertTo-Json | Out-File $HostFilename
    Write-Host "  Exporting $Datacenter network folders to $NetworkFilename..."
    $AllNetworkFolderPaths | Sort-Object | ConvertTo-Json | Out-File $NetworkFilename
    Write-Host "  Exporting $Datacenter datastore folders to $DatastoreFilename..."
    $AllDatastoreFolderPaths | Sort-Object | ConvertTo-Json | Out-File $DatastoreFilename
    $AllVMFolderPaths = @()                                     # Reset the array (may not be necessary?)
    $AllHostFolderPaths = @()                                   # Reset the array (may not be necessary?)
    $AllNetworkFolderPaths = @()                                # Reset the array (may not be necessary?)
    $AllDatastoreFolderPaths = @()                              # Reset the array (may not be necessary?)


}

Write-Host "`n`nvSphere Folders Export Complete!`n`n"
Write-Host "Disconnecting from vCenter Server $VIServer"
Disconnect-VIServer -Server $VIServer -Confirm:$False
