# Module containing only the functions from Start-LastWar.ps1
# This file is used by Pester tests to import functions without executing the full script

# Constants (default values for testing)
if (-not $script:REGEDIT_ROOT) {
    $script:REGEDIT_ROOT = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
}
if (-not $script:LOCK_FILE) {
    $script:LOCK_FILE = Join-Path -Path $script:REGEDIT_ROOT -ChildPath ".lastwar.lock"
}
if (-not $script:REGISTRY_PATH) {
    $script:REGISTRY_PATH = "HKEY_CURRENT_USER\Software\FunFly\Last War-Survival Game"
}
if (-not $script:GAME_ROOT) {
    $script:GAME_ROOT = Join-Path -Path $env:LOCALAPPDATA -ChildPath "FunFly\Last War-Survival Game"
}
if (-not $script:LAUNCHER_PATH) {
    $script:LAUNCHER_PATH = Join-Path -Path $script:GAME_ROOT -ChildPath "LastWarLauncher.exe"
}

# Timing Constants
if (-not $script:GAME_PROCESS_TIMEOUT_SECONDS) {
    $script:GAME_PROCESS_TIMEOUT_SECONDS = 90
}
if (-not $script:REGISTRY_WRITE_GRACE_PERIOD_SECONDS) {
    $script:REGISTRY_WRITE_GRACE_PERIOD_SECONDS = 1
}
if (-not $script:ERROR_MESSAGE_DISPLAY_SECONDS) {
    $script:ERROR_MESSAGE_DISPLAY_SECONDS = 10
}
if (-not $script:POST_IMPORT_DELAY_SECONDS) {
    $script:POST_IMPORT_DELAY_SECONDS = 1
}
if (-not $script:VERBOSE_STATUS_INTERVAL_SECONDS) {
    $script:VERBOSE_STATUS_INTERVAL_SECONDS = 10
}

function Test-GameInstallation {
    [CmdletBinding()]
    param()

    <#
    .SYNOPSIS
        Validates that the game is installed and accessible

    .DESCRIPTION
        Checks if the game directory and launcher exist before attempting to run

    .THROWS
        Throws exception if the game is not installed correctly
    #>

    if (-not (Test-Path $script:GAME_ROOT)) {
        throw "Game directory not found: $script:GAME_ROOT`nPlease verify the game is installed."
    }

    if (-not (Test-Path $script:LAUNCHER_PATH)) {
        throw "Game launcher not found: $script:LAUNCHER_PATH`nPlease verify the game installation."
    }

    Write-Verbose "Game installation validated: $script:GAME_ROOT"
}

function Test-ScriptLock {
    <#
    .SYNOPSIS
        Checks if another instance of the script is running

    .DESCRIPTION
        Checks for the existence of a lock file and validates if the associated process is still active.
        This function only reads the lock state without modifying it.

    .OUTPUTS
        Returns an object with lock information including:
        - IsLocked: Whether there is an active process
        - IsOrphaned: Whether the lock exists but the process does not
        - IsCorrupted: Whether the file is corrupted
        - AccountName, ProcessId, LockTime: Lock data (when available)
    #>
    if (-not (Test-Path $script:LOCK_FILE)) {
        return $null
    }

    try {
        $lockContent = Get-Content $script:LOCK_FILE -Raw | ConvertFrom-Json

        # Check if the process is still active
        $process = Get-Process -Id $lockContent.ProcessId -ErrorAction SilentlyContinue

        return [PSCustomObject]@{
            IsLocked = ($null -ne $process)
            IsOrphaned = ($null -eq $process)
            IsCorrupted = $false
            AccountName = $lockContent.AccountName
            ProcessId = $lockContent.ProcessId
            LockTime = $lockContent.LockTime
        }
    }
    catch {
        # Lock file corrupted or unreadable
        return [PSCustomObject]@{
            IsLocked = $false
            IsOrphaned = $false
            IsCorrupted = $true
            AccountName = $null
            ProcessId = $null
            LockTime = $null
        }
    }
}

