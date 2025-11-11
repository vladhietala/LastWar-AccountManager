# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Windows Registry management system for "The Last War: Survival Game" that enables switching between multiple game accounts by manipulating Windows Registry entries. The game stores account data in `HKEY_CURRENT_USER\Software\FirstFun\Last War-Survival Game`.

## Core Architecture

### Main Scripts

1. **Start-LastWar.ps1** - Primary orchestration script
   - Manages the complete account switching workflow
   - Handles registry import/export operations
   - Controls game launch and monitoring
   - Implements automatic backup system with deduplication
   - Account names are case-insensitive and dynamically discovered from Accounts/ folder
   - **Lock mechanism**: Prevents concurrent executions to avoid registry corruption
   - **Auto-elevation**: Automatically requests administrator privileges when needed

2. **Create-Shortcuts.ps1** - Shortcut management utility
   - Automatically discovers all accounts from Accounts/ folder
   - Creates/updates Windows Start Menu shortcuts for quick access
   - Removes orphaned shortcuts (accounts that no longer exist)
   - Uses dynamic paths (updates automatically when repository is moved)
   - Shortcuts are created in: `Start Menu\Programs\FirstFun\`

### Utility Scripts (Tools/)

1. **Tools/ConvertFrom-RegHex.ps1** - Registry hex decoder and analyzer
   - Decodes Windows Registry .reg files to human-readable formats
   - Supports all registry types (REG_SZ, REG_DWORD, REG_QWORD, REG_BINARY, etc.)
   - Auto-detects encoding (UTF-16 LE, UTF-8, JSON, DWORD/QWORD)
   - Three output formats: Text (default), Detailed (with hex dumps), JSON
   - `-ShowKeyNames` removes Unity PlayerPrefs `_h` hash suffixes
   - Includes `SimpleName` field in JSON output for cleaner key names
   - Can combine `-Format Json` with `-OutputFile` for structured exports
   - Useful for debugging account data and understanding game state

2. **Tools/Compare-LastWarKeys.ps1** - Registry diffing utility
   - Generates .reg files containing only differences between two registry keys
   - Outputs deletion entries (`"name"=-`) for removed values
   - Useful for understanding account-specific changes
   - **Note**: Created during initial development when exploring registry key manipulation approach

3. **Tools/Launch-LastWar.ps1** - Logging wrapper script (optional)
   - Provides error logging to `%TEMP%\lastwar_error.log`
   - Ensures correct working directory
   - Delegates to Start-LastWar.ps1
   - **Note**: Not actively used; kept for reference/debugging purposes

### Directory Structure

```text
Accounts/        - Active .reg files for each account (dynamically discovered)
Backups/         - Timestamped backups organized by account name
Tools/           - Utility scripts (Compare-LastWarKeys.ps1, Launch-LastWar.ps1, ConvertFrom-RegHex.ps1)
.vscode/         - Contains PowerShell debug configuration
```

### Account Switching Workflow

The system follows this sequence when switching accounts:

1. **Lock Check**: Verifies no other instance is running (prevents registry corruption)
2. **Lock Creation**: Creates lock file in repository root (`.lastwar.lock`) with account name, PID, and timestamp
3. **Initialization**: Validates account name exists in Accounts/ folder
4. **Backup**: Creates timestamped backup in Backups/{AccountName}/ (only if different from last backup based on SHA256 hash)
5. **Registry Cleanup**: Deletes existing registry key using `reg delete` to prevent value accumulation
6. **Import**: Loads account .reg file into Windows Registry using `reg import`
7. **Launch**: Starts game via `%LOCALAPPDATA%\TheLastWar\Launch.exe`
8. **Monitor**: Waits for game process (searches for LastWar.exe, timeout 90s)
9. **Await Exit**: Blocks until game process terminates
10. **Grace Period**: Waits 1 second for registry write operations to complete
11. **Export**: Saves current registry state back to account .reg file using `reg export`
12. **Lock Release**: Removes lock file (guaranteed via try-finally block)

### Registry File Format

Registry files are Unicode-encoded Windows Registry Editor Version 5.00 format containing:

- Unity analytics/session data (player_sessionid, cloud_userid)
- Game configuration (screen resolution, fullscreen mode)
- Account identifiers (RANDD0M_ID, distinct_id, alliance_id)
- Encrypted check keys (REG_ENC_CHECK_KEY)
- Game state data (hex-encoded JSON for super_properties)

## Common Development Tasks

### Running the main script

```powershell
.\Start-LastWar.ps1 -Conta <AccountName>
.\Start-LastWar.ps1 -Conta <AccountName> -MaxBackups 15  # Customize backup retention
```

### Running with error logging (optional)

```powershell
.\Tools\Launch-LastWar.ps1 -Conta <AccountName>
```

### Analyzing registry files

```powershell
# View decoded registry data in console
.\Tools\ConvertFrom-RegHex.ps1 -RegFilePath ".\Accounts\Vlad.reg"

