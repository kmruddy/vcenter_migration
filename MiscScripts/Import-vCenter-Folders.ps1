<#
.SYNOPSIS
Imports vCenter folder names and paths for purposes of migration or backup
To be used with Import-vCenter-Folders.ps1

.DESCRIPTION
The script imports four files for each datacenter, one each detailing the VM, HostAndCluster, Network, and Datastore folder layouts
Datacenter-level folders are not compatible with the current version of this script.  This is due to the change in object type (from Folder to Datacenter) when
iterating up a folder path.  It could be added but was not necessary for our purposes at this time.
 * Handles duplicate folder names (e.g. SysDev\DBSvcs and Windows\DBSvcs) 
 * Can be run against existing folder structure, only missing folders are created and no folders are removed
 * Only works for nested folders up to a depth of 6, but can add more if needed

.PARAMETER VIServer
Specifies the vCenter FQDN

.PARAMETER DataCenterToImport
Specifies the datacenter to import from json files

.PARAMETER CreateMissingDatacenter
Optional switch to create datacenters with folder entries if they do not exist

.NOTES
Authors: Mark Wolfe and Scott Haas
Website: www.definebroken.com

Changelog:
14-May-2017
 * Initial Script
24-Aug-2017
 * Adjusted script for public consumption on github

Todo:
 * Rewrite so that one loop can handle all folder types
 * Add switch to allow for folder types to be imported individually
 * Add error message to alert on folders more than 6 levels deep that aren't created
 * Add Whatif switch 
 
.EXAMPLE
Export all folders to json files from vCenter vcenter.domain.com importing datacenter dc1 and create the datacenter if it's missing.

PS> Import-vCenter-Folders.ps1 -VIServer vcenter.domain.com -DatacenterToImport "dc1" -CreateMissingDatacenter

.LINK
Reference: https://github.com/ScottHaas/vcenter-migration-scripts
#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="FQDN of vCenter")]
    [ValidateNotNullOrEmpty()]
    [string]$VIServer,
    [Parameter(Mandatory=$true, Position=1, HelpMessage="Which Datacenter's folders to import?")]
    [string]$DataCenterToImport,
    [Parameter(HelpMessage="Creates datacenters with folder entries if they do not exist")]
    [switch]$CreateMissingDatacenter=$False
)

Write-Host "Disconnecting from all vCenter servers before connecting to target vCenter..."
Pause
Disconnect-VIServer * -ErrorAction:SilentlyContinue
Write-Host "`n`nConnecting to $VIServer...`n`n"
Connect-VIServer -Server $VIServer -ErrorAction Stop
Write-Host "`n`n"

$VIServerShortName = $VIServer.Split(".")[0]
$VMFilename = "$VIServerShortName.$DatacenterToImport.VMfolders.json"
$HostFileName = "$VIServerShortName.$DatacenterToImport.Hostfolders.json"
$NetworkFileName = "$VIServerShortName.$DatacenterToImport.Networkfolders.json"
$DatastoreFileName = "$VIServerShortName.$DatacenterToImport.Datastorefolders.json"
$ImportFileList = $VMFilename, $HostFileName, $NetworkFileName, $DatastoreFileName
$ErrorActionPreference = "silentlycontinue"
$MissingImportFiles = $false

#Verify that import files exist

ForEach ($Filename in $ImportFileList){
    If ((Test-Path $Filename) -eq $False){
        $MissingImportFiles = $true
        Write-Host "The import file $Filename doesn't appear to exist."
        }
    }


If ($MissingImportFiles -eq $true){
        Write-Host "One or more import files are missing.  Please check them and try again."
        Write-Host "Exiting..."
        Disconnect-Viserver -Server $VIServer -Confirm:$false
        Exit
        }

