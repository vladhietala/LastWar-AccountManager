param(
    [Parameter(Position = 0)]
    [string]$Conta = "Vlad"
)

$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath "Start-LastWar.ps1"
$logPath = Join-Path -Path $env:TEMP -ChildPath "lastwar_error.log"

try {
    # Ensure we're using the correct working directory
    Set-Location -Path $PSScriptRoot

    # Run the main script and capture all output
    $output = & $scriptPath -Conta $Conta -Verbose *>&1

    # Log the output
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] Starting LastWar with account: $Conta" | Out-File -FilePath $logPath
    $output | Out-File -FilePath $logPath -Append
}
catch {
    $errorMessage = $_.Exception.Message
    $errorLine = $_.InvocationInfo.ScriptLineNumber
    $errorScript = $_.InvocationInfo.ScriptName

    # Log the error with details
    @"
[$timestamp] ERROR:
Script: $errorScript
Line: $errorLine
Message: $errorMessage
"@ | Out-File -FilePath $logPath -Append

    # Re-throw the error
    throw
}