function Remove-OrphanedLock {
    [CmdletBinding()]
    param()

    <#
    .SYNOPSIS
        Removes orphaned lock file if the associated process no longer exists

    .DESCRIPTION
        Checks the lock state and removes it if it is orphaned or corrupted
    #>
    $lockState = Test-ScriptLock

    if ($lockState -and ($lockState.IsOrphaned -or $lockState.IsCorrupted)) {
        try {
            Remove-Item $script:LOCK_FILE -Force -ErrorAction SilentlyContinue
            if ($lockState.IsOrphaned) {
                Write-Verbose "Orphaned lock removed (PID: $($lockState.ProcessId))"
            } elseif ($lockState.IsCorrupted) {
                Write-Verbose "Corrupted lock removed"
            }
        }
        catch {
            Write-Warning "Could not remove orphaned lock: $_"
        }
    }
}

function Assert-NoExistingLock {
    <#
    .SYNOPSIS
        Checks if there is an active lock and aborts execution if so

    .DESCRIPTION
        Validates that no other instance of the script is running.
        If there is, displays a detailed error message and exits the process.
    #>
    $existingLock = Test-ScriptLock

    if (-not ($existingLock -and $existingLock.IsLocked)) {
        return  # No active lock, can continue
    }

    # ConvertFrom-Json already deserializes ISO 8601 to DateTime
    $lockTime = if ($existingLock.LockTime -is [DateTime]) {
        $existingLock.LockTime
    } else {
        [DateTime]::ParseExact($existingLock.LockTime, "o", [System.Globalization.CultureInfo]::InvariantCulture)
    }

    $duration = (Get-Date) - $lockTime

    Write-Host ""
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "ERROR: Another instance of the script is already running!" -ForegroundColor Red
    Write-Host "================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host ("Account running: {0}" -f $existingLock.AccountName) -ForegroundColor Yellow
    Write-Host ("Process ID: {0}" -f $existingLock.ProcessId) -ForegroundColor Yellow
    Write-Host ("Started at: {0}" -f $lockTime.ToString('MM/dd/yyyy HH:mm:ss')) -ForegroundColor Yellow
    Write-Host ("Elapsed time: {0} minutes and {1} seconds" -f [Math]::Floor($duration.TotalMinutes), $duration.Seconds) -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please wait for the other instance to finish before starting a new one." -ForegroundColor Cyan
    Write-Host "This prevents Export-GameRegistry from one account from overwriting" -ForegroundColor Cyan
    Write-Host "another account's .reg file incorrectly." -ForegroundColor Cyan
    Write-Host ""
    Start-Sleep -Seconds $script:ERROR_MESSAGE_DISPLAY_SECONDS
    exit 1
}

function New-ScriptLock {
    [CmdletBinding()]
    param (
        [string]$AccountName
    )

    <#
    .SYNOPSIS
        Creates a lock file to prevent simultaneous executions

    .PARAMETER AccountName
        Name of the account being executed
    #>

    $lockData = @{
        AccountName = $AccountName
        ProcessId = $PID
        LockTime = (Get-Date).ToString("o")
    } | ConvertTo-Json

    try {
        $lockData | Set-Content -Path $script:LOCK_FILE -Force
        Write-Verbose "Lock created: $script:LOCK_FILE (PID: $PID, Account: $AccountName)"
    }
    catch {
        throw "Error creating lock file: $_"
    }
}

function Remove-ScriptLock {
    [CmdletBinding()]
    param()

    <#
    .SYNOPSIS
        Removes the script's lock file
    #>
    try {
        if (Test-Path $script:LOCK_FILE) {
            Remove-Item $script:LOCK_FILE -Force
            Write-Verbose "Lock removed: $script:LOCK_FILE"
        }
    }
    catch {
        Write-Warning "Error removing lock: $_"
    }
}

