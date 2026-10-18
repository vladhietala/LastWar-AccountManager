# LastWar Account Manager

A PowerShell-based Windows Registry management system for switching between multiple accounts in "The Last War: Survival Game".

**🌐 Languages**: [English](README.md) | [Português (Brasil)](README.pt-BR.md)

## Features

- **Multi-Account Support**: Easily switch between different game accounts
- **Automatic Backup**: Creates timestamped backups with SHA256 deduplication
- **Registry Management**: Handles import/export of game registry settings
- **Process Monitoring**: Automatically launches game and monitors process lifecycle
- **Error Logging**: Comprehensive error handling and logging

## Requirements

- Windows OS
- PowerShell Core
- The Last War: Survival Game installed at `%LOCALAPPDATA%\FunFly\Last War-Survival Game\`
- Administrator privileges are not required to run the account switcher.

## Quick Start

### Basic Usage

```powershell
# Launch game with specific account
.\Start-LastWar.ps1 -Account AccountName

# Launch with custom backup retention
.\Start-LastWar.ps1 -Account AccountName -MaxBackups 15

# Launch with error logging
.\Tools\Launch-LastWar.ps1 -Account AccountName
```

### Adding a New Account

1. Export your game's registry settings to a `.reg` file
2. Place the file in the `Accounts/` folder with a descriptive name
3. The script will automatically detect it as an available account

## Project Structure

```
.
├── Accounts/                      # Account registry files (.reg)
├── Backups/                       # Automatic timestamped backups (organized by account)
├── Tools/                         # Utility scripts
│   ├── Compare-LastWarKeys.ps1    # Registry comparison utility
│   ├── ConvertFrom-RegHex.ps1     # Registry hex value decoder
│   └── Launch-LastWar.ps1         # Wrapper with error logging
├── Start-LastWar.ps1              # Main script
├── Start-LastWar.Functions.ps1    # Shared functions
├── Create-Shortcuts.ps1           # Start Menu shortcut manager
└── CLAUDE.md                      # Developer documentation
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
.\Tools\Compare-LastWarKeys.ps1 -KeyPath1 "HKCU:\Software\FunFly\LastWar-Account1" `
                                -KeyPath2 "HKCU:\Software\FunFly\LastWar-Account2" `
                                -OutRegFile "C:\Backups\Diff.reg"
```

### Decode Registry Hex Values

```powershell
.\Tools\ConvertFrom-RegHex.ps1 -RegFilePath ".\Accounts\Account.reg"
.\Tools\ConvertFrom-RegHex.ps1 -RegFilePath ".\Accounts\Account.reg" -OutputFormat Json
```

### Create/Update Start Menu Shortcuts

```powershell
.\Create-Shortcuts.ps1
.\Create-Shortcuts.ps1 -IconPath "C:\Icons\game.ico"
.\Create-Shortcuts.ps1 -PinToStart
```

## Configuration

Key constants are defined in `Start-LastWar.ps1`:

- Registry Path: `HKEY_CURRENT_USER\Software\FunFly\Last War-Survival Game`
- Game Launcher: `%LOCALAPPDATA%\FunFly\Last War-Survival Game\LastWarLauncher.exe`
- Default Max Backups: 20 per account

## Security Note

⚠️ **Important**: Registry files may contain sensitive game account data. The `.gitignore` is configured to exclude `Accounts/*.reg` files by default. Be careful not to commit sensitive data to public repositories.

## Development

For detailed architecture and development guidance, see [CLAUDE.md](CLAUDE.md).

## License

This project is personal tooling. Use at your own risk.

## Author

#1306 [SOF]Vlad Țepeș ঌ (retired)
