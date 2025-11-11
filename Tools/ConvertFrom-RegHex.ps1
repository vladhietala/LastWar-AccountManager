<#
.SYNOPSIS
Converts hexadecimal values from registry .reg files to readable text format.

.DESCRIPTION
This utility script parses Windows Registry .reg files and decodes all registry value types
to human-readable text. It automatically detects encoding and formats the output appropriately.

Supported Registry Types:
- REG_SZ (string) - Regular string values (appears as "name"="value" or hex(1))
- REG_EXPAND_SZ (hex(2)) - Expandable strings with environment variables
- REG_BINARY (hex or hex(3)) - Binary data
- REG_DWORD (dword:00000000) - 32-bit integers
- REG_QWORD (hex(b)) - 64-bit integers
- REG_MULTI_SZ (hex(7)) - Multiple null-terminated strings
- REG_NONE (hex(0)) - No defined value type
- REG_RESOURCE_LIST (hex(8)) - Resource list data

Encoding Detection:
- UTF-16 LE (most common for Windows strings)
- UTF-8 strings
- JSON (automatically parsed and formatted)
- DWORD/QWORD (shown in decimal and hexadecimal)
- Binary data (hex dump)

.PARAMETER RegFilePath
Path to the .reg file to analyze. Must be a valid .reg file from the Accounts/ folder.

.PARAMETER OutputFile
Optional path to save the decoded output. If not specified, outputs to console only.

.PARAMETER Format
Output format: 'Text' (default), 'Json', or 'Detailed'
- Text: Simple key=value pairs
- Json: Structured JSON output
- Detailed: Includes hex dump alongside decoded text

.PARAMETER ShowKeyNames
Show the simplified key names (removing _hXXXXXXXXXX suffixes that Unity PlayerPrefs adds)

.EXAMPLE
.\Tools\ConvertFrom-RegHex.ps1 -RegFilePath ".\Accounts\Vlad.reg"
Decodes all hex values from Vlad.reg and displays in console

.EXAMPLE
.\Tools\ConvertFrom-RegHex.ps1 -RegFilePath ".\Accounts\Vlad.reg" -OutputFile ".\decoded.txt"
Decodes hex values and saves output to decoded.txt

.EXAMPLE
.\Tools\ConvertFrom-RegHex.ps1 -RegFilePath ".\Accounts\Vlad.reg" -Format Json
Outputs decoded values as structured JSON

.EXAMPLE
.\Tools\ConvertFrom-RegHex.ps1 -RegFilePath ".\Accounts\Vlad.reg" -ShowKeyNames
Shows simplified key names by removing Unity's _hXXXXXXXXXX hash suffixes

.NOTES
Created for LastWar-AccountManager project to help inspect registry data.
Useful for debugging account-specific values and understanding game state.

Unity PlayerPrefs Hash Suffixes:
Unity adds _hXXXXXXXXXX suffixes to registry keys to avoid issues with special characters.
The hash is computed from the key name and remains constant across all accounts.
Use -ShowKeyNames to see the original key names without these suffixes.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateScript({
        if (-not (Test-Path $_)) {
            throw "File not found: $_"
        }
        if ($_ -notmatch '\.reg$') {
            throw "File must be a .reg file: $_"
        }
        $true
    })]
    [string]$RegFilePath,

    [Parameter(Mandatory = $false)]
    [string]$OutputFile,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Text', 'Json', 'Detailed')]
    [string]$Format = 'Text',

    [Parameter(Mandatory = $false)]
    [switch]$ShowKeyNames
)

#Requires -Version 7.0