function Test-Administrator {
    <#
    .SYNOPSIS
        Checks if the script is being executed with administrator privileges
    #>
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ScriptFullPath {
    <#
    .SYNOPSIS
        Gets the full path of the main script with fallbacks

    .DESCRIPTION
        Tries multiple strategies to obtain the path of the main script (Start-LastWar.ps1),
        ensuring compatibility in different execution contexts.

        IMPORTANT: Uses $script:MAIN_SCRIPT_PATH when available, which is defined in
        Start-LastWar.ps1 before dot-sourcing Functions.ps1. This ensures that it
        always returns the path of the main script, not Functions.ps1.
    #>
    # Use MAIN_SCRIPT_PATH if it was defined by the main script
    if ($script:MAIN_SCRIPT_PATH) {
        return $script:MAIN_SCRIPT_PATH
    }
    # Fallback to PSCommandPath (test context or direct execution)
    elseif ($PSCommandPath) {
        return $PSCommandPath
    }
    # Fallback to MyInvocation (older contexts)
    elseif ($MyInvocation.MyCommand.Path) {
        return $MyInvocation.MyCommand.Path
    }
    # Last fallback: construct path based on directory
    else {
        return Join-Path -Path $script:REGEDIT_ROOT -ChildPath "Start-LastWar.ps1"
    }
}

function Build-ElevatedProcessArguments {
    <#
    .SYNOPSIS
        Builds the argument list for the elevated process

    .PARAMETER ScriptPath
        Full path of the script to be executed

    .PARAMETER Account
        Account name

    .PARAMETER MaxBackups
        Maximum number of backups

    .PARAMETER BoundParameters
        Bound parameters from the original cmdlet
    #>
    param(
        [string]$ScriptPath,
        [string]$Account,
        [int]$MaxBackups,
        [hashtable]$BoundParameters
    )

    $argList = @("-NoProfile")

    # Add -NoExit if Verbose is active (to keep window open and see messages)
    if ($BoundParameters['Verbose']) {
        $argList += "-NoExit"
    }

    $argList += @(
        "-ExecutionPolicy", "Bypass"
        "-File", '"{0}"' -f $ScriptPath
        "-Account", '"{0}"' -f $Account
        "-MaxBackups", $MaxBackups
    )

    if ($BoundParameters['CreateNew']) {
        $argList += "-CreateNew"
    }

    if ($BoundParameters['Verbose']) {
        $argList += "-Verbose"
    }

    return $argList
}

function Show-ElevationPrompt {
    <#
    .SYNOPSIS
        Displays informative message about privilege elevation
    #>
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "  Privilege Elevation Required" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "The game requires administrator permissions." -ForegroundColor Cyan
    Write-Host "Requesting elevation..." -ForegroundColor Cyan
    Write-Host ""
}

function Request-Elevation {
    [CmdletBinding()]
    param (
        [string]$Account,
        [int]$MaxBackups,
        [hashtable]$BoundParameters
    )

    <#
    .SYNOPSIS
        Requests privilege elevation and relaunches the script as administrator

    .PARAMETER Account
        Name of the account being loaded

    .PARAMETER MaxBackups
        Maximum number of backups

    .PARAMETER BoundParameters
        Bound parameters from the original cmdlet
    #>

    Show-ElevationPrompt

    try {
        $scriptFullPath = Get-ScriptFullPath
        Write-Verbose "Script path for elevation: $scriptFullPath"

        $argList = Build-ElevatedProcessArguments `
            -ScriptPath $scriptFullPath `
            -Account $Account `
            -MaxBackups $MaxBackups `
            -BoundParameters $BoundParameters

        Write-Verbose "Arguments for elevated process: $($argList -join ' ')"

        $process = Start-Process -FilePath "pwsh.exe" -ArgumentList $argList -Verb RunAs -PassThru
        Write-Verbose "Elevated process started with PID: $($process.Id)"

        exit 0
    }
    catch {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "  ERROR" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "Failed to elevate privileges: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "The script needs to be run as administrator." -ForegroundColor Yellow
        Write-Host ""
        Start-Sleep -Seconds 5
        exit 1
    }
}

function Initialize-NewAccount {
    [CmdletBinding()]
    param (
        [string]$Account
    )

    <#
    .SYNOPSIS
        Initializes a new account that does not yet exist

    .DESCRIPTION
        Checks if there is an Initial.reg file to use as a template.
        If it exists, copies it to the new account.
        If it does not exist, returns $null (indicating that import should be skipped).

    .PARAMETER Account
        Name of the new account to be created

    .OUTPUTS
        Path of the created .reg file, or $null if import should be skipped
    #>

    $accountsPath = Join-Path -Path $script:REGEDIT_ROOT -ChildPath "Accounts"
    $accountFile = Join-Path -Path $accountsPath -ChildPath ("{0}.reg" -f $Account)

    # Check if account already exists (additional safety)
    if (Test-Path $accountFile) {
        throw "Account '{0}' already exists at: {1}" -f $Account, $accountFile
    }

    # Check if Initial.reg exists as template
    $initialFile = Join-Path -Path $accountsPath -ChildPath "Initial.reg"

    if (Test-Path $initialFile) {
        Write-Host ("Using Initial.reg as base for new account '{0}'" -f $Account) -ForegroundColor Cyan
        Copy-Item $initialFile $accountFile -Force
        Write-Verbose ("Template copied: {0} -> {1}" -f $initialFile, $accountFile)
        return $accountFile
    }
    else {
        Write-Warning "Initial.reg not found. Account will be created from scratch."
        Write-Host ("Configure the new account '{0}' inside the game. When you exit, the settings will be saved to '{1}'" -f $Account, $accountFile) -ForegroundColor Yellow
        return $null  # Signals to skip import
    }
}

function Initialize-Workspace {
    <#
    .SYNOPSIS
        Initializes the workspace and validates existing account file

    .PARAMETER Account
        Name of the account to be loaded

    .PARAMETER IsNewAccount
        If $true, treats as new account creation

    .OUTPUTS
        Path of the .reg file, or $null if import should be skipped (only for new accounts)
    #>
    param (
        [string]$Account,
        [bool]$IsNewAccount = $false
    )

    if ($IsNewAccount) {
        return Initialize-NewAccount -Account $Account
    }

    $regFilePath = Join-Path -Path $script:REGEDIT_ROOT -ChildPath "Accounts" -AdditionalChildPath ("{0}.reg" -f $Account)
    if (-not (Test-Path $regFilePath)) {
        throw "Registry file not found: {0}" -f $regFilePath
    }

    return $regFilePath
}

function Test-BackupNeeded {
    <#
    .SYNOPSIS
        Checks if a new backup is needed by comparing with the most recent one

    .PARAMETER SourceFile
        Source file to be checked

    .PARAMETER BackupFolder
        Folder where backups are stored

    .PARAMETER Account
        Account name to filter backups

    .OUTPUTS
        $true if backup is needed, $false if file is identical to the last backup
    #>
    param(
        [string]$SourceFile,
        [string]$BackupFolder,
        [string]$Account
    )

    $latestBackup = Get-ChildItem -Path $BackupFolder -Filter "Backup_${Account}_*.reg" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latestBackup) {
        return $true
    }

    try {
        $hashSource = Get-FileHash -Path $SourceFile -Algorithm SHA256
        $hashLatest = Get-FileHash -Path $latestBackup.FullName -Algorithm SHA256

        if ($hashSource.Hash -eq $hashLatest.Hash) {
            Write-Host ("Current file is identical to the most recent backup ({0}). Skipping backup creation." -f $latestBackup.Name)
            return $false
        }

        return $true
    }
    catch {
        Write-Warning "Could not compare file hashes: $_"
        return $true  # In case of error, create the backup for safety
    }
}

