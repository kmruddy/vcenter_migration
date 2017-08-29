<# 
.SYNOPSIS
Export custom attributes for virtual machines and hosts to a JSON-formatted file
To be used with Import-HostsVMs-CustomAttributes.ps1

.DESCRIPTION
Exports all custom attributes for VMs and hosts to a JSON file to be used for migrations

.PARAMETER Server
Specifies the vCenter FQDN

.PARAMETER Cluster
Optional parameter that specifies the cluster name to operate on 
or "All" for all clusters. Default is all clusters.

.PARAMETER Filename
Optional output filename, defaulting to CustomAttr_<vCenter>_<cluster>.json

.NOTES
Authors: Bowen Lee, Joseph Jackson, and Scott Haas
Website: www.definebroken.com

Changelog:
9-Aug-2017
 * Initial Script
24-Aug-2017
 * Adjusted script for public consumption on github

.EXAMPLE
Exporting all VM and Host custom attributes for cluster cluster1

PS> Export-HostsVMs-CustomAttributes.ps1 -Server vCenter.domain.com -Cluster cluster1 -Filename CustomAttr_vCenter_cluster1.json

.EXAMPLE
Exporting all VM and Host custom attributes
PS> Export-HostsVMs-CustomAttributes.ps1 -Server vCenter.domain.com 

.LINK
Reference: https://github.com/ScottHaas/vcenter-migration-scripts

#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true,HelpMessage="FQDN of vCenter")]
    [ValidateNotNullOrEmpty()]
    [string]$Server,

    [Parameter(Mandatory=$false,HelpMessage="Cluster name")]
    [ValidateNotNullOrEmpty()]
    [string]$Cluster = "All",

    [Parameter(Mandatory=$false,HelpMessage="Output filename")]
    [ValidateNotNullOrEmpty()]
    [string]$Filename = ''
)
   
# Build output filename if none was given on the command line
if ($Filename -eq '') {
    $Filename = 'CustomAttr_' + $Server.split(".")[0] + '_' + $Cluster + '.json'
}

# Connect to the vCenter
$viserver = Connect-VIServer $server -ErrorAction Stop

# Select the specified cluster or all clusters
if ($Cluster -match 'All') {
    $allVMs   = Get-VM -ErrorAction Stop
    $allHosts = Get-VMHost -ErrorAction Stop
} else {
    $location = Get-Cluster $Cluster -Server $viserver -ErrorAction Stop
    $allVMs   = Get-VM -Location $location -ErrorAction Stop
    $allHosts = Get-VMHost -Location $location -ErrorAction Stop
}

# Gather all the custom attribute types for either VMs or hosts
# Convert the TargetType enum to a string to avoid saving the internal numeric identifier (.value__)
$attributes = Get-CustomAttribute -TargetType VirtualMachine,VMHost | Select Name, @{n='TargetType';e={$_.TargetType.ToString()}}

# Iterate over VMs found in a specific or all clusters
$vmsWithAttrs = $allVMs | Select Name, CustomFields | foreach {
    # Given a VM, iterate over its CustomFields, collecting any that have non-empty values into $attrs
    $attrs = @{}
    for ($i = 0; $i -lt $_.CustomFields.Count; $i++){
        $key   = $_.CustomFields.Keys[$i]
        $value = $_.CustomFields.Values[$i]
        if ($value -ne '') {
            $attrs[$key] = $value
        }
    }
    if ($attrs.Count -gt 0) {
        @{"Name" = $_.Name; "Attributes" = $attrs}
    }
}

# Iterate over hosts found in a specific or all clusters
$hostsWithAttrs = $allHosts | Select Name, CustomFields | foreach {
    # Given a host, iterate over its CustomFields, collecting any that have non-empty values into $attrs
    $attrs = @{}
    for ($i = 0; $i -lt $_.CustomFields.Count; $i++){
        $key   = $_.CustomFields.Keys[$i]
        $value = $_.CustomFields.Values[$i]
        if ($value -ne '') {            
            $attrs[$key] = $value
        }
    }
    if ($attrs.Count -gt 0) {
        @{"Name" = $_.Name; "Attributes" = $attrs}
    }
}

# Bundle the list of attributes, the VM/attribute values, and host/attribute values into a single object
# and export it as a JSON file
ConvertTo-Json -InputObject @{"Attributes" = $attributes; "VirtualMachines" = $vmsWithAttrs; "VMHosts" = $hostsWithAttrs} -Depth 3 | Out-File $Filename

# Drop the connection to the vCenter
Disconnect-VIServer –server $viserver -Confirm:$False