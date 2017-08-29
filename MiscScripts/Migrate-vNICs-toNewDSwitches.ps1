<#
.SYNOPSIS
Migrate vNICs to new DSwitch portgroups based on custom attributes vNIC0 through vNIC10
Used for migration between vCenters and run against a swing host that is mounted to old and new DSWitches.

.PARAMETER jsonFile
The JSON file used to import settings

.PARAMETER esxiHostname
ESXi hostname to get vms from instead of guest list in JSON

.PARAMETER WhatIf
Switch that enables the whatif mode so changes are not applied.

.NOTES
Author: Scott Haas
Website: www.definebroken.com

Changelog:
11-Aug-2017
 * Initial Script
24-Aug-2017 
 * Adjusted script for public consumption on github


.EXAMPLE
Run a whatif simulation moving VMs on host esxi-1 with vCenter_Batch1_data json file.
PS> Migrate-vNICs-toNewDSwitches.ps1 -esxiHostname "esxi-1.domain.com" -jsonFile "vCenter_batch1_data.json" -WhatIf

.EXAMPLE
Migrate iscsi uplink 1 vNICS on VMs on esxi-1 host
PS> Migrate-vNICs-toNewDSwitches.ps1 -esxiHostname "esxi-1.domain.com" -jsonFile "vCenter_batch2_iscsiUplink1.json"

.LINK
Reference: https://github.com/ScottHaas/vcenter-migration-scripts

#>
[CmdletBinding()]
Param(
	[Parameter(Mandatory=$true,HelpMessage="Filename for the JSON formatted file to migrate vNICS between vCenters")]
	[ValidateNotNullOrEmpty()]
	[string]$jsonFile,

    [Parameter(Mandatory=$false,HelpMessage="Optional ESXi Hostname to get vms from instead of guest list in JSON")]
    [string]$esxiHostname,

	[Parameter(Mandatory=$false,HelpMessage="Optional Whatif Switch")]
	[ValidateNotNullOrEmpty()]
	[switch]$whatif
)

$jsonObj = get-content $jsonFile|convertfrom-json
if (!$jsonObj){
    write-host "JSON file not defined or working. Please check and try again using -jsonfile parameter."
    break
}

$jsonGuests = $jsonObj.Guests
if (!$esxihostname -and !$jsonGuests){
    write-host "No Guests Defined. Please add guest names to the json file or specify a -esxiHostname parameter."
    break
}

#Main code
$viserver = connect-viserver $jsonObj.vcName -ErrorAction Stop
if ($esxiHostname){
    $vms = get-datacenter $jsonObj.Datacenter|get-vmhost $esxiHostname|get-vm
    $dcView = get-view -ViewType Datacenter -Filter @{'Name' = $jsonObj.Datacenter}
    $hostView = get-view -viewType HostSystem -Filter @{'Name'=$esxiHostname}
    $vmsView = get-view -id $hostview.vm -property Name,AvailableField,summary
} else {
    $vms = get-datacenter $jsonObj.Datacenter|get-vm $jsonGuests
    $dcView = get-view -ViewType Datacenter -Filter @{'Name' = $jsonObj.Datacenter}
    $vmsView = $vms|get-view -Property Name,AvailableField,Summary
}

$workingVMList = New-Object Collections.ArrayList
foreach ($vmView in $vmsView){
    
    $currVNICsAttr = $vmView.AvailableField|?{$_.name -match "vNIC"}
    foreach ($currVNICAttr in $currVNICsAttr){
        $vmMember =New-object PSObject
        
        $attrKeyName = $currVNICAttr.Name
        $attrKey = $currVNICAttr.Key
        $attrValue = ($vmView.summary.customvalue|?{$_.key -eq $attrKey}).value
        
        if ($attrValue){
            Add-Member -InputObject $vmMember -MemberType NoteProperty -Name AnnotatedEntity -Value $vmView.Name    
            Add-Member -InputObject $vmMember -MemberType NoteProperty -Name Name -value $attrKeyName
            Add-Member -InputObject $vmMember -MemberType NoteProperty -Name Value -value $attrValue    
            $workingVMList += $vmMember
        }
    } 
    
}

$vmNICs = $workingVMlist

if ($whatif){
	write-host "Running in WhatIf mode.`n"
}

$destVDSwitch = get-datacenter $jsonObj.Datacenter|get-vdswitch $jsonObj.DestinationDSwitch
foreach ($vm in $vms){
   
    $DPortgroups = $jsonObj.DPortgroups
	foreach ($DPortGroup in $DPortgroups){
        
        $srcPortgroup = $DPortgroup.sourcePortgroup
        $destPortgroup = $DPortgroup.destinationPortgroup
        $DestPortgroupObj = $destVDSwitch|get-vdportgroup $destPortgroup
        $vmNICFilter = $vmNICs|?{$_.Value -eq $srcPortgroup -and $_.AnnotatedEntity -eq $vm}
       
        Foreach ($vmNIC in $vmNICFilter){
            $currvmNICName = "Network adapter " + $vmNIC.name.replace("vNIC","")
            write-host "Getting Adapter $currvmNICName"
            $currvmNICObj =$vm|get-networkadapter -name $currvmNICName
            
            $currvmNICNetwork = $currvmNICObj.networkName
            if ($currvmNICNetwork -ne $DestPortgroupObj.name ){
                $null = $currvmNICObj|Set-NetworkAdapter -Portgroup $DestPortgroupObj -confirm:$false -WhatIf:$whatif -RunAsync
            }
        }
	}
}

write-host "Script Finished."
disconnect-viserver $viserver -confirm:$false