function Remove-OldBackups {
    [CmdletBinding()]
    param(
        [string]$BackupFolder,
        [string]$Account,
        [int]$MaxBackups
    )

    <#
    .SYNOPSIS
        Removes old backups keeping only the N most recent

    .PARAMETER BackupFolder
        Folder where backups are stored

    .PARAMETER Account
        Account name to filter backups

    .PARAMETER MaxBackups
        Maximum number of backups to keep
    #>

    $oldBackups = Get-ChildItem -Path $BackupFolder -Filter "Backup_${Account}_*.reg" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $MaxBackups

    if ($oldBackups) {
        $oldBackups | Remove-Item -Force
        Write-Verbose ("Removed {0} old backups" -f $oldBackups.Count)
    }
}

function New-RegistryBackup {
    <#
    .SYNOPSIS
        Creates backup of the account's registry file

    .PARAMETER Path
        Base path where to create the backups folder

    .PARAMETER Account
        Account name

    .PARAMETER SourceFile
        Source file to be copied

    .PARAMETER MaxBackups
        Maximum number of backups to keep
    #>
    param (
        [string]$Path,
        [string]$Account,
        [string]$SourceFile,
        [int]$MaxBackups
    )

    # Create backup folder
    $backupFolder = Join-Path -Path $Path -ChildPath "Backups" -AdditionalChildPath $Account
    if (-not (Test-Path $backupFolder)) {
        New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
    }

    # Check if backup is needed
    if (-not (Test-BackupNeeded -SourceFile $SourceFile -BackupFolder $backupFolder -Account $Account)) {
        return
    }

    # Create backup with timestamp
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path -Path $backupFolder -ChildPath "Backup_${Account}_${timestamp}.reg"

    try {
        Write-Host "Backing up current file to: $backupPath"
        Copy-Item -Path $SourceFile -Destination $backupPath -Force
        Write-Host "Backup completed successfully"

        # Remove old backups
        Remove-OldBackups -BackupFolder $backupFolder -Account $Account -MaxBackups $MaxBackups
    }
    catch {
        Write-Warning "Could not create backup: $_"
    }
}

