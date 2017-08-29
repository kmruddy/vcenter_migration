$DataCenters = Get-Datacenter -Server $SourceVC                       # All datacenter objects
$DataCenterTypeFolders = Get-Folder -Server $SourceVC -Type Datacenter        # All folder objects of type datacenter
$AllVMFolderPaths = @()                                     # Empty Array
$AllHostFolderPaths = @()                                   # Empty Array
$AllNetworkFolderPaths = @()                                # Empty Array
$AllDatastoreFolderPaths = @()                              # Empty Array
$FolderTypes = "VM","HostAndCluster","Network","Datastore"  # Array of valid folder types
$SystemFolderNames = "vm","host","datastore","network"      # Array of system folder names automatically created inside each datacenter

## Create temporary migrationdata folder
$MigrationData = "$env:temp\vCenterMigrationData"
if (!(Test-Path -Path $MigrationData -PathType Container -ErrorAction Ignore)) {
	New-Item $MigrationData -ItemType Directory
} else {
	Remove-Item "$MigrationData\*"
}

# If there are any folders of type datacenter that have a parent of type datacenter, exit
# Script was not designed to handle datacenter level folders due to added complexity of iterating a folder path up through datacenter (non-folder) objects

If ($DataCenterTypeFolders.parent.type -contains "Datacenter"){
    Write-Host "vCenter contains Datacenter folders."
    Write-Host "Script not designed to handle such folders."
    Write-Host "Exiting."
	return $null
}

# Work on one Datacenter at a time, and for the purposes of this script consider the datacenter the root level of a folder's path
ForEach ($Datacenter in $Datacenters) {
    Write-Host "Working on $Datacenter..."
    $AllDataCenterChildFolders = Get-Folder -Server $SourceVC -Location $DataCenter

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
            $Folder = Get-Folder -Server $SourceVC -Id $Folder.Parent.Id      #Replace the object in $Folder with its parent
            $FolderPath = $Folder.Name + "/" + $FolderPath  #Add the parent folder name +/ to $Folderpath
             }
 
        if ($FolderType -eq "VM") {$AllVMFolderPaths += $FolderPath}  #If Folder is of type VM, add it to the array of all VM folder paths
        if ($FolderType -eq "HostAndCluster") {$AllHostFolderPaths += $FolderPath}  #If Folder is of type HostAndCluster, add it to the array of all host folder paths
        if ($FolderType -eq "Network") {$AllNetworkFolderPaths += $FolderPath}  #If Folder is of type Network, add it to the array of all Network folder paths
        if ($FolderType -eq "Datastore") {$AllDatastoreFolderPaths += $FolderPath}  #If Folder is of type Datastore, add it to the array of all Datastore folder paths
    }

    $VMFilename = "$Datacenter.VMfolders.json"
    $HostFileName = "$Datacenter.Hostfolders.json"
    $NetworkFileName = "$Datacenter.Networkfolders.json"
    $DatastoreFileName = "$Datacenter.Datastorefolders.json"
    Write-Host "  Exporting $Datacenter VM folders to $VMFilename..."
    $AllVMFolderPaths | Sort-Object | ConvertTo-Json | Out-File "$MigrationData\$VMFilename"
    Write-Host "  Exporting $Datacenter host folders to $HostFilename..."
    $AllHostFolderPaths | Sort-Object | ConvertTo-Json | Out-File "$MigrationData\$HostFilename"
    Write-Host "  Exporting $Datacenter network folders to $NetworkFilename..."
    $AllNetworkFolderPaths | Sort-Object | ConvertTo-Json | Out-File "$MigrationData\$NetworkFilename"
    Write-Host "  Exporting $Datacenter datastore folders to $DatastoreFilename..."
    $AllDatastoreFolderPaths | Sort-Object | ConvertTo-Json | Out-File "$MigrationData\$DatastoreFilename"
    $AllVMFolderPaths = @()                                     # Reset the array (may not be necessary?)
    $AllHostFolderPaths = @()                                   # Reset the array (may not be necessary?)
    $AllNetworkFolderPaths = @()                                # Reset the array (may not be necessary?)
    $AllDatastoreFolderPaths = @()                              # Reset the array (may not be necessary?)

}

Write-Host "`n`nvSphere Folders Export Complete!`n`n"
do {
	$CreateMissingDatacenter=$True

	## Select the Datacenter
	$DataCentertoImport = Get-Selection -SelectionTitle "Choose the Datacenter to Copy Folders from" -SelectionList $DataCenters


	$VMFilename = "$MigrationData\$DatacenterToImport.VMfolders.json"
	$HostFileName = "$MigrationData\$DatacenterToImport.Hostfolders.json"
	$NetworkFileName = "$MigrationData\$DatacenterToImport.Networkfolders.json"
	$DatastoreFileName = "$MigrationData\$DatacenterToImport.Datastorefolders.json"
	$ImportFileList = $VMFilename, $HostFileName, $NetworkFileName, $DatastoreFileName
	$ErrorActionPreference = "silentlycontinue"
	$MissingImportFiles = $falsed

	#Verify that import files exist

	ForEach ($Filename in $ImportFileList){
	    If ((Test-Path $Filename) -eq $False){
	        $MissingImportFiles = $true
	        Write-Host "The import file $Filename doesn't appear to exist."
	    }
	}


	#Check if Datacenter Exists
	$DoesDataCenterExist = Get-Datacenter -Server $TargetVC -Name $DataCenterToImport

	If (Get-Datacenter -Server $TargetVC -Name $DataCenterToImport){
	    Write-Host "Verified that the $DatacenterToImport datacenter exists, continuing..."
	} ElseIf ($CreateMissingDatacenter -eq $True){
	       Write-Host "The $DataCenterToImport datacenter doesn't exist, creating..."
	       New-Datacenter -Server $TargetVC -Name $DataCenterToImport -Location Datacenters
	       }
	        Else {

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
	$RootVMFolder = Get-Datacenter -Server $TargetVC -Name $DataCenterToImport | Get-Folder "vm"
	$RootHostFolder = Get-Datacenter -Server $TargetVC -Name $DataCenterToImport | Get-Folder "host"
	$RootNetworkFolder = Get-Datacenter -Server $TargetVC -Name $DataCenterToImport | Get-Folder "network"
	$RootDatastoreFolder = Get-Datacenter -Server $TargetVC -Name $DataCenterToImport | Get-Folder "datastore"

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
	$ProcessAnother = Get-YesNo -Question "Process another Datacenter?"
} while ($ProcessAnother)