#Check if Datacenter Exists
$DoesDataCenterExist = Get-Datacenter $DataCenterToImport
If (Get-Datacenter $DataCenterToImport){
    Write-Host "Verified that the $DatacenterToImport datacenter exists, continuing..."
    }
    ElseIf ($CreateMissingDatacenter -eq $True){
       Write-Host "The $DataCenterToImport datacenter doesn't exist, creating..."
       New-Datacenter $DataCenterToImport -Location Datacenters
       }
        Else {
            Write-Host "The $DataCenterToImport datacenter doesn't seem to exist."
            Write-Host "If you'd like to create it, rerun the script with the -CreateMissingDatacenter switch."
            Write-Host "Disconnecting from vCenter Server $VIServer"
            Disconnect-VIServer -Server $VIServer -Confirm:$False
            Exit
            }

#Import the files
Write-Host "Importing VM folders from $VMFilename to $VIServerShortName\$DatacenterToImport"
$AllVMFolderPaths = Get-Content $VMFilename | ConvertFrom-Json 
Write-Host "Importing host folders from $HostFileName to $VIServerShortName\$DatacenterToImport"
$AllHostFolderPaths = Get-Content $HostFileName | ConvertFrom-Json 
Write-Host "Importing network folders from $NetworkFileName to $VIServerShortName\$DatacenterToImport"
$AllNetworkFolderPaths = Get-Content $NetworkFileName | ConvertFrom-Json 
Write-Host "Importing datastore folders from $DatastoreFileName to $VIServerShortName\$DatacenterToImport"
$AllDatastoreFolderPaths = Get-Content $DatastoreFileName | ConvertFrom-Json 

#Actually make some folders
$RootVMFolder = Get-Datacenter $DataCenterToImport | Get-Folder "vm"
$RootHostFolder = Get-Datacenter $DataCenterToImport | Get-Folder "host"
$RootNetworkFolder = Get-Datacenter $DataCenterToImport | Get-Folder "network"
$RootDatastoreFolder = Get-Datacenter $DataCenterToImport | Get-Folder "datastore"