function Invoke-RegistryCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('import', 'export', 'delete')]
        [string]$Operation,

        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$SuccessMessage,

        [Parameter(Mandatory)]
        [string]$ErrorContext,

        [switch]$ContinueOnError
    )

    <#
    .SYNOPSIS
        Executes reg.exe commands with standardized error handling

    .PARAMETER Operation
        The operation to execute (import, export, delete)

    .PARAMETER Arguments
        Array of arguments to pass to reg.exe

    .PARAMETER SuccessMessage
        Message to display on success

    .PARAMETER ErrorContext
        Error context for clearer messages

    .PARAMETER ContinueOnError
        If specified, does not throw exception on error (only displays warning)

    .OUTPUTS
        Returns $true if success, $false if fails with ContinueOnError, throws exception otherwise
    #>

    try {
        # Log the command being executed
        $commandLine = "reg {0} {1}" -f $Operation, ($Arguments -join ' ')
        Write-Verbose ("Executing: {0}" -f $commandLine)

        $result = & reg $Operation @Arguments 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host $SuccessMessage
            return $true
        }
        else {
            $errorMessage = ("reg {0} returned error (code {1}): {2}" -f $Operation, $LASTEXITCODE, $result)

            if ($ContinueOnError) {
                Write-Verbose ("{0}: {1}" -f $ErrorContext, $errorMessage)
                return $false
            }
            else {
                throw $errorMessage
            }
        }
    }
    catch {
        $fullError = ("{0}: {1}" -f $ErrorContext, $_)

        if ($ContinueOnError) {
            Write-Verbose $fullError
            return $false
        }
        else {
            throw $fullError
        }
    }
}

