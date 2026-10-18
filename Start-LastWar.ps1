#Requires -PSEdition core

<#
.SYNOPSIS
    Script to manage The Last War settings for multiple accounts.

.DESCRIPTION
    This script manages The Last War registry settings, allowing you to
    switch between different accounts, back up settings, and restore them
    automatically.

.PARAMETER Account
    Name of the account to load. Available accounts are dynamically discovered
    from the Accounts/ folder. Use tab completion to see available options.
    Also accepts -Conta as an alias for backwards compatibility.

.NOTES
    Folder structure:
    - Accounts/ : Account .reg files
    - Backups/  : Automatic account backups

.PARAMETER MaxBackups
    Maximum number of backups to keep per account. Default: 20

.EXAMPLE
    .\Start-LastWar.ps1 -Account Vlad
    Starts the game with Vlad account settings

.EXAMPLE
    .\Start-LastWar.ps1 -Conta Vlad
    Same as above, using the Portuguese alias for backwards compatibility

.NOTES
    Author: Vlad
    Last Updated: 2025-10-26
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Name of the account to load")]
    [Alias('Conta')]  # Portuguese alias for backwards compatibility
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        # Dynamically discover accounts from Accounts folder
        $accountsPath = Join-Path -Path $PSScriptRoot -ChildPath "Accounts"
        if (Test-Path $accountsPath) {
            Get-ChildItem -Path $accountsPath -Filter "*.reg" -File |
                Where-Object { $_.Name -ne "Initial.reg" } |
                ForEach-Object {
                    $accountName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                    if ($accountName -like "$wordToComplete*") {
                        [System.Management.Automation.CompletionResult]::new(
                            $accountName,
                            $accountName,
                            'ParameterValue',
                            "Account: $accountName"
                        )
                    }
                }
        }
    })]
    [string]$Account,

    [Parameter(Mandatory = $false, HelpMessage = "Maximum number of backups to keep per account")]
    [ValidateRange(1, 100)]
    [int]$MaxBackups = 20,

    [Parameter(Mandatory = $false, HelpMessage = "Create a new account if it doesn't exist")]
    [switch]$CreateNew
)

# Full path of the main script (must be defined BEFORE dot-sourcing for privilege elevation)
$script:MAIN_SCRIPT_PATH = $PSCommandPath

# Import functions
. "$PSScriptRoot\Start-LastWar.Functions.ps1"

# Function used in parameter validation (not in Functions.ps1 because it depends on $PSScriptRoot)
function Get-AvailableAccounts {
    # List all .reg files from Accounts folder
    $accountsPath = Join-Path -Path $PSScriptRoot -ChildPath "Accounts"
    Get-ChildItem -Path $accountsPath -Filter "*.reg" |
    ForEach-Object { $_.BaseName } |
    Sort-Object
}

# Account validation (dynamic, executed after parameter parsing)
$availableAccounts = Get-AvailableAccounts
$matched = $availableAccounts | Where-Object { $_.Equals($Account, 'InvariantCultureIgnoreCase') } | Select-Object -First 1

if ($CreateNew) {
    # Creation mode: account must NOT exist
    if ($matched) {
        throw "Account '{0}' already exists. Use without -CreateNew to load it, or choose another name." -f $Account
    }
    # Keep the user-provided name (no matched name to normalize)
    Write-Host ("Creation mode: New account '{0}' will be created" -f $Account) -ForegroundColor Cyan
}
else {
    # Normal mode: account MUST exist
    if (-not $matched) {
        throw "Account '{0}' not found. Available accounts: {1}`nTo create a new account, use: -CreateNew" -f $Account, ($availableAccounts -join ', ')
    }
    # Normalize casing to match filename
    $Account = $matched
}

# Constants (overrides default values from Functions.ps1 with production values)
$script:REGISTRY_PATH = "HKEY_CURRENT_USER\Software\FunFly\Last War-Survival Game"
$script:GAME_ROOT = Join-Path -Path $env:LOCALAPPDATA -ChildPath "FunFly\Last War-Survival Game"
$script:LAUNCHER_PATH = Join-Path -Path $script:GAME_ROOT -ChildPath "LastWarLauncher.exe"

# Determine script directory even when executed with -NoProfile
$script:REGEDIT_ROOT = if ($PSScriptRoot) {
    $PSScriptRoot # Use $PSScriptRoot if available
} else {
    Split-Path -Parent -Path $MyInvocation.MyCommand.Definition # Fallback
}
$script:LOCK_FILE = Join-Path -Path $script:REGEDIT_ROOT -ChildPath ".lastwar.lock"

# Timing Constants
$script:GAME_PROCESS_TIMEOUT_SECONDS = 90
$script:REGISTRY_WRITE_GRACE_PERIOD_SECONDS = 1
$script:ERROR_MESSAGE_DISPLAY_SECONDS = 10
$script:POST_IMPORT_DELAY_SECONDS = 1
$script:VERBOSE_STATUS_INTERVAL_SECONDS = 10


try {
    Write-Verbose "Script running from: $($script:REGEDIT_ROOT)"

    # Validate game installation
    Test-GameInstallation

    # Remove orphaned locks and check for other running instances
    Remove-OrphanedLock
    Assert-NoExistingLock

    # Create lock for this instance
    New-ScriptLock -AccountName $Account

    try {
        Invoke-AccountSwitch -Account $Account -MaxBackups $MaxBackups -IsNewAccount $CreateNew
    }
    catch {
        # Catch error inside inner try, but still remove lock in finally
        throw
    }
    finally {
        # Ensure lock is removed even on error
        Remove-ScriptLock
    }
}
catch {
    # Error already handled (lock was removed in finally above)
    Show-ErrorMessage -ErrorRecord $_ -WaitForKeyPress
    exit 1
}
