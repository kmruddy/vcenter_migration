<#
.SYNOPSIS
Set Custom Attributes to VMs including vmFolder location and vNIC portgroup assignments. 
Mostly used for migrations between vCenters.

.DESCRIPTION
This script creates several custom attributes against the VMs which are useful for exporting and importing into another vCenter if you happen
to be migrating VMs between vCenters. This allows you to script out the reconnection of the vNICs to new DSwitches and move the VMs back into the same
folders that they were in before migrations. vmFolder contains the folder path starting with the datacenter. VNIC# represents each VM's network device
which then contains the network name string.

.PARAMETER Server
Specifies the vCenter FQDN

.PARAMETER WhatIf
A switch that specifies the whatif flags. "$false" by default.

.NOTES
Author: Scott Haas
Website: www.definebroken.com
Credit: Utilized get-vmfolderpath from http://kunaludapi.blogspot.com  

Changelog:
18-May-2017
 * Initial Script
21-Aug-2017
 * Adjusted script for public consumption on github


.EXAMPLE
Run a whatif scenario against vcenter.domain.com without setting anything.

PS> Set-VMAttrs-vmFolderandvNICs.ps1 -Server vcenter.domain.com -WhatIf

.EXAMPLE
Set the vmFolder and vNIC# attributes for real.

PS> Set-VMAttrs-vmFolderandvNICs.ps1 -Server vcenter.domain.com

.LINK
Reference: https://github.com/ScottHaas/vcenter-migration-scripts

#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true,HelpMessage="FQDN vCenter")]
    [ValidateNotNullOrEmpty()]
    [string]$server,

    [Parameter(Mandatory=$false,HelpMessage="What if option")]
    [switch]$WhatIf
)

#Functions
function Get-VMFolderPath {  
 <#  
 .SYNOPSIS  
 Get folder path of Virtual Machines  
 .DESCRIPTION  
 The function retrives complete folder Path from vcenter (Inventory >> Vms and Templates)  
 .NOTES   
 Author: Kunal Udapi  
 http://kunaludapi.blogspot.com
 Version 1  
 .PARAMETER N/a  
 No Parameters Required  
 .EXAMPLE  
  PS> Get-VM vmname | Get-VMFolderPath  
 .EXAMPLE  
  PS> Get-VM | Get-VMFolderPath  
 .EXAMPLE  
  PS> Get-VM | Get-VMFolderPath | Out-File c:\vmfolderPathlistl.txt  
 #>  
   Begin {} 
   Process {  
     foreach ($vm in $Input) {  
       $DataCenter = $vm | Get-Datacenter  
       $DataCenterName = $DataCenter.Name  
       #$VMname = $vm.Name  
       $VMname = ""
       $VMParentName = $vm.Folder  
       if ($VMParentName.Name -eq "vm") {  
         $FolderStructure = "{0}\{1}" -f $DataCenterName, $VMname  
         $FodlerStructure = $dataCenterName + "\"
         $FolderStructure  
         Continue  
       }#if ($VMParentName.Name -eq "vm")  
       else {  
         $FolderStructure = "{0}\{1}" -f $VMParentName.Name, $VMname  
         $VMParentID = Get-Folder -Id $VMParentName.ParentId  
         do {  
           $ParentFolderName = $VMParentID.Name  
           if ($ParentFolderName -eq "vm") {  
             $FolderStructure = "$DataCenterName\$FolderStructure"  
             $FolderStructure  
             break  
           } #if ($ParentFolderName -eq "vm")  
           $FolderStructure = "$ParentFolderName\$FolderStructure"  
           $VMParentID = Get-Folder -Id $VMParentID.ParentId  
         }   
         until ($VMParentName.ParentId -eq $DataCenter.Id)  
       } #else ($VMParentName.Name -eq "vm")  
     } 
   }   
   End {}   
 } 

#Connect
$viserver = connect-viserver $Server -ErrorAction Stop

#Main Code
$vms = get-vm -server $viserver
[System.Collections.ArrayList]$currVMCustomAttNames = @()
$currVMCustomAttNames += (get-customattribute -targetType VirtualMachine).Name

foreach ($vm in $vms){
    #vmFolder Attribute
    $newvmFolderValue = $vm|get-vmfolderpath
    if ($currVMCustomAttNames|?{$_ -eq "vmFolder"}){
        $currvmFolderValue = ($vm|get-annotation -customattribute "vmFolder").Value
        if ($currvmFolderValue -ne $newvmFolderValue){
            #write-host "curr: $currvmFolderValue - new: $newvmFolderValue"
            write-host "`nVM:$vm setting vmFolder: $newvmFolderValue"
            try{$null = set-annotation -entity $vm -CustomAttribute "vmFolder" -value $newvmFolderValue -ErrorVariable Err -Whatif:$whatif}catch{write-host "Error: $Err"}
        }
    } else {
        write-host "`nCreating custom attribute: vmFolder"
        try{$null = New-CustomAttribute -targettype VirtualMachine -name "vmFolder" -ErrorVariable Err -Whatif:$whatif}catch{write-host "Error: $Err"}
        $currVMCustomAttNames += "vmFolder"
        write-host "`nVM:$vm setting vmFolder: $newvmFolderValue"
        try{$null = set-annotation -entity $vm -CustomAttribute "vmFolder" -value $newvmFolderValue -ErrorVariable Err -Whatif:$whatif}catch{write-host "Error: $Err"}
    }

    #vNics
    #A number is added to each tag so vNIC0,vNIC1,vNIC2, etc
    $vmnics = get-networkadapter -vm $vm
    foreach ($vmnic in $vmnics){
        $vmname = $vm.name
        $networkvnic = "vNIC" + $vmnic.Name.split(" ")[-1]
        if (![string]::IsNullOrWhiteSpace($vmnic.NetworkName)){
            $networkname = $vmnic.NetworkName
            if ($currVMCustomAttNames|?{$_ -eq $networkvnic}){
               $currValue = ($vm|get-annotation -customattribute $networkvnic).value
               if ($currValue -ne $networkname){
                    write-host "VM:$vm setting $networkvnic`: $networkname"
                    try{$null = Set-Annotation -entity $vm -CustomAttribute $networkvnic -value $networkname -ErrorVariable Err -Whatif:$whatif}catch{write-host "Error: $Err"}
               }
            } else {
                write-host "`nCreating custom attribute: $networkvnic"
                try{$null = New-CustomAttribute -targettype VirtualMachine -name $networkvnic -ErrorVariable Err -Whatif:$whatif}catch{write-host "Error: $Err"}
                $currVMCustomAttNames += "$networkvnic"
                write-host "`nVM:$vm setting $networkvnic`: $networkname"
                try{$null = Set-Annotation -entity $vm -CustomAttribute $networkvnic -value $networkname -ErrorVariable Err -Whatif:$whatif}catch{write-host "Error: $Err"}
            }
        }
    }
}
write-host "Script Complete."
Disconnect-VIServer $viserver -confirm:$false