function Import-GameRegistry {
    param (
        [string]$RegFilePath
    )

    Write-Host "Cleaning previous registry..."

    # Delete the registry key to ensure clean slate (avoids value accumulation)
    Invoke-RegistryCommand `
        -Operation 'delete' `
        -Arguments @($script:REGISTRY_PATH, '/f') `
        -SuccessMessage "Registry cleaned successfully" `
        -ErrorContext "Warning: Could not clean registry (may not exist)" `
        -ContinueOnError

    Write-Host "Importing registry settings..."

    Invoke-RegistryCommand `
        -Operation 'import' `
        -Arguments @($RegFilePath) `
        -SuccessMessage "Settings imported successfully" `
        -ErrorContext "Error importing settings"
}

function Export-GameRegistry {
    param (
        [string]$RegFilePath
    )

    Write-Host "Updating registry file with new settings..."

    Invoke-RegistryCommand `
        -Operation 'export' `
        -Arguments @($script:REGISTRY_PATH, $RegFilePath, '/y') `
        -SuccessMessage "Settings saved successfully" `
        -ErrorContext "Error saving settings"
}

function Find-GameProcess {
    [CmdletBinding()]
    param()

    # Wait until game process is found
    $maxAttempts = $script:GAME_PROCESS_TIMEOUT_SECONDS
    $attempt = 0
    $gameProcess = $null

    Write-Verbose "Looking for game process (timeout: $maxAttempts seconds)..."

    while ($attempt -lt $maxAttempts) {
        # Look for LastWar.exe (excluding LastWarLauncher.exe)
        $gameProcess = Get-Process -Name "LastWar" -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($gameProcess) {
            Write-Host ("Game process found: {0}" -f $gameProcess.Path)
            return $gameProcess
        }

        # Show progress periodically
        if (($attempt % $script:VERBOSE_STATUS_INTERVAL_SECONDS) -eq 0 -and $attempt -gt 0) {
            Write-Verbose "Still waiting for game process... ($attempt/$maxAttempts seconds)"
        }

        Start-Sleep -Seconds 1
        $attempt++
    }

    throw "Could not find the game process after $maxAttempts seconds"
}

function Start-GameProcess {
    [CmdletBinding()]
    param()

    Write-Host "Starting The Last War..."
    try {
        # Start the launcher
        Start-Process -FilePath $script:LAUNCHER_PATH -PassThru | Out-Null
        Write-Host "Launcher started, looking for game process..."

        # Find the actual game process
        $gameProcess = Find-GameProcess

        Write-Host "Waiting for game to close..."
        $gameProcess.WaitForExit()

        # Wait a bit to ensure registry write operations are finished
        Start-Sleep -Seconds $script:REGISTRY_WRITE_GRACE_PERIOD_SECONDS
    }
    catch {
        throw "Error starting/monitoring game: $_"
    }
}

function Invoke-AccountSwitch {
    <#
    .SYNOPSIS
        Orchestrates the complete account switching flow

    .DESCRIPTION
        Executes the complete flow to switch accounts:
        1. Initializes workspace and validates account file
        2. Creates backup of current account state (if applicable)
        3. Imports account registry settings (if available)
        4. Starts the game and waits for termination
        5. Exports updated registry settings

    .PARAMETER Account
        Name of the account to be loaded

    .PARAMETER MaxBackups
        Maximum number of backups to keep per account

    .PARAMETER IsNewAccount
        If $true, treats as new account creation
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Account,

        [Parameter(Mandatory)]
        [int]$MaxBackups,

        [bool]$IsNewAccount = $false
    )

    # Initialize and check environment
    $regFilePath = Initialize-Workspace -Account $Account -IsNewAccount $IsNewAccount

    if ($regFilePath) {
        Write-Host ("Loading account {0} from: {1}" -f $Account, $regFilePath)

        # Create backup of current settings
        New-RegistryBackup -Path $script:REGEDIT_ROOT -Account $Account -SourceFile $regFilePath -MaxBackups $MaxBackups

        # Import account settings
        Import-GameRegistry -RegFilePath $regFilePath

        Start-Sleep -Seconds $script:POST_IMPORT_DELAY_SECONDS
    }
    else {
        Write-Host ("Creating new account '{0}' without template. Game will start with current settings." -f $Account) -ForegroundColor Yellow
        # Define path where it will be saved when exporting
        $regFilePath = Join-Path -Path $script:REGEDIT_ROOT -ChildPath "Accounts" -AdditionalChildPath ("{0}.reg" -f $Account)
    }

    # Start game and wait for it to finish
    Start-GameProcess

    # Export new settings
    Export-GameRegistry -RegFilePath $regFilePath

    Write-Host "Process completed!"
    Start-Sleep -Seconds $script:REGISTRY_WRITE_GRACE_PERIOD_SECONDS
}

function Show-ErrorMessage {
    <#
    .SYNOPSIS
        Displays error message in a consistent formatted way

    .PARAMETER ErrorRecord
        The error record to be displayed

    .PARAMETER Title
        Title of the error message (default: "CRITICAL ERROR")

    .PARAMETER WaitForKeyPress
        Whether to wait for the user to press a key before continuing
    #>
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [string]$Title = "CRITICAL ERROR",

        [switch]$WaitForKeyPress
    )

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  $Title" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $ErrorRecord.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Technical details:" -ForegroundColor Yellow
    Write-Host $ErrorRecord.ScriptStackTrace -ForegroundColor Gray
    Write-Host ""

    if ($WaitForKeyPress) {
        Write-Host "Press any key to close..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
}
