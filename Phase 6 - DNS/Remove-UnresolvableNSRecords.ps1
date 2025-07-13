<#
.SYNOPSIS
    Remove unresolvable NS records from a DNS zone across multiple DNS servers.

.DESCRIPTION
    This script reads a list of DNS servers from a text file, queries the specified DNS zone for NS records,
    attempts to resolve each Name Server (NS) to an IP address, and removes any NS records that cannot be resolved.
    All removed records are logged and exported to a CSV report for auditing.

.NOTES
    Script Name    : Remove-UnresolvableNSRecords.ps1
    Version        : 0.1
    Author         : [Your Name]
    Approved By    : [Approver's Name]
    Date           : [Date]
    Purpose        : Automate cleanup of stale NS records that no longer resolve to an IP address.

.PREREQUISITES
    - DNS Server tools / DNS PowerShell module installed
    - Permissions to query and modify DNS zones on the target DNS servers
    - Input file (DnsServerList.txt) with one DNS server name per line

.PARAMETERS
    None (all paths and zone name are set in variables at the start of the script)

.EXAMPLE
    .\Remove-UnresolvableNSRecords.ps1
#>

# Start of Script

# Path to text file containing DNS server names (one per line)
$DnsServers = Get-Content "C:\Temp\DnsServerList.txt"

# DNS zone to check and clean up
$ZoneName = "contoso.com"

# Path to export the removal log
$ExportPath = "C:\Temp\Removed_NS_Records.csv"

# Array to collect details of removed NS records
$removedRecords = @()

foreach ($DnsServer in $DnsServers) {
    Write-Host "`nProcessing DNS server: $DnsServer"
    try {
        # Retrieve NS records from the zone
        $nsRecords = Get-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $ZoneName -RRType NS

        foreach ($record in $nsRecords) {
            $nsFQDN = $record.RecordData.NameServer
            try {
                # Attempt to resolve the NS FQDN
                $ip = (Resolve-DnsName -Name $nsFQDN -Type A -ErrorAction Stop).IPAddress
                Write-Host "$nsFQDN resolves to $ip. Keeping."
            } catch {
                # Resolution failed - remove the NS record
                Write-Host "$nsFQDN could NOT be resolved. REMOVING from zone."
                Remove-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $ZoneName -InputObject $record -Force

                # Log the removal
                $removedRecords += [PSCustomObject]@{
                    DnsServer      = $DnsServer
                    NameServerFQDN = $nsFQDN
                    RemovalTime    = (Get-Date)
                }
            }
        }
    } catch {
        Write-Host "ERROR: Could not process DNS server $DnsServer. Details: $_"
    }
}

# Export the removal log to CSV if any records were removed
if ($removedRecords.Count -gt 0) {
    $removedRecords | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
    Write-Host "`nRemoval report exported to $ExportPath"
} else {
    Write-Host "`nNo NS records were removed."
}

# End of Script
