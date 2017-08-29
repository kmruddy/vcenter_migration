<#
.SYNOPSIS
Move VMs into the VM and Templates folder based on the custom attribute vmFolder. 
Mostly for migrations between vCenters.

.DESCRIPTION
This script moves VMs into their original VM and Templates folders by looking at
the vmFolder custom attribute that was set before hand. Designed to be used
alongside the Set-VMAttrs-vmFolderandvNICs.ps1 script for vCenter migrations.

.PARAMETER Server
Specifies the vCenter FQDN

.PARAMETER Datacenter
Specifies the vCenter Datacenter to move guests within.

.PARAMETER Cluster
Optional cluster name to query guests within.

.PARAMETER Guests
Optional VM objects to be moved into their respective vm folders. 
If not specified all vms are checked and moved.

.PARAMETER WhatIf
Optional switch that enables the whatif mode so changes are not applied.

.NOTES
Author: Scott Haas
Website: www.definebroken.com
Credit: Utilized Get-FolderByPath from http://www.lucd.info

Changelog:
11-Aug-2017
 * Initial Script
23-Aug-2017
 * Adjusted script for public consumption on github

.EXAMPLE
Run a whatif scenario against vcenter.domain.com for all guests named testvm* in the dc1 datacenter

PS> Move-VMs-with-vmFolderAttribute.ps1 -Whatif -Server vcenter.domain.com -Datacenter "dc1" -Guests "testvm*"

.EXAMPLE
Run a whatif scenario against vcenter.domain.com for all guests in the cluster cluster1 within datacenter dc1.

PS> Move-VMs-with-vmFolderAttribute.ps1 -Server vcenter.domain.com -Datacenter "dc1" -Cluster "cluster1" -WhatIf

.EXAMPLE
Move all VMs in the dc1 datacenter into their original folders 

PS> Move-VMs-with-vmFolderAttribute.ps1 -Server vcenter.domain.com -Datacenter "dc1" 

.LINK
Reference: https://github.com/ScottHaas/vcenter-migration-scripts

#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true,HelpMessage="FQDN vCenter")]
    [ValidateNotNullOrEmpty()]
    [string]$server,

    [Parameter(Mandatory=$false,HelpMessage="Guests to Verify and Move")]
    [string]$Guests = "*",

    [Parameter(Mandatory=$true,HelpMessage="Datacenter Name")]
    [ValidateNotNullOrEmpty()]
    [string]$datacenter,

    [Parameter(Mandatory=$false,HelpMessage="Cluster Name")]
    [string]$cluster,

    [Parameter(Mandatory=$false,HelpMessage="What if option")]
    [switch]$WhatIf
)

#Functions
function Get-FolderByPath{
    <# .SYNOPSIS Retrieve folders by giving a path 
    .DESCRIPTION The function will retrieve a folder by it's path. The path can contain any type of leave (folder or datacenter). 
    .NOTES Author: Luc Dekens .PARAMETER Path The path to the folder. This is a required parameter. 
    .PARAMETER Path The path to the folder. This is a required parameter. 
    .PARAMETER Separator The character that is used to separate the leaves in the path. The default is '\' 
    .EXAMPLE PS> Get-FolderByPath -Path "Folder1\Datacenter\Folder2"
    .EXAMPLE
    PS> Get-FolderByPath -Path "Folder1\Folder2" -Separator '\'
    #>
    param(
        [CmdletBinding()]
        [parameter(Mandatory = $true)]
        [System.String[]]${Path},
        [char]${Separator} = '\'
    )
    process{
        if((Get-PowerCLIConfiguration).DefaultVIServerMode -eq "Multiple"){
        $vcs = $defaultVIServers
        } else{
            $vcs = $defaultVIServers[0]
        }
        foreach($vc in $vcs){
            foreach($strPath in $Path){
                $root = Get-Folder -Name Datacenters -Server $vc
                $strPath.Split($Separator) | %{
                    $root = Get-Inventory -Name $_ -Location $root -Server $vc -NoRecursion
                    if((Get-Inventory -Location $root -NoRecursion | Select -ExpandProperty Name) -contains "vm"){
                        $root = Get-Inventory -Name "vm" -Location $root -Server $vc -NoRecursion
                    }
                }
                $root | where {$_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.FolderImpl]}|%{
                    Get-Folder -Name $_.Name -Location $root.Parent -NoRecursion -Server $vc
                }
            }
        }
    }
}

#Main Code
$viserver = connect-viserver $Server -ErrorAction Stop

if ($cluster){
    $vms = get-datacenter $datacenter | get-cluster $cluster | get-vm $Guests
} else {
    $vms = get-datacenter $datacenter|get-vm $Guests
}

if ($Whatif){
    write-host "Running in WhatIf mode.`n"
}

foreach ($vm in $vms){
    $vmPath = (get-annotation -Entity $vm -CustomAttribute "vmFolder").Value
    $vmSplit = $vmPath.split("\",[System.StringSplitOptions]::RemoveEmptyEntries)
    $vmSplitCount = $vmSplit.count - 1
    $vmDC = $vmSplit[0]
    $DCID = (get-datacenter $vmDC).Id
    $currVMFolderID=(get-vm $vm).folderid
    if ($vmSplitCount -eq 0){
        if ((get-folder -id $currVMFolderID).parentid -ne $DCID){
            write-host "`nMoving $vm to $vmDC"
            $null = Move-VM -VM $vm -Destination (get-datacenter -id $DCID) -whatif:$whatif
        }
    } else {
        $vmFolders = $vmSplit[(1..$vmSplitCount)]
        $NewVMFolder = get-folderbypath -path ($vmsplit -join "\")
        $NewVMFolderID = $newVMFolder.id
        if ($currVMFolderID -ne $NewVMFolderID){
            write-host "`nMoving $vm to $NewVMFolder"
            $null = Move-VM -VM $vm -Destination (get-folder -id $NewVMFolderID) -whatif:$whatif
        }
    }
}    

write-host "Script Complete."
disconnect-viserver $viserver -confirm:$false