Write-Host `n`n`n"----------------------------------"
Write-Host "    Working on VM Folders    "
Write-Host "----------------------------------"
ForEach ($1VMPath in $AllVMFolderPaths){

    $1VMPathSplit = $1VMPath.split("/")  #$1VMPathSplit contains an array of the individual folder components of a given folder's path
    $FolderCount = $1VMPathSplit.Count

    If ($FolderCount -ge 1){
        $CheckFolder = 1
        $CheckFolder = $RootVMFolder | Get-Folder $1VMPathSplit[0] -NoRecursion
            If ($CheckFolder){
                Write-Host "  \--" $1VMPathSplit[0] "already exists"
                }
                Else{
                    New-Folder -Location $RootVMFolder -Name $1VMPathSplit[0] | Out-Null
                    Write-Host "  \--" $1VMPathSplit[0] "created"
                    }
        }

    If ($FolderCount -ge 2){
        $CheckFolder = 1
        $CheckFolder = $RootVMFolder | Get-Folder $1VMPathSplit[0] -NoRecursion | Get-Folder $1VMPathSplit[1] -NoRecursion
            If ($CheckFolder){
                Write-Host "     \--" $1VMPathSplit[1] "already exists"
                } Else {
                    New-Folder -Location ($RootVMFolder | Get-Folder $1VMPathSplit[0] -NoRecursion) -Name $1VMPathSplit[1] | Out-Null
                    Write-Host "     \--" $1VMPathSplit[1] "created"
                    }
        }
        
    If ($FolderCount -ge 3){
        $CheckFolder = 1
        $CheckFolder = $RootVMFolder | Get-Folder $1VMPathSplit[0] -NoRecursion | Get-Folder $1VMPathSplit[1] -NoRecursion | Get-Folder $1VMPathSplit[2] -NoRecursion
            If ($CheckFolder){
                Write-Host "        \--" $1VMPathSplit[2] "already exists"
                } Else {
                    New-Folder -Location ($RootVMFolder | Get-Folder $1VMPathSplit[0] -NoRecursion | Get-Folder $1VMPathSplit[1] -NoRecursion) -Name $1VMPathSplit[2] | Out-Null
                    Write-Host "        \--" $1VMPathSplit[2] "created"
                    }
        }

    If ($FolderCount -ge 4){
        $CheckFolder = 1
        $CheckFolder = $RootVMFolder | Get-Folder $1VMPathSplit[0] -NoRecursion | Get-Folder $1VMPathSplit[1] -NoRecursion | Get-Folder $1VMPathSplit[2] -NoRecursion | Get-Folder $1VMPathSplit[3] -NoRecursion
            If ($CheckFolder){
                Write-Host "           \--" $1VMPathSplit[3] "already exists"
                } Else {
                    New-Folder -Location ($RootVMFolder | Get-Folder $1VMPathSplit[0] -NoRecursion | Get-Folder $1VMPathSplit[1] -NoRecursion | Get-Folder $1VMPathSplit[2] -NoRecursion) -Name $1VMPathSplit[3] | Out-Null
                    Write-Host "           \--" $1VMPathSplit[3] "created"
                    }
        }
    
    If ($FolderCount -ge 5){
        $CheckFolder = 1
        $CheckFolder = $RootVMFolder | Get-Folder $1VMPathSplit[0] -NoRecursion | Get-Folder $1VMPathSplit[1] -NoRecursion | Get-Folder $1VMPathSplit[2] -NoRecursion | Get-Folder $1VMPathSplit[3] -NoRecursion | Get-Folder $1VMPathSplit[4] -NoRecursion
            If ($CheckFolder){
                Write-Host "              \--" $1VMPathSplit[4] "already exists"
                } Else {
                    New-Folder -Location ($RootVMFolder | Get-Folder $1VMPathSplit[0] -NoRecursion | Get-Folder $1VMPathSplit[1] -NoRecursion | Get-Folder $1VMPathSplit[2] -NoRecursion | Get-Folder $1VMPathSplit[3] -NoRecursion) -Name $1VMPathSplit[4] | Out-Null
                    Write-Host "              \--" $1VMPathSplit[4] "created"
                    }
        }  
 
    If ($FolderCount -ge 6){
        $CheckFolder = 1
        $CheckFolder = $RootVMFolder | Get-Folder $1VMPathSplit[0] -NoRecursion | Get-Folder $1VMPathSplit[1] -NoRecursion | Get-Folder $1VMPathSplit[2] -NoRecursion | Get-Folder $1VMPathSplit[3] -NoRecursion | Get-Folder $1VMPathSplit[4] -NoRecursion | Get-Folder $1VMPathSplit[5] -NoRecursion
            If ($CheckFolder){
                Write-Host "                 \--" $1VMPathSplit[5] "already exists"
                } Else {
                    New-Folder -Location ($RootVMFolder | Get-Folder $1VMPathSplit[0] -NoRecursion | Get-Folder $1VMPathSplit[1] -NoRecursion | Get-Folder $1VMPathSplit[2] -NoRecursion | Get-Folder $1VMPathSplit[3] -NoRecursion | Get-Folder $1VMPathSplit[4] -NoRecursion) -Name $1VMPathSplit[5] | Out-Null
                    Write-Host "                 \--" $1VMPathSplit[5] "created"
                    }
        }  

    If ($FolderCount -ge 7){
        Write-Host "Folder $1VMPath has a folder path depth longer than this script supports.  Skipping..."
        } 

    }

Write-Host `n`n`n"----------------------------------"
Write-Host "      Working on Host Folders    "
Write-Host "----------------------------------"

