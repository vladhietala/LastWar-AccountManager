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

    # Log start
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] Starting LastWar with account: $Conta" | Out-File -FilePath $logPath

    # Run the main script
    # Output is shown on screen AND captured via transcript
    Start-Transcript -Path $logPath -Append
    & $scriptPath -Conta $Conta -Verbose
    Stop-Transcript
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
