<#
.SYNOPSIS
    Checks the current SCHANNEL TLS registry settings (TLS 1.0, 1.1, 1.2) on all Domain Controllers
    and outputs both CSV and HTML reports.

.DESCRIPTION
    This script:
        - Discovers all Domain Controllers in the current Active Directory domain using Get-ADDomainController.
        - Remotely queries the SCHANNEL TLS registry keys on each DC for:
              TLS 1.0, TLS 1.1, TLS 1.2
          and for both:
              Client, Server roles.
        - Collects the Enabled and DisabledByDefault values (if present).
        - Exports:
              * A CSV file with raw values
              * A formatted HTML report with color-coded Secure / Not Secure / Unknown states,
                grouped by Domain Controller (DC name shown once as a header row).

    Reports are saved under:
        C:\Temp\TLS Remediation Results

    The HTML report is automatically opened in the default browser when the script finishes.

.NOTES
    Script Name    : Get-TLSVersion_AllDCs.ps1
    Version        : 1.1
    Author         : Jonathan Preetham
    Approved By    : [Approver's Name]
    Date           : 2025-07-07
    Purpose        : To gather and document existing SCHANNEL TLS registry configuration on all
                     Domain Controllers for audit, troubleshooting, or pre-hardening assessment,
                     with both CSV and human-friendly HTML output.

.PREREQUISITES
    - RSAT / ActiveDirectory PowerShell module installed on the system running this script.
    - Remote PowerShell (WinRM) access enabled and allowed to each Domain Controller.
    - Sufficient permissions to:
          * Query Active Directory for Domain Controllers.
          * Read remote registry keys on each DC.
    - Output directory base path: C:\Temp
      (The script will create "TLS Remediation Results" under C:\Temp if it does not exist.)

.PARAMETERS
    None
        This script takes no parameters.
        Use -Verbose for detailed per-server and per-protocol progress output.

.EXAMPLE
    PS C:\> .\Get-TLSVersion_AllDCs.ps1

    Runs the script with default output behavior (minimal console output) and exports
    the result CSV and HTML files to:
        C:\Temp\TLS Remediation Results\DC_TLS_Check_Result_yyyyMMdd_HHmmss.csv
        C:\Temp\TLS Remediation Results\DC_TLS_Check_Result_yyyyMMdd_HHmmss.html

.EXAMPLE
    PS C:\> .\Get-TLSVersion_AllDCs.ps1 -Verbose

    Runs the script with verbose logging, showing detailed status for each Domain Controller
    and each protocol/role combination, and exports the results to the same folder/path pattern.
#>

#Requires -Modules ActiveDirectory

[CmdletBinding()]
param()

# Start of Script

# Get list of all Domain Controllers dynamically
try {
    $dcs = Get-ADDomainController -Filter * | Select-Object -ExpandProperty HostName
    if (-not $dcs) {
        Write-Error "No domain controllers found. Exiting script."
        return
    }
}
catch {
    Write-Error "Failed to get Domain Controllers. Ensure RSAT tools are installed and you have permissions."
    return
}

$protocols = @("TLS 1.0", "TLS 1.1", "TLS 1.2")
$roles     = @("Client", "Server")
$results   = @()

$totalStart = Get-Date
Write-Verbose "TLS registry check started at $($totalStart.ToString('yyyy-MM-dd HH:mm:ss'))"

foreach ($server in $dcs) {

    # Progress bar for current server
    $index = [array]::IndexOf($dcs, $server) + 1
    $total = $dcs.Count

    Write-Progress `
        -Activity "Checking TLS Configuration Across Domain Controllers" `
        -Status "Processing $server ($index of $total)" `
        -PercentComplete (($index / $total) * 100)

    $serverStart = Get-Date
    Write-Verbose "------------------------------------------------------------"
    Write-Verbose "Checking server: $server | Start time: $($serverStart.ToString('yyyy-MM-dd HH:mm:ss'))"

    foreach ($protocol in $protocols) {
        foreach ($role in $roles) {
            Write-Verbose "  Checking protocol: $protocol ($role)"
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$protocol\$role"

            try {
                $output = Invoke-Command -ComputerName $server -ScriptBlock {
                    param ($path)

                    $enabled  = $null
                    $disabled = $null

                    if (Test-Path $path) {
                        $enabled = Get-ItemProperty -Path $path -Name Enabled -ErrorAction SilentlyContinue |
                                   Select-Object -ExpandProperty Enabled -ErrorAction SilentlyContinue

                        $disabled = Get-ItemProperty -Path $path -Name DisabledByDefault -ErrorAction SilentlyContinue |
                                    Select-Object -ExpandProperty DisabledByDefault -ErrorAction SilentlyContinue
                    }

                    return [PSCustomObject]@{
                        Enabled           = $enabled
                        DisabledByDefault = $disabled
                    }
                } -ArgumentList $regPath -ErrorAction Stop

                $results += [PSCustomObject]@{
                    ComputerName      = $server
                    Protocol          = $protocol
                    Role              = $role
                    Enabled           = $output.Enabled
                    DisabledByDefault = $output.DisabledByDefault
                }
            }
            catch {
                Write-Verbose "  Error connecting to $server or reading $protocol ($role)"
                $results += [PSCustomObject]@{
                    ComputerName      = $server
                    Protocol          = $protocol
                    Role              = $role
                    Enabled           = "Error"
                    DisabledByDefault = "Error"
                }
            }
        }
    }

    $serverEnd = Get-Date
    $duration  = New-TimeSpan -Start $serverStart -End $serverEnd
    Write-Verbose "Finished checking server: $server | End time: $($serverEnd.ToString('yyyy-MM-dd HH:mm:ss')) | Duration: $($duration.ToString())"
}

$totalEnd      = Get-Date
$totalDuration = New-TimeSpan -Start $totalStart -End $totalEnd
Write-Verbose "------------------------------------------------------------"
Write-Verbose "All servers checked. Total duration: $($totalDuration.ToString())"

# ---------- Output folder & file paths ----------
$basePath = "C:\Temp\TLS Remediation Results"
New-Item -Path $basePath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvPath   = Join-Path $basePath "DC_TLS_Check_Result_$timestamp.csv"
$htmlPath  = Join-Path $basePath "DC_TLS_Check_Result_$timestamp.html"

# Export CSV
$results | Export-Csv -NoTypeInformation -Path $csvPath
Write-Verbose "CSV results exported to $csvPath"

# ---------- Build HTML report ----------

# Determine domain (for header info)
try {
    $domain = (Get-ADDomain).DNSRoot
}
catch {
    $domain = "Unknown domain"
}

$generatedOn = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# HTML header & styles
$htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <title>Domain Controllers TLS Configuration Report</title>
    <style>
        body {
            font-family: Segoe UI, Arial, sans-serif;
            background-color: #f5f5f5;
            margin: 0;
            padding: 20px;
        }
        .report-container {
            max-width: 1200px;
            margin: 0 auto;
            background-color: #ffffff;
            border-radius: 8px;
            padding: 20px 24px;
            box-shadow: 0 2px 6px rgba(0,0,0,0.1);
        }
        h1 {
            font-size: 22px;
            margin-bottom: 4px;
        }
        .subtitle {
            color: #555;
            font-size: 13px;
            margin-bottom: 16px;
        }
        .meta {
            font-size: 12px;
            color: #777;
            margin-bottom: 16px;
        }
        .legend {
            font-size: 12px;
            margin-bottom: 16px;
        }
        .legend span {
            display: inline-block;
            margin-right: 12px;
        }
        .badge {
            display: inline-block;
            padding: 2px 8px;
            font-size: 11px;
            border-radius: 10px;
            font-weight: 600;
        }
        .status-secure {
            background-color: #d4edda;
            color: #155724;
        }
        .status-insecure {
            background-color: #f8d7da;
            color: #721c24;
        }
        .status-unknown {
            background-color: #e2e3e5;
            color: #383d41;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 12px;
        }
        thead {
            background-color: #f0f0f0;
        }
        th, td {
            padding: 8px 10px;
            border-bottom: 1px solid #e0e0e0;
            text-align: left;
            white-space: nowrap;
        }
        th {
            font-weight: 600;
            font-size: 12px;
        }
        tbody tr:nth-child(even) {
            background-color: #fafafa;
        }
        .center {
            text-align: center;
        }
        .value-null {
            color: #999;
            font-style: italic;
        }
    </style>
</head>
<body>
    <div class="report-container">
        <h1>Domain Controllers TLS Configuration Report</h1>
        <div class="subtitle">Summary of SCHANNEL TLS registry settings across all Domain Controllers</div>
        <div class="meta">
            Generated on: $generatedOn<br />
            Domain: $domain
        </div>

        <div class="legend">
            <strong>Legend:</strong>
            <span><span class="badge status-secure">Secure</span> TLS 1.2 enabled, older protocols disabled (expected state)</span>
            <span><span class="badge status-insecure">Not Secure</span> Insecure / legacy protocol enabled or TLS 1.2 missing</span>
            <span><span class="badge status-unknown">Unknown</span> Registry keys missing or error reading values</span>
        </div>

        <table>
            <thead>
                <tr>
                    <th>Domain Controller</th>
                    <th>Protocol</th>
                    <th>Role</th>
                    <th>Enabled</th>
                    <th>DisabledByDefault</th>
                    <th class="center">State</th>
                    <th>Notes</th>
                </tr>
            </thead>
            <tbody>
"@

# Build table rows (grouped by DC so name is shown once)
$htmlRows = ""

$dcGroups = $results | Group-Object ComputerName

foreach ($dcGroup in $dcGroups) {

    $dcName = $dcGroup.Name

    # DC header row spanning all columns
    $htmlRows += @"
                <tr style='background-color:#e8e8e8; font-weight:bold;'>
                    <td colspan='7'>$dcName</td>
                </tr>
"@

    foreach ($row in $dcGroup.Group) {

        $protocol = $row.Protocol
        $role     = $row.Role
        $enabled  = $row.Enabled
        $disabled = $row.DisabledByDefault

        # Display values
        $enabledDisplay  = if ($null -eq $enabled  -or $enabled  -eq "") { "N/A" } else { "$enabled" }
        $disabledDisplay = if ($null -eq $disabled -or $disabled -eq "") { "N/A" } else { "$disabled" }

        $enabledClass  = if ($enabledDisplay  -eq "N/A") { "value-null" } else { "" }
        $disabledClass = if ($disabledDisplay -eq "N/A") { "value-null" } else { "" }

        # Determine state: Secure / Not Secure / Unknown
        $stateClass = "status-unknown"
        $stateText  = "Unknown"
        $notes      = "Key missing, not set, or error reading values."

        # If there was an explicit error recorded
        if ($enabledDisplay -eq "Error" -or $disabledDisplay -eq "Error") {
            $stateClass = "status-unknown"
            $stateText  = "Unknown"
            $notes      = "Error reading registry values on this server."
        }
        else {
            # Try to interpret as numeric where possible
            $enabledNumeric  = $null
            $disabledNumeric = $null

            [void][int]::TryParse("$enabledDisplay",  [ref]$enabledNumeric)
            [void][int]::TryParse("$disabledDisplay", [ref]$disabledNumeric)

            if ($enabledDisplay -ne "N/A" -or $disabledDisplay -ne "N/A") {

                if ($protocol -eq "TLS 1.2") {
                    # Secure if TLS 1.2 is properly enabled (Enabled=1, DisabledByDefault=0)
                    if ($enabledNumeric -eq 1 -and $disabledNumeric -eq 0) {
                        $stateClass = "status-secure"
                        $stateText  = "Secure"
                        $notes      = "Expected modern protocol configuration (TLS 1.2 enabled)."
                    }
                    else {
                        $stateClass = "status-insecure"
                        $stateText  = "Not Secure"
                        $notes      = "TLS 1.2 not configured as expected."
                    }
                }
                elseif ($protocol -in @("TLS 1.0", "TLS 1.1")) {
                    # Secure if legacy TLS is disabled (Enabled=0, DisabledByDefault=1)
                    if ($enabledNumeric -eq 0 -and $disabledNumeric -eq 1) {
                        $stateClass = "status-secure"
                        $stateText  = "Secure"
                        $notes      = "Legacy protocol disabled for this role."
                    }
                    else {
                        $stateClass = "status-insecure"
                        $stateText  = "Not Secure"
                        $notes      = "Legacy protocol still enabled or not fully disabled."
                    }
                }
            }
        }

        # Detail row (first column blank because DC name is in header row)
        $htmlRows += @"
                <tr>
                    <td></td>
                    <td>$protocol</td>
                    <td>$role</td>
                    <td class="$enabledClass">$enabledDisplay</td>
                    <td class="$disabledClass">$disabledDisplay</td>
                    <td class="center"><span class="badge $stateClass">$stateText</span></td>
                    <td>$notes</td>
                </tr>
"@
    }
}

# Close HTML
$htmlFooter = @"
            </tbody>
        </table>
    </div>
</body>
</html>
"@

$htmlContent = $htmlHeader + $htmlRows + $htmlFooter

# Write HTML to file
Set-Content -Path $htmlPath -Value $htmlContent -Encoding UTF8
Write-Verbose "HTML report exported to $htmlPath"

# Open HTML report automatically
Start-Process $htmlPath

# End of Script