ForEach ($1HostPath in $AllHostFolderPaths){

    $1HostPathSplit = $1HostPath.split("/")  #$1HostPathSplit contains an array of the individual folder components of a given folder's path
    $FolderCount = $1HostPathSplit.Count

    If ($FolderCount -ge 1){
        $CheckFolder = 1
        $CheckFolder = $RootHostFolder | Get-Folder $1HostPathSplit[0] -NoRecursion
            If ($CheckFolder){
                Write-Host "  \--" $1HostPathSplit[0] "already exists"
                }
                Else{
                    New-Folder -Location $RootHostFolder -Name $1HostPathSplit[0] | Out-Null
                    Write-Host "  \--" $1HostPathSplit[0] "created"
                    }
        }

    If ($FolderCount -ge 2){
        $CheckFolder = 1
        $CheckFolder = $RootHostFolder | Get-Folder $1HostPathSplit[0] -NoRecursion | Get-Folder $1HostPathSplit[1] -NoRecursion
            If ($CheckFolder){
                Write-Host "     \--" $1HostPathSplit[1] "already exists"
                } Else {
                    New-Folder -Location ($RootHostFolder | Get-Folder $1HostPathSplit[0] -NoRecursion) -Name $1HostPathSplit[1] | Out-Null
                    Write-Host "     \--" $1HostPathSplit[1] "created"
                    }
        }
        
    If ($FolderCount -ge 3){
        $CheckFolder = 1
        $CheckFolder = $RootHostFolder | Get-Folder $1HostPathSplit[0] -NoRecursion | Get-Folder $1HostPathSplit[1] -NoRecursion | Get-Folder $1HostPathSplit[2] -NoRecursion
            If ($CheckFolder){
                Write-Host "        \--" $1HostPathSplit[2] "already exists"
                } Else {
                    New-Folder -Location ($RootHostFolder | Get-Folder $1HostPathSplit[0] -NoRecursion | Get-Folder $1HostPathSplit[1] -NoRecursion) -Name $1HostPathSplit[2] | Out-Null
                    Write-Host "        \--" $1HostPathSplit[2] "created"
                    }
        }

    If ($FolderCount -ge 4){
        $CheckFolder = 1
        $CheckFolder = $RootHostFolder | Get-Folder $1HostPathSplit[0] -NoRecursion | Get-Folder $1HostPathSplit[1] -NoRecursion | Get-Folder $1HostPathSplit[2] -NoRecursion | Get-Folder $1HostPathSplit[3] -NoRecursion
            If ($CheckFolder){
                Write-Host "              \--" $1HostPathSplit[3] "already exists"
                } Else {
                    New-Folder -Location ($RootHostFolder | Get-Folder $1HostPathSplit[0] -NoRecursion | Get-Folder $1HostPathSplit[1] -NoRecursion | Get-Folder $1HostPathSplit[2] -NoRecursion) -Name $1HostPathSplit[3] | Out-Null
                    Write-Host "              \--" $1HostPathSplit[3] "created"
                    }
        }
    
    If ($FolderCount -ge 5){
        $CheckFolder = 1
        $CheckFolder = $RootHostFolder | Get-Folder $1HostPathSplit[0] -NoRecursion | Get-Folder $1HostPathSplit[1] -NoRecursion | Get-Folder $1HostPathSplit[2] -NoRecursion | Get-Folder $1HostPathSplit[3] -NoRecursion | Get-Folder $1HostPathSplit[4] -NoRecursion
            If ($CheckFolder){
                Write-Host "                 \--" $1HostPathSplit[4] "already exists"
                } Else {
                    New-Folder -Location ($RootHostFolder | Get-Folder $1HostPathSplit[0] -NoRecursion | Get-Folder $1HostPathSplit[1] -NoRecursion | Get-Folder $1HostPathSplit[2] -NoRecursion | Get-Folder $1HostPathSplit[3] -NoRecursion) -Name $1HostPathSplit[4] | Out-Null
                    Write-Host "                 \--" $1HostPathSplit[4] "created"
                    }
        }  
 
    If ($FolderCount -ge 6){
        $CheckFolder = 1
        $CheckFolder = $RootHostFolder | Get-Folder $1HostPathSplit[0] -NoRecursion | Get-Folder $1HostPathSplit[1] -NoRecursion | Get-Folder $1HostPathSplit[2] -NoRecursion | Get-Folder $1HostPathSplit[3] -NoRecursion | Get-Folder $1HostPathSplit[4] -NoRecursion | Get-Folder $1HostPathSplit[5] -NoRecursion
            If ($CheckFolder){
                Write-Host "                    \--" $1HostPathSplit[5] "already exists"
                } Else {
                    New-Folder -Location ($RootHostFolder | Get-Folder $1HostPathSplit[0] -NoRecursion | Get-Folder $1HostPathSplit[1] -NoRecursion | Get-Folder $1HostPathSplit[2] -NoRecursion | Get-Folder $1HostPathSplit[3] -NoRecursion | Get-Folder $1HostPathSplit[4] -NoRecursion) -Name $1HostPathSplit[5] | Out-Null
                    Write-Host "                    \--" $1HostPathSplit[5] "created"
                    }
        }  

    If ($FolderCount -ge 7){
        Write-Host "Folder $1HostPath has a folder path depth longer than this script supports.  Skipping..."
        } 

    }

