# LastWar Account Manager

A PowerShell-based Windows Registry management system for switching between multiple accounts in "The Last War: Survival Game".

## Features

- **Multi-Account Support**: Easily switch between different game accounts
- **Automatic Backup**: Creates timestamped backups with SHA256 deduplication
- **Registry Management**: Handles import/export of game registry settings
- **Process Monitoring**: Automatically launches game and monitors process lifecycle
- **Error Logging**: Comprehensive error handling and logging

## Requirements

- Windows OS
- PowerShell Core
- The Last War: Survival Game installed at `C:\Users\[username]\AppData\Local\TheLastWar\`

## Quick Start

### Basic Usage

```powershell
# Launch game with specific account
.\Start-LastWar.ps1 -Conta AccountName

# Launch with custom backup retention
.\Start-LastWar.ps1 -Conta AccountName -MaxBackups 15

# Launch with error logging
.\Launch-LastWar.ps1 -Conta AccountName
```

### Adding a New Account

1. Export your game's registry settings to a `.reg` file
2. Place the file in the `Accounts/` folder with a descriptive name
3. The script will automatically detect it as an available account

## Project Structure

```
.
├── Accounts/           # Account registry files (.reg)
├── Backups/           # Automatic timestamped backups (organized by account)
├── registry_files/    # Historical/test registry files
├── Start-LastWar.ps1  # Main script
├── Launch-LastWar.ps1 # Wrapper with error logging
├── Compare-LastWarKeys.ps1  # Registry comparison utility
└── CLAUDE.md          # Developer documentation
```

## How It Works

1. **Backup**: Creates a backup of current account state (with deduplication)
2. **Import**: Loads selected account's registry settings
3. **Launch**: Starts the game launcher
4. **Monitor**: Waits for game process to start and exit
5. **Export**: Saves any registry changes back to account file

## Utilities

### Compare Registry Keys

```powershell
.\Compare-LastWarKeys.ps1 -KeyPath1 "HKCU:\Software\FirstFun\LastWar-Account1" `
                          -KeyPath2 "HKCU:\Software\FirstFun\LastWar-Account2" `
                          -OutRegFile "C:\Backups\Diff.reg"
```

## Configuration

Key constants are defined in `Start-LastWar.ps1`:
- Registry Path: `HKEY_CURRENT_USER\Software\FirstFun\Last War-Survival Game`
- Game Launcher: `C:\Users\vladh\AppData\Local\TheLastWar\Launch.exe`
- Default Max Backups: 10 per account

## Security Note

⚠️ **Important**: Registry files may contain sensitive game account data. The `.gitignore` is configured to exclude `Accounts/*.reg` files by default. Be careful not to commit sensitive data to public repositories.

## Development

For detailed architecture and development guidance, see [CLAUDE.md](CLAUDE.md).

## License

This project is personal tooling. Use at your own risk.

## Author

Vlad