# Function to convert hex bytes to string with multiple encoding attempts
function ConvertFrom-HexBytes {
    param(
        [byte[]]$Bytes,
        [string]$ValueName
    )

    $result = @{
        ValueName = $ValueName
        RawHex = ($Bytes | ForEach-Object { $_.ToString('X2') }) -join ' '
        ByteCount = $Bytes.Count
        DecodedText = $null
        DecodedJson = $null
        Encoding = 'Unknown'
        IsBinary = $false
    }

    # Try UTF-16 LE (most common for Windows registry strings)
    try {
        $utf16Text = [System.Text.Encoding]::Unicode.GetString($Bytes).TrimEnd([char]0)
        if ($utf16Text -match '^[\x20-\x7E\s\r\n]+$' -or $utf16Text -match '[а-яА-Я]') {
            $result.DecodedText = $utf16Text
            $result.Encoding = 'UTF-16 LE'

            # Try parsing as JSON
            try {
                $jsonObj = $utf16Text | ConvertFrom-Json -ErrorAction Stop
                $result.DecodedJson = $jsonObj
            }
            catch {
                # Not valid JSON, that's okay
            }

            return $result
        }
    }
    catch {
        # UTF-16 decode failed, try next
    }

    # Try UTF-8
    try {
        $utf8Text = [System.Text.Encoding]::UTF8.GetString($Bytes).TrimEnd([char]0)
        if ($utf8Text -match '^[\x20-\x7E\s\r\n]+$') {
            $result.DecodedText = $utf8Text
            $result.Encoding = 'UTF-8'

            # Try parsing as JSON
            try {
                $jsonObj = $utf8Text | ConvertFrom-Json -ErrorAction Stop
                $result.DecodedJson = $jsonObj
            }
            catch {
                # Not valid JSON, that's okay
            }

            return $result
        }
    }
    catch {
        # UTF-8 decode failed
    }

    # Check if it's a DWORD (4 bytes)
    if ($Bytes.Count -eq 4) {
        $dwordValue = [BitConverter]::ToUInt32($Bytes, 0)
        $result.DecodedText = "DWORD: $dwordValue (0x{0:X8})" -f $dwordValue
        $result.Encoding = 'DWORD'
        return $result
    }

    # If all else fails, it's binary data
    $result.IsBinary = $true
    $result.DecodedText = "[Binary data - {0} bytes]" -f $Bytes.Count
    return $result
}

# Function to convert hex string from .reg file to bytes
function ConvertFrom-RegHexString {
    param(
        [string]$HexString
    )

    # Remove any backslashes and whitespace (line continuations)
    $cleanHex = $HexString -replace '[\\,\s]', ''

    # Convert pairs of hex characters to bytes
    $bytes = @()
    for ($i = 0; $i -lt $cleanHex.Length; $i += 2) {
        if ($i + 1 -lt $cleanHex.Length) {
            $hexPair = $cleanHex.Substring($i, 2)
            $bytes += [Convert]::ToByte($hexPair, 16)
        }
    }

    return $bytes
}

# Main processing
Write-Host "🔍 Analyzing registry file: " -NoNewline
Write-Host $RegFilePath -ForegroundColor Cyan

$regContent = Get-Content -Path $RegFilePath -Raw -Encoding Unicode

# Extract registry key path
if ($regContent -match '\[([^\]]+)\]') {
    $registryKey = $matches[1]
    Write-Host "📝 Registry Key: " -NoNewline
    Write-Host $registryKey -ForegroundColor Yellow
    Write-Host ""
}

# Parse all registry values (hex, dword, qword, string)
$allValues = @()

# Pattern for hex values: hex, hex(0), hex(1), hex(2), hex(3), hex(7), hex(8), hex(b)
$hexPattern = '"([^"]+)"=hex(\([0-9a-fb]\))?:([0-9a-f,\\,\s]+)'
$hexMatches = [regex]::Matches($regContent, $hexPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)

foreach ($match in $hexMatches) {
    $allValues += @{
        ValueName = $match.Groups[1].Value
        Type = if ($match.Groups[2].Success) { "hex$($match.Groups[2].Value)" } else { "hex" }
        RawData = $match.Groups[3].Value
        IsHex = $true
    }
}

