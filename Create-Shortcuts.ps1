#Requires -PSEdition core

<#
.SYNOPSIS
    Creates Start Menu shortcuts for all LastWar Account Manager accounts

.DESCRIPTION
    This script automatically discovers all accounts in the Accounts/ folder
    and creates shortcuts in the Windows Start Menu for quick access.

    Shortcuts are created in: Start Menu\Programs\FunFly\

    When moving the repository, just run this script again to
    update all shortcuts with the new paths.

.PARAMETER IconPath
    Optional path to a custom icon (.ico)

.PARAMETER PinToStart
    Attempts to pin shortcuts to the Start Menu (Windows 10/11)
    NOTE: May not work due to Windows restrictions

.EXAMPLE
    .\Create-Shortcuts.ps1
    Creates shortcuts for all discovered accounts

.EXAMPLE
    .\Create-Shortcuts.ps1 -IconPath "C:\Icons\game.ico"
    Creates shortcuts with custom icon

.EXAMPLE
    .\Create-Shortcuts.ps1 -PinToStart
    Creates shortcuts and attempts to pin them to Start Menu

.NOTES
    Author: Vlad
    Last Updated: 11/08/2025
#>

[CmdletBinding()]
param (
    [string]$IconPath = $null,

    [switch]$PinToStart
)

# Constants
$script:REPO_PATH = $PSScriptRoot
$script:LAUNCH_SCRIPT = Join-Path -Path $script:REPO_PATH -ChildPath "Start-LastWar.ps1"
$script:PWSH_PATH = "C:\Program Files\PowerShell\7\pwsh.exe"
$script:SHORTCUTS_FOLDER = Join-Path -Path $env:APPDATA -ChildPath "Microsoft\Windows\Start Menu\Programs\FunFly"
$script:ACCOUNTS_FOLDER = Join-Path -Path $script:REPO_PATH -ChildPath "Accounts"

function Get-AccountList {
    <#
    .SYNOPSIS
        Discovers all available accounts in the Accounts/ folder

    .DESCRIPTION
        Excludes template files like "Initial.reg" that are not real accounts
    #>
    if (-not (Test-Path $script:ACCOUNTS_FOLDER)) {
        throw "Accounts folder not found: $script:ACCOUNTS_FOLDER"
    }

    # Templates that should be ignored
    $excludedTemplates = @("Initial")

    $accounts = Get-ChildItem -Path $script:ACCOUNTS_FOLDER -Filter "*.reg" |
                ForEach-Object { $_.BaseName } |
                Where-Object { $_ -notin $excludedTemplates } |
                Sort-Object

    if ($accounts.Count -eq 0) {
        throw "No accounts found in: $script:ACCOUNTS_FOLDER"
    }

    return $accounts
}

function Set-ShortcutPinToStart {
    <#
    .SYNOPSIS
        Attempts to pin a shortcut to the Start Menu

    .PARAMETER ShortcutPath
        Full path of the .lnk shortcut

    .NOTES
        On Windows 10/11, Microsoft blocked the "Pin to Start" API programmatically for security.
        The verb.DoIt() call returns E_ACCESSDENIED (0x80070005) even when the verb exists.
        The only way to pin is manually by the user.

        Note about languages:
        - Verb names depend on the Windows language
        - The & character indicates the keyboard shortcut (e.g., "Unpi&n from Start")
        - The function removes & before comparison
        - Supports EN-US ("Pin to Start") and PT-BR ("Fixar no Iniciar")
    #>
    param (
        [Parameter(Mandatory)]
        [string]$ShortcutPath
    )

    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = Split-Path $ShortcutPath
        $file = Split-Path $ShortcutPath -Leaf

        $folderObj = $shell.NameSpace($folder)
        $fileObj = $folderObj.ParseName($file)

        # Check if shortcut is already pinned
        # Note: & is used for keyboard shortcuts (e.g., "Unpi&n from Start")
        $unpinVerb = $fileObj.Verbs() | Where-Object {
            $_.Name -replace '&', '' -match 'Unpin from Start|Desafixar do Iniciar|Unpin from taskbar'
        }
        if ($unpinVerb) {
            Write-Host "    ✓ Shortcut is already pinned to Start Menu" -ForegroundColor Green
            return $true
        }

        # Look for "Pin to Start" verb
        # Remove & for more reliable comparison across languages
        $pinVerb = $fileObj.Verbs() | Where-Object {
            $_.Name -replace '&', '' -match 'Pin to Start|Fixar no Iniciar'
        }

        if ($pinVerb) {
            try {
                $pinVerb.DoIt()
                Write-Host "    → Pin attempt made" -ForegroundColor Cyan
                Start-Sleep -Milliseconds 500

                # Check if it actually pinned
                $fileObj = $folderObj.ParseName($file)
                $unpinCheck = $fileObj.Verbs() | Where-Object {
                    $_.Name -replace '&', '' -match 'Unpin from Start|Desafixar do Iniciar'
                }
                if ($unpinCheck) {
                    Write-Host "    ✓ Shortcut pinned successfully!" -ForegroundColor Green
                    return $true
                }
            }
            catch {
                # Expected error: E_ACCESSDENIED (0x80070005)
                Write-Verbose "Error pinning: $_"
            }
        }

        # If we got here, couldn't pin automatically
        Write-Host "    ⚠ Windows blocked automatic pinning (system security)" -ForegroundColor Yellow
        Write-Host "      → To pin: Press Win, type '$($file.Replace('.lnk',''))', right-click → 'Pin to Start'" -ForegroundColor Gray
        return $false
    }
    catch {
        Write-Verbose "Error accessing shortcut: $_"
        return $false
    }
}

