<# 
.SYNOPSIS
Import custom attributes for virtual machines and hosts from a JSON-formatted file
To be used with Export-HostsVMs-CustomAttributes.ps1

.DESCRIPTION
Imports all custom attributes for VMs and hosts from a JSON file

.PARAMETER Server
Specifies the vCenter FQDN

.PARAMETER TargetType
Optional parameter to limit the import to attributes defined on vCenter objects of the type:
VirtualMachine, VMHost, or All
Default is All.

.PARAMETER Filename
Input filename, defaulting to CustomAttr_<vCenter>_<cluster>.json

.NOTES
Authors: Bowen Lee, Joseph Jackson, and Scott Haas
Website: www.definebroken.com

Changelog:
9-Aug-2017
 * Initial Script
24-Aug-2017
 * Adjusted script for public consumption on github

.EXAMPLE
Importing only Host custom attributes for the cluster1 cluster.
PS> Import-HostsVMs-CustomAttributes.ps1 -Server vCenter.domain.com -Filename CustomAttr_vCenter_cluster1.json -TargetType VMHost

.EXAMPLE
Exporting all VM and Host custom attributes
PS> Export-HostsVMs-CustomAttributes.ps1 -Server vCenter.domain.com -Filename CustomAttr_vCenter_All.json

.LINK
Reference: https://github.com/ScottHaas/vcenter-migration-scripts

#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true,HelpMessage="Hostname of vCenter")]
    [ValidateNotNullOrEmpty()]
    [string]$Server,

    [Parameter(Mandatory=$false,HelpMessage="VirtualMachine, VMHost, or All")]
    [ValidateSet("VirtualMachine","VMHost","All")]
    [string]$TargetType = "All",

    [Parameter(Mandatory=$false,HelpMessage="Input filename")]
    [ValidateNotNullOrEmpty()]
    [string]$Filename = ''
)
   
# Build input filename if none was given on the command line
if ($Filename -eq '') {
    $Filename = 'CustomAttr_' + $Server.split(".")[0] + '_' + $Cluster + '.json'
}

#
# Colorized writing functions
#
function WriteNormal($text)  { Write-Host $text }
function WriteChanged($text) { Write-Host -ForegroundColor Green $text }
function WriteWarning($text) { Write-Host -ForegroundColor Yellow $text }
function WriteError($text)   { Write-Host -ForegroundColor Red $text }

#
# Function to read JSON file and handle errors
#
function ReadJSON([string]$filename) {
    $file = (Get-Content $filename -ErrorAction Stop) -join "`n"
    $json = ConvertFrom-Json -InputObject $file -ErrorVariable err
    if ($err) {
        Throw "Syntax error parsing JSON input file"
    }
    if (-not ($json.psobject.properties.name -Contains 'Attributes' -and
        $json.psobject.properties.name -Contains 'VirtualMachines' -and
        $json.psobject.properties.name -Contains 'VMHosts')) {
        Throw New-Object System.FormatException "JSON input missing Attributes, VirtualMachines and/or VMHosts keys"
    }
    return $json
}

# Parse JSON file
$json = ReadJSON($Filename)

# Connect to the vCenter
$viserver = Connect-VIServer $server -ErrorAction Stop

# Define any attributes not already present
foreach ($attr in $json.Attributes) {
    $existing = Get-CustomAttribute -Name $attr.Name -ErrorAction SilentlyContinue -ErrorVariable err
    if ($err) {
        WriteChanged "Creating custom attribute", $attr.Name, "for objects of type", $attr.TargetType
        $null = New-CustomAttribute -Name $attr.Name -TargetType $attr.TargetType
    } else {
        WriteNormal "Custom attribute already exists:", $attr.Name, "for", $attr.TargetType
    }
}

if ($TargetType -eq "VirtualMachine" -or $TargetType -eq "All") {
    foreach ($vmAttrs in $json.VirtualMachines) {
        WriteChanged "Setting attributes on VM", $vmAttrs.Name
        $vm = Get-VM -Name $vmAttrs.Name -Server $viserver
        $vmAttrs.Attributes.psobject.properties.ForEach({
            WriteChanged "Setting custom attribute", $_.Name, "to value", $_.Value, "on VM", $vmAttrs.Name
            $null = Set-Annotation -Entity $vm -CustomAttribute $_.Name -Value $_.value -Server $viserver -Confirm:$false
        })
    }
}

if ($TargetType -eq "VMHost" -or $TargetType -eq "All") {
    foreach ($hostAttrs in $json.VMHosts) {
        WriteChanged "Setting attributes on host", $hostAttrs.Name
        $vmhost = Get-VMHost -Name $hostAttrs.Name -Server $viserver
        $hostAttrs.Attributes.psobject.properties.ForEach({
            WriteChanged "Setting custom attribute", $_.Name, "to value", $_.Value, "on host", $hostAttrs.Name
            $null = Set-Annotation -Entity $vmhost -CustomAttribute $_.Name -Value $_.value -Server $viserver -Confirm:$false
        })
    }
}

# Drop the connection to the vCenter
Disconnect-VIServer –server $viserver -Confirm:$False