# Pattern for DWORD values: dword:00000000
$dwordPattern = '"([^"]+)"=dword:([0-9a-f]{8})'
$dwordMatches = [regex]::Matches($regContent, $dwordPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

foreach ($match in $dwordMatches) {
    $allValues += @{
        ValueName = $match.Groups[1].Value
        Type = "dword"
        RawData = $match.Groups[2].Value
        IsHex = $false
    }
}

# Pattern for QWORD values: hex(b):0000000000000000
# Already captured by hex pattern above

# Pattern for string values: "name"="value"
$stringPattern = '"([^"]+)"="([^"]*)"'
$stringMatches = [regex]::Matches($regContent, $stringPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)

foreach ($match in $stringMatches) {
    $allValues += @{
        ValueName = $match.Groups[1].Value
        Type = "string"
        RawData = $match.Groups[2].Value
        IsHex = $false
    }
}

if ($allValues.Count -eq 0) {
    Write-Host "⚠️  No registry values found in file" -ForegroundColor Yellow
    return
}

Write-Host "Found $($allValues.Count) registry value(s)`n" -ForegroundColor Green

$decodedValues = @()

foreach ($value in $allValues) {
    $valueName = $value.ValueName
    $valueType = $value.Type
    $rawData = $value.RawData

    Write-Verbose "Processing: $valueName (type: $valueType)"

    $decoded = $null

    if ($value.IsHex) {
        # Parse hex bytes
        $bytes = ConvertFrom-RegHexString -HexString $rawData

        # Decode based on registry type
        switch ($valueType) {
            "hex" {
                # REG_NONE or REG_BINARY
                $decoded = ConvertFrom-HexBytes -Bytes $bytes -ValueName $valueName
                $decoded.RegistryType = "REG_BINARY"
            }
            "hex(0)" {
                # REG_NONE
                $decoded = ConvertFrom-HexBytes -Bytes $bytes -ValueName $valueName
                $decoded.RegistryType = "REG_NONE"
            }
            "hex(1)" {
                # REG_SZ (null-terminated string)
                $decoded = ConvertFrom-HexBytes -Bytes $bytes -ValueName $valueName
                $decoded.RegistryType = "REG_SZ"
            }
            "hex(2)" {
                # REG_EXPAND_SZ (expandable string with environment variables)
                $decoded = ConvertFrom-HexBytes -Bytes $bytes -ValueName $valueName
                $decoded.RegistryType = "REG_EXPAND_SZ"
            }
            "hex(3)" {
                # REG_BINARY
                $decoded = ConvertFrom-HexBytes -Bytes $bytes -ValueName $valueName
                $decoded.RegistryType = "REG_BINARY"
            }
            "hex(7)" {
                # REG_MULTI_SZ (multiple strings separated by nulls)
                $decoded = ConvertFrom-HexBytes -Bytes $bytes -ValueName $valueName
                $decoded.RegistryType = "REG_MULTI_SZ"
                # Try to split by null terminators
                if ($decoded.DecodedText -and $decoded.Encoding -eq 'UTF-16 LE') {
                    $strings = $decoded.DecodedText -split "`0" | Where-Object { $_ -ne '' }
                    if ($strings.Count -gt 1) {
                        $decoded.MultiStrings = $strings
                        $decoded.DecodedText = "Multiple strings: " + ($strings -join " | ")
                    }
                }
            }
            "hex(8)" {
                # REG_RESOURCE_LIST
                $decoded = ConvertFrom-HexBytes -Bytes $bytes -ValueName $valueName
                $decoded.RegistryType = "REG_RESOURCE_LIST"
            }
            "hex(b)" {
                # REG_QWORD (64-bit integer)
                if ($bytes.Count -eq 8) {
                    $qwordValue = [BitConverter]::ToUInt64($bytes, 0)
                    $decoded = @{
                        ValueName = $valueName
                        RawHex = ($bytes | ForEach-Object { $_.ToString('X2') }) -join ' '
                        ByteCount = 8
                        DecodedText = "QWORD: $qwordValue (0x{0:X16})" -f $qwordValue
                        DecodedJson = $null
                        Encoding = 'QWORD'
                        RegistryType = 'REG_QWORD'
                        IsBinary = $false
                    }
                }
                else {
                    $decoded = ConvertFrom-HexBytes -Bytes $bytes -ValueName $valueName
                    $decoded.RegistryType = "REG_QWORD"
                }
            }
            default {
                $decoded = ConvertFrom-HexBytes -Bytes $bytes -ValueName $valueName
                $decoded.RegistryType = "Unknown ($valueType)"
            }
        }
    }
    else {
        # Non-hex values (dword, string)
        switch ($valueType) {
            "dword" {
                $dwordValue = [Convert]::ToUInt32($rawData, 16)
                $decoded = @{
                    ValueName = $valueName
                    RawHex = $rawData
                    ByteCount = 4
                    DecodedText = "DWORD: $dwordValue (0x{0:X8})" -f $dwordValue
                    DecodedJson = $null
                    Encoding = 'DWORD'
                    RegistryType = 'REG_DWORD'
                    IsBinary = $false
                }
            }
            "string" {
                $decoded = @{
                    ValueName = $valueName
                    RawHex = $null
                    ByteCount = $rawData.Length
                    DecodedText = $rawData
                    DecodedJson = $null
                    Encoding = 'String'
                    RegistryType = 'REG_SZ'
                    IsBinary = $false
                }
                # Try parsing as JSON
                try {
                    $jsonObj = $rawData | ConvertFrom-Json -ErrorAction Stop
                    $decoded.DecodedJson = $jsonObj
                }
                catch {
                    # Not valid JSON
                }
            }
        }
    }

    # Add simplified name if applicable
    if ($valueName -match '^(.+)_h\d+$') {
        $decoded.SimpleName = $matches[1]
    }

    $decodedValues += $decoded

    # Display based on format
    switch ($Format) {
        'Text' {
            Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor DarkGray
            Write-Host "📌 " -NoNewline -ForegroundColor Blue

            # Show simplified key name if requested
            if ($ShowKeyNames -and $valueName -match '^(.+)_h\d+$') {
                $simpleName = $matches[1]
                Write-Host $simpleName -ForegroundColor Cyan
                Write-Host "   Full name: " -NoNewline -ForegroundColor DarkGray
                Write-Host $valueName -ForegroundColor DarkGray
            }
            else {
                Write-Host $valueName -ForegroundColor Cyan
            }
            Write-Host "   Type: " -NoNewline
            Write-Host $decoded.RegistryType -ForegroundColor Magenta
            Write-Host "   Encoding: " -NoNewline
            Write-Host $decoded.Encoding -ForegroundColor Yellow
            Write-Host "   Bytes: " -NoNewline
            Write-Host $decoded.ByteCount -ForegroundColor Gray
            Write-Host ""

            if ($decoded.MultiStrings) {
                Write-Host "   📄 Multiple Strings:" -ForegroundColor Green
                foreach ($str in $decoded.MultiStrings) {
                    Write-Host "      • $str" -ForegroundColor White
                }
            }
            elseif ($decoded.DecodedJson) {
                Write-Host "   📄 JSON Content:" -ForegroundColor Green
                $decoded.DecodedJson | ConvertTo-Json -Depth 10 | Write-Host -ForegroundColor White
            }
            elseif (-not $decoded.IsBinary) {
                Write-Host "   📄 Content:" -ForegroundColor Green
                Write-Host "   $($decoded.DecodedText)" -ForegroundColor White
            }
            else {
                Write-Host "   ⚠️  $($decoded.DecodedText)" -ForegroundColor DarkYellow
            }
            Write-Host ""
        }

        'Detailed' {
            Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor DarkGray
            Write-Host "📌 " -NoNewline -ForegroundColor Blue

            # Show simplified key name if requested
            if ($ShowKeyNames -and $valueName -match '^(.+)_h\d+$') {
                $simpleName = $matches[1]
                Write-Host $simpleName -ForegroundColor Cyan
                Write-Host "   Full name: " -NoNewline -ForegroundColor DarkGray
                Write-Host $valueName -ForegroundColor DarkGray
            }
            else {
                Write-Host $valueName -ForegroundColor Cyan
            }
            Write-Host "   Type: " -NoNewline
            Write-Host $decoded.RegistryType -ForegroundColor Magenta
            Write-Host "   Encoding: " -NoNewline
            Write-Host $decoded.Encoding -ForegroundColor Yellow
            Write-Host "   Bytes: " -NoNewline
            Write-Host $decoded.ByteCount -ForegroundColor Gray
            Write-Host ""

            if ($decoded.RawHex) {
                Write-Host "   🔢 Hex Dump:" -ForegroundColor Magenta
                # Format hex dump in rows of 16 bytes for better readability
                $hexBytes = $decoded.RawHex -split ' '
                for ($i = 0; $i -lt $hexBytes.Count; $i += 16) {
                    $row = $hexBytes[$i..[Math]::Min($i + 15, $hexBytes.Count - 1)] -join ' '
                    Write-Host "   $row" -ForegroundColor DarkGray
                }
                Write-Host ""
            }

            if ($decoded.MultiStrings) {
                Write-Host "   📄 Multiple Strings:" -ForegroundColor Green
                foreach ($str in $decoded.MultiStrings) {
                    Write-Host "      • $str" -ForegroundColor White
                }
            }
            elseif ($decoded.DecodedJson) {
                Write-Host "   📄 JSON Content:" -ForegroundColor Green
                $decoded.DecodedJson | ConvertTo-Json -Depth 10 | Write-Host -ForegroundColor White
            }
            elseif (-not $decoded.IsBinary) {
                Write-Host "   📄 Content:" -ForegroundColor Green
                Write-Host "   $($decoded.DecodedText)" -ForegroundColor White
            }
            else {
                Write-Host "   ⚠️  $($decoded.DecodedText)" -ForegroundColor DarkYellow
            }
            Write-Host ""
        }
    }
}

# JSON output format
if ($Format -eq 'Json') {
    $jsonOutput = @{
        SourceFile = $RegFilePath
        RegistryKey = $registryKey
        ValueCount = $decodedValues.Count
        Values = $decodedValues
    }

    $jsonString = $jsonOutput | ConvertTo-Json -Depth 10

    # Output to console
    $jsonString | Write-Host

    # If OutputFile specified with JSON format, save JSON directly
    if ($OutputFile) {
        $jsonString | Out-File -FilePath $OutputFile -Encoding UTF8
        Write-Host "`n💾 JSON output saved to: " -NoNewline
        Write-Host $OutputFile -ForegroundColor Green
    }
}

# Save to file if requested (Text/Detailed formats)
if ($OutputFile -and $Format -ne 'Json') {
    $outputContent = @"
Registry File: $RegFilePath
Registry Key: $registryKey
Decoded at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

═══════════════════════════════════════════════════════════

"@

    foreach ($decoded in $decodedValues) {
        $outputContent += @"
Value Name: $($decoded.ValueName)
Registry Type: $($decoded.RegistryType)
Encoding: $($decoded.Encoding)
Byte Count: $($decoded.ByteCount)

"@

        if ($Format -eq 'Detailed' -and $decoded.RawHex) {
            $outputContent += "Hex Dump:`n$($decoded.RawHex)`n`n"
        }

        if ($decoded.MultiStrings) {
            $outputContent += "Multiple Strings:`n"
            foreach ($str in $decoded.MultiStrings) {
                $outputContent += "  • $str`n"
            }
        }
        elseif ($decoded.DecodedJson) {
            $outputContent += "JSON Content:`n"
            $outputContent += ($decoded.DecodedJson | ConvertTo-Json -Depth 10)
            $outputContent += "`n"
        }
        elseif (-not $decoded.IsBinary) {
            $outputContent += "Content:`n$($decoded.DecodedText)`n"
        }
        else {
            $outputContent += "$($decoded.DecodedText)`n"
        }

        $outputContent += "`n═══════════════════════════════════════════════════════════`n`n"
    }

    $outputContent | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Host "💾 Output saved to: " -NoNewline
    Write-Host $OutputFile -ForegroundColor Green
}

Write-Host "✅ Analysis complete!" -ForegroundColor Green