# Show simplified key names (removes Unity's _hXXXXXXXXXX suffixes)
.\Tools\ConvertFrom-RegHex.ps1 -RegFilePath ".\Accounts\Vlad.reg" -ShowKeyNames

# Export to JSON for programmatic analysis
.\Tools\ConvertFrom-RegHex.ps1 -RegFilePath ".\Accounts\Vlad.reg" -Format Json -OutputFile "vlad-data.json"

# Detailed analysis with hex dumps
.\Tools\ConvertFrom-RegHex.ps1 -RegFilePath ".\Accounts\Vlad.reg" -Format Detailed -OutputFile "analysis.txt"
```

### Comparing two registry keys (utility)

```powershell
.\Tools\Compare-LastWarKeys.ps1 -KeyPath1 "HKCU:\Software\FirstFun\LastWar-Account1" `
                                -KeyPath2 "HKCU:\Software\FirstFun\LastWar-Account2" `
                                -OutRegFile ".\Diff.reg"
```

### Creating/updating Start Menu shortcuts

```powershell
.\Create-Shortcuts.ps1
.\Create-Shortcuts.ps1 -IconPath "C:\Icons\game.ico"  # With custom icon
.\Create-Shortcuts.ps1 -PinToStart                    # Try to pin to Start Menu (may not work on all Windows versions)
```

### Adding a new account

1. Create or export a .reg file with the account's registry data
2. Place it in the Accounts/ folder with a descriptive name (e.g., `NewAccount.reg`)
3. Run `.\Create-Shortcuts.ps1` to create a shortcut for the new account
4. The script will automatically detect it as an available account

### Testing PowerShell scripts

Use VSCode's PowerShell debugging (F5) or run with `-Verbose` flag:

```powershell
.\Start-LastWar.ps1 -Conta Vlad -Verbose
```

## Important Constants

- **Repository Location**: Detected automatically via `$PSScriptRoot`
- **Registry Path**: `HKEY_CURRENT_USER\Software\FirstFun\Last War-Survival Game`
- **Game Launcher**: `%LOCALAPPDATA%\TheLastWar\Launch.exe`
- **Game Root**: `%LOCALAPPDATA%\TheLastWar`
- **Shortcuts Location**: `%APPDATA%\Microsoft\Windows\Start Menu\Programs\FirstFun\`
- **Lock File**: `.lastwar.lock` (in repository root)
- **Default Max Backups**: 10 per account
- **Registry Decoder**: `Tools/ConvertFrom-RegHex.ps1` (supports Text, Detailed, and JSON output formats)
- **Unity PlayerPrefs Hash Suffix Pattern**: `_h[0-9]+` (e.g., `_h2665564582`)
- **GitHub Repository**: Private repository (uses SSH)

## Script Requirements

- PowerShell Core (`#Requires -PSEdition core` in Start-LastWar.ps1)
- Windows Registry access (uses `reg.exe` commands)
- Write permissions to script directory for backups
- **Administrator privileges**: The script automatically elevates itself when needed (auto-elevation)

## PowerShell Coding Conventions

When working with PowerShell code in this repository, follow these guidelines:

### String Formatting

- **Prefer `-f` format operator for complex string construction** instead of string interpolation
- Use `-f` when combining multiple variables or expressions to improve readability
- Simple interpolation with `"$variable"` is acceptable for single variables

**Good examples (complex):**

```powershell
$errorMessage = "reg {0} retornou erro (código {1}): {2}" -f $Operation, $LASTEXITCODE, $result
Write-Host ("Processo encontrado: {0} (PID: {1})" -f $process.Name, $process.Id)
```

**Acceptable (simple):**

```powershell
Write-Host "Usando conta: $Conta"
```

### Path Construction

- **Always use `Join-Path`** instead of string concatenation for file paths
- Ensures correct path separators across different scenarios
- Use `-AdditionalChildPath` for joining multiple path segments

**Good examples:**

```powershell
$accountsPath = Join-Path -Path $repoRoot -ChildPath "Accounts"
$backupPath = Join-Path -Path $backupFolder -ChildPath "Backup_${Conta}_${timestamp}.reg"
$deepPath = Join-Path -Path $base -ChildPath "Level1" -AdditionalChildPath "Level2", "file.txt"
```

