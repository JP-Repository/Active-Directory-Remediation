<#
.SYNOPSIS
    What-if check for unresolvable NS records in a specified DNS zone across multiple Domain Controllers.

.DESCRIPTION
    This script reads a list of Domain Controllers from a text file, queries the specified DNS zone for NS records,
    attempts to resolve each Name Server (NS) to an IP address, and identifies any NS records that cannot be resolved.
    Instead of removing them, it creates a “what-if” report listing the NS records that *would* be removed.

.NOTES
    Script Name    : Check-UnrecognizedNSRecords.ps1
    Version        : 0.1
    Author         : [Your Name]
    Approved By    : [Approver's Name]
    Date           : [Date]
    Purpose        : Identify potentially invalid NS records across DNS servers without actually deleting them.

.PREREQUISITES
    - ActiveDirectory PowerShell module (for Get-DnsServerResourceRecord)
    - Appropriate permissions to query DNS zones on Domain Controllers
    - Input file (DCList.txt) containing Domain Controller names, one per line

.PARAMETERS
    None (all paths and zone name are defined in variables at the start of the script)

.EXAMPLE
    Simply run the script:
    .\Check-UnrecognizedNSRecords.ps1
#>

# Start of Script

# Path to your text file with Domain Controller names (one per line)
$DCListPath = "C:\Temp\DCList.txt"

# DNS zone to process
$ZoneName = "contoso.com"

# Output report path
$ReportPath = "C:\Temp\Unrecognized_NS_WhatIf_Report.csv"

# Read Domain Controllers from the file
$DCs = Get-Content $DCListPath

# Prepare an array to collect what-if results
$whatIfResults = @()

foreach ($dc in $DCs) {
    Write-Host "`nProcessing Domain Controller: $dc"
    try {
        # Retrieve all NS records from the specified zone
        $nsRecords = Get-DnsServerResourceRecord -ComputerName $dc -ZoneName $ZoneName -RRType NS

        foreach ($record in $nsRecords) {
            $nsFQDN = $record.RecordData.NameServer
            try {
                # Attempt to resolve the NS FQDN to an IP address
                $ip = (Resolve-DnsName -Name $nsFQDN -Type A -ErrorAction Stop).IPAddress
                Write-Host "  $nsFQDN resolves to $ip - would be kept."
            } catch {
                # If resolution fails, log that it would be removed
                Write-Host "  $nsFQDN could NOT be resolved - would be REMOVED."
                $whatIfResults += [PSCustomObject]@{
                    DomainController = $dc
                    NameServer       = $nsFQDN
                    Action           = "Would be removed"
                }
            }
        }
    } catch {
        Write-Host "  ERROR: Could not process $dc. $_"
    }
}

# Export the what-if report if there are any unresolved NS records
if ($whatIfResults.Count -gt 0) {
    $whatIfResults | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
    Write-Host "`nWhat-if report exported to $ReportPath"
} else {
    Write-Host "`nNo unrecognized Name Server records found for removal."
}

# End of Script