function New-AccountShortcut {
    <#
    .SYNOPSIS
        Creates a shortcut for a specific account

    .PARAMETER AccountName
        Account name to create shortcut for

    .PARAMETER IconPath
        Optional path to custom icon

    .PARAMETER PinToStart
        Whether to attempt pinning the shortcut to Start Menu
    #>
    param (
        [Parameter(Mandatory)]
        [string]$AccountName,

        [string]$IconPath = $null,

        [bool]$PinToStart = $false
    )

    # Create shortcuts folder if it doesn't exist
    if (-not (Test-Path $script:SHORTCUTS_FOLDER)) {
        New-Item -ItemType Directory -Path $script:SHORTCUTS_FOLDER -Force | Out-Null
        Write-Host "Shortcuts folder created: $script:SHORTCUTS_FOLDER" -ForegroundColor Cyan
    }

    $shortcutPath = Join-Path -Path $script:SHORTCUTS_FOLDER -ChildPath "$AccountName.lnk"

    try {
        # Create COM object to manipulate shortcuts
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)

        # Configure shortcut properties
        $shortcut.TargetPath = $script:PWSH_PATH
        $shortcut.Arguments = "-nop -file `"$script:LAUNCH_SCRIPT`" -Account `"$AccountName`""
        $shortcut.WorkingDirectory = $script:REPO_PATH
        $shortcut.Description = "Start LastWar with account $AccountName"
        $shortcut.WindowStyle = 1  # Normal (visible)

        # Set icon if provided
        if ($IconPath -and (Test-Path $IconPath)) {
            $shortcut.IconLocation = $IconPath
        }

        # Save the shortcut
        $shortcut.Save()

        Write-Host "  ✓ Shortcut created: $AccountName.lnk" -ForegroundColor Green

        # Release COM object
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null

        # Attempt to pin to Start Menu if requested
        if ($PinToStart) {
            Set-ShortcutPinToStart -ShortcutPath $shortcutPath | Out-Null
        }

        return $true
    }
    catch {
        Write-Host "  ✗ Error creating shortcut for $AccountName : $_" -ForegroundColor Red
        return $false
    }
}

function Remove-OrphanedShortcuts {
    <#
    .SYNOPSIS
        Removes orphaned shortcuts (accounts that no longer exist)

    .PARAMETER ValidAccounts
        List of valid accounts
    #>
    param (
        [Parameter(Mandatory)]
        [string[]]$ValidAccounts
    )

    if (-not (Test-Path $script:SHORTCUTS_FOLDER)) {
        return
    }

    $shortcuts = Get-ChildItem -Path $script:SHORTCUTS_FOLDER -Filter "*.lnk" -ErrorAction SilentlyContinue

    foreach ($shortcut in $shortcuts) {
        $shortcutName = $shortcut.BaseName

        # Skip the Launch.lnk shortcut (direct game shortcut)
        if ($shortcutName -eq "Launch") {
            continue
        }

        # If shortcut doesn't correspond to any valid account, remove it
        if ($shortcutName -notin $ValidAccounts) {
            try {
                Remove-Item $shortcut.FullName -Force
                Write-Host "  🗑 Orphaned shortcut removed: $shortcutName.lnk" -ForegroundColor Yellow
            }
            catch {
                Write-Warning "Could not remove orphaned shortcut: $shortcutName.lnk"
            }
        }
    }
}

# ============================================================================
# MAIN
# ============================================================================

try {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  LastWar Account Manager" -ForegroundColor Cyan
    Write-Host "  Shortcut Creation" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Validate prerequisites
    Write-Host "Validating environment..." -ForegroundColor Yellow

    if (-not (Test-Path $script:LAUNCH_SCRIPT)) {
        throw "Script Start-LastWar.ps1 not found at: $script:LAUNCH_SCRIPT"
    }

    if (-not (Test-Path $script:PWSH_PATH)) {
        throw "PowerShell 7 not found at: $script:PWSH_PATH"
    }

    Write-Host "✓ Environment validated" -ForegroundColor Green
    Write-Host ""

    # Discover accounts
    Write-Host "Discovering accounts..." -ForegroundColor Yellow
    $accounts = Get-AccountList
    Write-Host "✓ Found $($accounts.Count) accounts: $($accounts -join ', ')" -ForegroundColor Green
    Write-Host ""

    # Create shortcuts
    Write-Host "Creating shortcuts in: $script:SHORTCUTS_FOLDER" -ForegroundColor Yellow
    Write-Host ""

    $successCount = 0
    foreach ($account in $accounts) {
        if (New-AccountShortcut -AccountName $account -IconPath $IconPath -PinToStart $PinToStart.IsPresent) {
            $successCount++
        }
    }

    Write-Host ""

    # Remove orphaned shortcuts
    Write-Host "Checking for orphaned shortcuts..." -ForegroundColor Yellow
    Remove-OrphanedShortcuts -ValidAccounts $accounts
    Write-Host ""

    # Summary
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "✓ Shortcuts created/updated: $successCount of $($accounts.Count)" -ForegroundColor Green
    Write-Host "📁 Location: $script:SHORTCUTS_FOLDER" -ForegroundColor Cyan
    Write-Host ""
    if (-not $PinToStart) {
        Write-Host "💡 Tip: Use the -PinToStart parameter to attempt automatic pinning to Start Menu" -ForegroundColor Gray
    }
    Write-Host "To search quickly, press Win and type the account name." -ForegroundColor Gray
    Write-Host ""

    Start-Sleep -Seconds 3
}
catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  ERROR" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Start-Sleep -Seconds 5
    exit 1
}
