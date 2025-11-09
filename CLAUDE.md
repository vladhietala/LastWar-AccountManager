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

2. **Launch-LastWar.ps1** - Wrapper script
   - Provides error logging to `%TEMP%\lastwar_error.log`
   - Ensures correct working directory
   - Delegates to Start-LastWar.ps1

3. **Compare-LastWarKeys.ps1** - Utility for registry diffing
   - Generates .reg files containing only differences between two registry keys
   - Outputs deletion entries (`"name"=-`) for removed values
   - Useful for understanding account-specific changes

4. **Create-Shortcuts.ps1** - Shortcut management utility
   - Automatically discovers all accounts from Accounts/ folder
   - Creates/updates Windows Start Menu shortcuts for quick access
   - Removes orphaned shortcuts (accounts that no longer exist)
   - Uses dynamic paths (updates automatically when repository is moved)
   - Shortcuts are created in: `Start Menu\Programs\FirstFun\`

### Directory Structure

```
Accounts/        - Active .reg files for each account (8 accounts currently)
Backups/         - Timestamped backups organized by account name
registry_files/  - Historical/test registry files (not used by main scripts)
.vscode/         - Contains PowerShell debug configuration
```

### Account Switching Workflow

The system follows this sequence when switching accounts:

1. **Lock Check**: Verifies no other instance is running (prevents registry corruption)
2. **Lock Creation**: Creates lock file in repository root (`.lastwar.lock`) with account name, PID, and timestamp
3. **Initialization**: Validates account name exists in Accounts/ folder
4. **Backup**: Creates timestamped backup in Backups/{AccountName}/ (only if different from last backup based on SHA256 hash)
5. **Import**: Loads account .reg file into Windows Registry using `reg import`
6. **Launch**: Starts game via `C:\Users\vladh\AppData\Local\TheLastWar\Launch.exe`
7. **Monitor**: Waits for game process (searches for *LastWar.exe*, timeout 30s)
8. **Await Exit**: Blocks until game process terminates
9. **Grace Period**: Waits 1 second for registry write operations to complete
10. **Export**: Saves current registry state back to account .reg file using `reg export`
11. **Lock Release**: Removes lock file (guaranteed via try-finally block)

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

### Running with error logging
```powershell
.\Launch-LastWar.ps1 -Conta <AccountName>
```

### Comparing two registry keys
```powershell
.\Compare-LastWarKeys.ps1 -KeyPath1 "HKCU:\Software\FirstFun\LastWar-Account1" `
                          -KeyPath2 "HKCU:\Software\FirstFun\LastWar-Account2" `
                          -OutRegFile "C:\Backups\Diff.reg"
```

### Creating/updating Start Menu shortcuts
```powershell
.\Create-Shortcuts.ps1
.\Create-Shortcuts.ps1 -IconPath "C:\Icons\game.ico"  # With custom icon
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

- **Repository Location**: `D:\source\repos\LastWar-AccountManager\`
- **Registry Path**: `HKEY_CURRENT_USER\Software\FirstFun\Last War-Survival Game`
- **Game Launcher**: `C:\Users\vladh\AppData\Local\TheLastWar\Launch.exe`
- **Game Root**: `C:\Users\vladh\AppData\Local\TheLastWar`
- **Default Max Backups**: 10 per account
- **GitHub Repository**: `git@github.com:vladhietala/LastWar-AccountManager.git` (private, uses SSH)

## Script Requirements

- PowerShell Core (`#Requires -PSEdition core` in Start-LastWar.ps1)
- Windows Registry access (uses `reg.exe` commands)
- Write permissions to script directory for backups

## Error Handling

All scripts use proper error handling with try-catch blocks. The main script will:
- Validate account existence before proceeding
- Check for required files and paths
- Throw descriptive errors with context
- Log errors to temp directory when using Launch-LastWar.ps1

## Backup System Details

- Backups are stored in `Backups/{AccountName}/Backup_{AccountName}_{timestamp}.reg`
- SHA256 hash comparison prevents duplicate backups
- Automatic cleanup maintains only the N most recent backups (configurable via `-MaxBackups`)
- Timestamp format: `yyyyMMdd_HHmmss`

## Process Monitoring

The game launch process uses a polling mechanism:
- Searches for processes matching `*LastWar*` pattern
- 30-second timeout with 1-second intervals
- Waits for game process to exit before exporting registry changes
- 1-second grace period after exit for write operations to complete

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

### Benefits
- Prevents Export-GameRegistry from one account overwriting another account's .reg file
- Allows safe sequential account switching without corruption
- Self-healing: automatically removes stale locks from crashed processes

## Shortcut Management

The repository includes a script for managing Start Menu shortcuts:

### Create-Shortcuts.ps1
- **Auto-discovery**: Scans Accounts/ folder for all .reg files
- **Creates shortcuts**: In `Start Menu\Programs\FirstFun\` for each account
- **Orphan cleanup**: Removes shortcuts for deleted accounts
- **Dynamic paths**: Uses current repository location automatically
- **Custom icons**: Optional `-IconPath` parameter for personalization

### Workflow
1. Add/remove account .reg files in Accounts/
2. Run `.\Create-Shortcuts.ps1`
3. All shortcuts update automatically with correct paths

### Benefits
- No manual shortcut editing needed
- Repository-independent (works after moving repo)
- Versionable in Git (script, not binary .lnk files)
- Quick access via Windows Search (Win + type account name)