Write-Host `n`n`n"----------------------------------"
Write-Host "   Working on Datastore Folders    "
Write-Host "----------------------------------"

ForEach ($1DatastorePath in $AllDatastoreFolderPaths){

    $1DatastorePathSplit = $1DatastorePath.split("/")  #$1DatastorePathSplit contains an array of the individual folder components of a given folder's path
    $FolderCount = $1DatastorePathSplit.Count

    If ($FolderCount -ge 1){
        $CheckFolder = 1
        $CheckFolder = $RootDatastoreFolder | Get-Folder $1DatastorePathSplit[0] -NoRecursion
            If ($CheckFolder){
                Write-Host "  \--" $1DatastorePathSplit[0] "already exists"
                }
                Else{
                    New-Folder -Location $RootDatastoreFolder -Name $1DatastorePathSplit[0] | Out-Null
                    Write-Host "  \--" $1DatastorePathSplit[0] "created"
                    }
        }

    If ($FolderCount -ge 2){
        $CheckFolder = 1
        $CheckFolder = $RootDatastoreFolder | Get-Folder $1DatastorePathSplit[0] -NoRecursion | Get-Folder $1DatastorePathSplit[1] -NoRecursion
            If ($CheckFolder){
                Write-Host "     \--" $1DatastorePathSplit[1] "already exists"
                } Else {
                    New-Folder -Location ($RootDatastoreFolder | Get-Folder $1DatastorePathSplit[0] -NoRecursion) -Name $1DatastorePathSplit[1] | Out-Null
                    Write-Host "     \--" $1DatastorePathSplit[1] "created"
                    }
        }
        
    If ($FolderCount -ge 3){
        $CheckFolder = 1
        $CheckFolder = $RootDatastoreFolder | Get-Folder $1DatastorePathSplit[0] -NoRecursion | Get-Folder $1DatastorePathSplit[1] -NoRecursion | Get-Folder $1DatastorePathSplit[2] -NoRecursion
            If ($CheckFolder){
                Write-Host "        \--" $1DatastorePathSplit[2] "already exists"
                } Else {
                    New-Folder -Location ($RootDatastoreFolder | Get-Folder $1DatastorePathSplit[0] -NoRecursion | Get-Folder $1DatastorePathSplit[1] -NoRecursion) -Name $1DatastorePathSplit[2] | Out-Null
                    Write-Host "        \--" $1DatastorePathSplit[2] "created"
                    }
        }

    If ($FolderCount -ge 4){
        $CheckFolder = 1
        $CheckFolder = $RootDatastoreFolder | Get-Folder $1DatastorePathSplit[0] -NoRecursion | Get-Folder $1DatastorePathSplit[1] -NoRecursion | Get-Folder $1DatastorePathSplit[2] -NoRecursion | Get-Folder $1DatastorePathSplit[3] -NoRecursion
            If ($CheckFolder){
                Write-Host "           \--" $1DatastorePathSplit[3] "already exists"
                } Else {
                    New-Folder -Location ($RootDatastoreFolder | Get-Folder $1DatastorePathSplit[0] -NoRecursion | Get-Folder $1DatastorePathSplit[1] -NoRecursion | Get-Folder $1DatastorePathSplit[2] -NoRecursion) -Name $1DatastorePathSplit[3] | Out-Null
                    Write-Host "           \--" $1DatastorePathSplit[3] "created"
                    }
        }
    
    If ($FolderCount -ge 5){
        $CheckFolder = 1
        $CheckFolder = $RootDatastoreFolder | Get-Folder $1DatastorePathSplit[0] -NoRecursion | Get-Folder $1DatastorePathSplit[1] -NoRecursion | Get-Folder $1DatastorePathSplit[2] -NoRecursion | Get-Folder $1DatastorePathSplit[3] -NoRecursion | Get-Folder $1DatastorePathSplit[4] -NoRecursion
            If ($CheckFolder){
                Write-Host "              \--" $1DatastorePathSplit[4] "already exists"
                } Else {
                    New-Folder -Location ($RootDatastoreFolder | Get-Folder $1DatastorePathSplit[0] -NoRecursion | Get-Folder $1DatastorePathSplit[1] -NoRecursion | Get-Folder $1DatastorePathSplit[2] -NoRecursion | Get-Folder $1DatastorePathSplit[3] -NoRecursion) -Name $1DatastorePathSplit[4] | Out-Null
                    Write-Host "              \--" $1DatastorePathSplit[4] "created"
                    }
        }  

    If ($FolderCount -ge 6){
        $CheckFolder = 1
        $CheckFolder = $RootDatastoreFolder | Get-Folder $1DatastorePathSplit[0] -NoRecursion | Get-Folder $1DatastorePathSplit[1] -NoRecursion | Get-Folder $1DatastorePathSplit[2] -NoRecursion | Get-Folder $1DatastorePathSplit[3] -NoRecursion | Get-Folder $1DatastorePathSplit[4] -NoRecursion | Get-Folder $1DatastorePathSplit[5] -NoRecursion
            If ($CheckFolder){
                Write-Host "                 \--" $1DatastorePathSplit[5] "already exists"
                } Else {
                    New-Folder -Location ($RootDatastoreFolder | Get-Folder $1DatastorePathSplit[0] -NoRecursion | Get-Folder $1DatastorePathSplit[1] -NoRecursion | Get-Folder $1DatastorePathSplit[2] -NoRecursion | Get-Folder $1DatastorePathSplit[3] -NoRecursion | Get-Folder $1DatastorePathSplit[4] -NoRecursion) -Name $1DatastorePathSplit[5] | Out-Null
                    Write-Host "                 \--" $1DatastorePathSplit[5] "created"
                    }
        }  

    If ($FolderCount -ge 7){
        Write-Host "Folder $1DatastorePath has a folder path depth longer than this script supports.  Skipping..."
        } 

    }

Write-Host `n`n`n"----------------------------------"
Write-Host "    Working on Network Folders    "
Write-Host "----------------------------------"