**Avoid:**

```powershell
$accountsPath = "$repoRoot\Accounts"  # Bad: hardcoded separator
$accountsPath = "$repoRoot/Accounts"  # Bad: wrong separator for Windows
```

### Other Conventions

- Use `Write-Verbose` for detailed logging (visible with `-Verbose` flag)
- Use `Write-Host` for user-facing status messages
- Use `throw` for fatal errors that should stop execution
- Always include descriptive comments for complex operations

## Error Handling

All scripts use proper error handling with try-catch blocks. The main script will:

- Validate account existence before proceeding
- Check for required files and paths
- Throw descriptive errors with context
- Display error messages in a user-friendly format with pause before closing
- Guarantee lock cleanup even on errors (via try-finally blocks)

## Backup System Details

- Backups are stored in `Backups/{AccountName}/Backup_{AccountName}_{timestamp}.reg`
- SHA256 hash comparison prevents duplicate backups
- Automatic cleanup maintains only the N most recent backups (configurable via `-MaxBackups`)
- Timestamp format: `yyyyMMdd_HHmmss`

## Process Monitoring

The game launch process uses a polling mechanism:

- Searches for processes matching `*LastWar*` pattern
- 90-second timeout with 1-second intervals (increased to accommodate UAC prompts)
- Progress messages every 10 seconds when using `-Verbose`
- Waits for game process to exit before exporting registry changes
- 1-second grace period after exit for write operations to complete

## Administrator Privileges (Auto-Elevation)

The game requires administrator privileges to run. The script handles this automatically:

### Auto-Elevation Mechanism

- Detects if running without admin privileges using `Test-Administrator` function
- Automatically re-launches itself elevated using `Start-Process -Verb RunAs`
- Preserves all command-line parameters (`-Conta`, `-MaxBackups`, `-Verbose`)
- Displays clear messages during elevation process
- Uses `$PSCommandPath` with fallbacks for reliable script path resolution

### Auto-Elevation Benefits

- **No manual UAC prompts during gameplay**: UAC prompt appears once at script start
- **Seamless experience**: Users don't need to manually run as admin
- **Works with shortcuts**: Start Menu shortcuts work normally without special configuration
- **Single window**: Elevated process runs independently, original process exits cleanly
- **Fail-safe**: If elevation fails, shows clear error message

### Auto-Elevation Behavior

- If already running as admin: continues normally (no re-launch)
- If not admin: shows yellow banner, requests elevation, original process exits
- If user cancels UAC: elevated process never starts, clean exit
- Pre-elevation window is visible for debugging purposes

## Concurrency Control (Lock System)

To prevent registry corruption from simultaneous executions:

### Lock Mechanism

- Lock file: `.lastwar.lock` in repository root (JSON format, ignored by Git)
- Contains: account name, process ID, and timestamp
- Validated on startup - checks if process is still active
- Auto-cleanup of orphaned locks (when process no longer exists)
- Repository-specific: Each clone/location has its own lock

### Lock Behavior

- **If lock exists**: Script displays error with details (account name, PID, duration) and exits after 10 seconds
- **Lock creation**: Immediately after validation, before any registry operations
- **Lock release**: Guaranteed via try-finally block, even on errors

### Lock System Benefits

- Prevents Export-GameRegistry from one account overwriting another account's .reg file
- Allows safe sequential account switching without corruption
- Self-healing: automatically removes stale locks from crashed processes

## Shortcut Management

The repository includes a script for managing Start Menu shortcuts:

### Create-Shortcuts.ps1

- **Auto-discovery**: Scans Accounts/ folder for all .reg files (excludes templates like Initial.reg)
- **Creates shortcuts**: In `Start Menu\Programs\FirstFun\` for each account
- **Orphan cleanup**: Automatically removes shortcuts for deleted accounts
- **Dynamic paths**: Uses current repository location automatically
- **Custom icons**: Optional `-IconPath` parameter for personalization
- **Pin to Start**: Optional `-PinToStart` switch to attempt automatic pinning (Windows API limitations may prevent this)

### Workflow

1. Add/remove account .reg files in Accounts/
2. Run `.\Create-Shortcuts.ps1`
3. All shortcuts update automatically with correct paths

### Shortcut Benefits

- No manual shortcut editing needed
- Repository-independent (works after moving repo)
- Versionable in Git (script, not binary .lnk files)
- Quick access via Windows Search (Win + type account name)
