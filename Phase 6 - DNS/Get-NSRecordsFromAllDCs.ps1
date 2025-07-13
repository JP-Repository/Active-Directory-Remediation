<#
.SYNOPSIS
    Query all Domain Controllers for NS records in a DNS zone and attempt to resolve each NS record to an IP address.

.DESCRIPTION
    This script automatically retrieves the list of all Domain Controllers in the domain,
    queries each for NS records in a specified DNS zone, and attempts to resolve each Name Server (NS) to an IP address.
    The script logs which records resolved successfully and which could not be resolved, exporting the data to a CSV report.

.NOTES
    Script Name    : Get-NSRecordsFromAllDCs.ps1
    Version        : 0.1
    Author         : [Your Name]
    Approved By    : [Approver's Name]
    Date           : [Date]
    Purpose        : Inventory NS records from all DCs and validate resolution for troubleshooting or cleanup.

.PREREQUISITES
    - ActiveDirectory PowerShell module installed (for Get-ADDomainController)
    - DNS Server tools / DNS PowerShell module installed (for Get-DnsServerResourceRecord)
    - Permissions to query DNS zones on all Domain Controllers

.PARAMETERS
    None (all values are configured via variables at the start of the script)

.EXAMPLE
    .\Get-NSRecordsFromAllDCs.ps1
#>

# Start of Script

# Define the DNS zone to process
$ZoneName = "contoso.com"

# Get all Domain Controllers in the current domain
Write-Host "Getting all Domain Controllers in the domain..."
$DCs = (Get-ADDomainController -Filter *).HostName
Write-Host "Found $($DCs.Count) Domain Controllers.`n"

# Prepare an array to collect the results
$results = @()

foreach ($dc in $DCs) {
    Write-Host "Querying Domain Controller: $dc"
    try {
        # Retrieve NS records from the DNS zone on this Domain Controller
        $nsRecords = Get-DnsServerResourceRecord -ComputerName $dc -ZoneName $ZoneName -RRType NS
        Write-Host "  Found $($nsRecords.Count) NS records."
        
        foreach ($record in $nsRecords) {
            $nsFQDN = $record.RecordData.NameServer
            Write-Host "    Processing NS record: $nsFQDN"
            try {
                # Attempt to resolve the NS FQDN to an IP address
                $ip = (Resolve-DnsName -Name $nsFQDN -Type A -ErrorAction Stop).IPAddress
                Write-Host "      Resolved IP: $ip"
            } catch {
                $ip = "Unknown"
                Write-Host "      Could not resolve IP. Marked as Unknown."
            }

            # Log the result
            $results += [PSCustomObject]@{
                DomainController = $dc
                NameServer       = $nsFQDN
                IPAddress        = $ip
            }
        }
    } catch {
        # Log an error entry if the DC couldn't be queried
        Write-Host "  ERROR: Could not query NS records from $dc"
        $results += [PSCustomObject]@{
            DomainController = $dc
            NameServer       = "Error"
            IPAddress        = "Error"
        }
    }
    Write-Host ""
}

# Export the results to a CSV file
$ExportPath = "C:\Temp\AllDCs_NS_Records_With_IP.csv"
Write-Host "Exporting results to $ExportPath"
$results | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
Write-Host "Export complete."

# End of Script