ForEach ($1NetworkPath in $AllNetworkFolderPaths){

    $1NetworkPathSplit = $1NetworkPath.split("/")  #$1NetworkPathSplit contains an array of the individual folder components of a given folder's path
    $FolderCount = $1NetworkPathSplit.Count

    If ($FolderCount -ge 1){
        $CheckFolder = 1
        $CheckFolder = $RootNetworkFolder | Get-Folder $1NetworkPathSplit[0] -NoRecursion
            If ($CheckFolder){
                Write-Host "  \--" $1NetworkPathSplit[0] "already exists"
                }
                Else{
                    New-Folder -Location $RootNetworkFolder -Name $1NetworkPathSplit[0] | Out-Null
                    Write-Host "  \--" $1NetworkPathSplit[0] "created"
                    }
        }

    If ($FolderCount -ge 2){
        $CheckFolder = 1
        $CheckFolder = $RootNetworkFolder | Get-Folder $1NetworkPathSplit[0] -NoRecursion | Get-Folder $1NetworkPathSplit[1] -NoRecursion
            If ($CheckFolder){
                Write-Host "     \--" $1NetworkPathSplit[1] "already exists"
                } Else {
                    New-Folder -Location ($RootNetworkFolder | Get-Folder $1NetworkPathSplit[0] -NoRecursion) -Name $1NetworkPathSplit[1] | Out-Null
                    Write-Host "     \--" $1NetworkPathSplit[1] "created"
                    }
        }
        
    If ($FolderCount -ge 3){
        $CheckFolder = 1
        $CheckFolder = $RootNetworkFolder | Get-Folder $1NetworkPathSplit[0] -NoRecursion | Get-Folder $1NetworkPathSplit[1] -NoRecursion | Get-Folder $1NetworkPathSplit[2] -NoRecursion
            If ($CheckFolder){
                Write-Host "        \--" $1NetworkPathSplit[2] "already exists"
                } Else {
                    New-Folder -Location ($RootNetworkFolder | Get-Folder $1NetworkPathSplit[0] -NoRecursion | Get-Folder $1NetworkPathSplit[1] -NoRecursion) -Name $1NetworkPathSplit[2] | Out-Null
                    Write-Host "        \--" $1NetworkPathSplit[2] "created"
                    }
        }

    If ($FolderCount -ge 4){
        $CheckFolder = 1
        $CheckFolder = $RootNetworkFolder | Get-Folder $1NetworkPathSplit[0] -NoRecursion | Get-Folder $1NetworkPathSplit[1] -NoRecursion | Get-Folder $1NetworkPathSplit[2] -NoRecursion | Get-Folder $1NetworkPathSplit[3] -NoRecursion
            If ($CheckFolder){
                Write-Host "           \--" $1NetworkPathSplit[3] "already exists"
                } Else {
                    New-Folder -Location ($RootNetworkFolder | Get-Folder $1NetworkPathSplit[0] -NoRecursion | Get-Folder $1NetworkPathSplit[1] -NoRecursion | Get-Folder $1NetworkPathSplit[2] -NoRecursion) -Name $1NetworkPathSplit[3] | Out-Null
                    Write-Host "           \--" $1NetworkPathSplit[3] "created"
                    }
        }
    
    If ($FolderCount -ge 5){
        $CheckFolder = 1
        $CheckFolder = $RootNetworkFolder | Get-Folder $1NetworkPathSplit[0] -NoRecursion | Get-Folder $1NetworkPathSplit[1] -NoRecursion | Get-Folder $1NetworkPathSplit[2] -NoRecursion | Get-Folder $1NetworkPathSplit[3] -NoRecursion | Get-Folder $1NetworkPathSplit[4] -NoRecursion
            If ($CheckFolder){
                Write-Host "              \--" $1NetworkPathSplit[4] "already exists"
                } Else {
                    New-Folder -Location ($RootNetworkFolder | Get-Folder $1NetworkPathSplit[0] -NoRecursion | Get-Folder $1NetworkPathSplit[1] -NoRecursion | Get-Folder $1NetworkPathSplit[2] -NoRecursion | Get-Folder $1NetworkPathSplit[3] -NoRecursion) -Name $1NetworkPathSplit[4] | Out-Null
                    Write-Host "              \--" $1NetworkPathSplit[4] "created"
                    }
        }  
 
    If ($FolderCount -ge 6){
        $CheckFolder = 1
        $CheckFolder = $RootNetworkFolder | Get-Folder $1NetworkPathSplit[0] -NoRecursion | Get-Folder $1NetworkPathSplit[1] -NoRecursion | Get-Folder $1NetworkPathSplit[2] -NoRecursion | Get-Folder $1NetworkPathSplit[3] -NoRecursion | Get-Folder $1NetworkPathSplit[4] -NoRecursion | Get-Folder $1NetworkPathSplit[5] -NoRecursion
            If ($CheckFolder){
                Write-Host "                 \--" $1NetworkPathSplit[5] "already exists"
                } Else {
                    New-Folder -Location ($RootNetworkFolder | Get-Folder $1NetworkPathSplit[0] -NoRecursion | Get-Folder $1NetworkPathSplit[1] -NoRecursion | Get-Folder $1NetworkPathSplit[2] -NoRecursion | Get-Folder $1NetworkPathSplit[3] -NoRecursion | Get-Folder $1NetworkPathSplit[4] -NoRecursion) -Name $1NetworkPathSplit[5] | Out-Null
                    Write-Host "                 \--" $1NetworkPathSplit[5] "created"
                    }
        }  

    If ($FolderCount -ge 7){
        Write-Host "Folder $1NetworkPath has a folder path depth longer than this script supports.  Skipping..."
        } 

    }

Write-Host "`n`nvSphere Folders Import Complete!`n`n"
Write-Host "Disconnecting from vCenter Server $VIServer"
Disconnect-VIServer -Server $VIServer -Confirm:$False
