# Módulo contendo apenas as funções do Start-LastWar.ps1
# Este arquivo é usado pelos testes do Pester para importar funções sem executar o script completo

# Constantes (valores padrão para testes)
if (-not $script:REGEDIT_ROOT) {
    $script:REGEDIT_ROOT = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
}
if (-not $script:LOCK_FILE) {
    $script:LOCK_FILE = Join-Path -Path $script:REGEDIT_ROOT -ChildPath ".lastwar.lock"
}
if (-not $script:REGISTRY_PATH) {
    $script:REGISTRY_PATH = "HKEY_CURRENT_USER\Software\FirstFun\Last War-Survival Game"
}
if (-not $script:GAME_ROOT) {
    $script:GAME_ROOT = Join-Path -Path $env:LOCALAPPDATA -ChildPath "TheLastWar"
}
if (-not $script:LAUNCHER_PATH) {
    $script:LAUNCHER_PATH = Join-Path -Path $script:GAME_ROOT -ChildPath "Launch.exe"
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
    <#
    .SYNOPSIS
        Valida que o jogo está instalado e acessível
    #>
    if (-not (Test-Path $script:GAME_ROOT)) {
        throw "Diretório do jogo não encontrado: $script:GAME_ROOT`nVerifique se o jogo está instalado."
    }

    if (-not (Test-Path $script:LAUNCHER_PATH)) {
        throw "Launcher do jogo não encontrado: $script:LAUNCHER_PATH`nVerifique a instalação do jogo."
    }

    Write-Verbose "Instalação do jogo validada: $script:GAME_ROOT"
}

function Test-ScriptLock {
    <#
    .SYNOPSIS
        Verifica se existe outra instância do script em execução
    #>
    if (-not (Test-Path $script:LOCK_FILE)) {
        return $null
    }

    try {
        $lockContent = Get-Content $script:LOCK_FILE -Raw | ConvertFrom-Json

        # Verifica se o processo ainda está ativo
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
        # Lock file corrompido ou ilegível
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
    <#
    .SYNOPSIS
        Remove arquivo de lock órfão se o processo associado não existir mais
    #>
    $lockState = Test-ScriptLock

    if ($lockState -and ($lockState.IsOrphaned -or $lockState.IsCorrupted)) {
        try {
            Remove-Item $script:LOCK_FILE -Force -ErrorAction SilentlyContinue
            if ($lockState.IsOrphaned) {
                Write-Verbose "Lock órfão removido (PID: $($lockState.ProcessId))"
            } elseif ($lockState.IsCorrupted) {
                Write-Verbose "Lock corrompido removido"
            }
        }
        catch {
            Write-Warning "Não foi possível remover lock órfão: $_"
        }
    }
}

function New-ScriptLock {
    <#
    .SYNOPSIS
        Cria um arquivo de lock para prevenir execuções simultâneas
    #>
    param (
        [string]$AccountName
    )

    $lockData = @{
        AccountName = $AccountName
        ProcessId = $PID
        LockTime = (Get-Date).ToString("o")
    } | ConvertTo-Json

    try {
        $lockData | Set-Content -Path $script:LOCK_FILE -Force
        Write-Verbose "Lock criado: $script:LOCK_FILE (PID: $PID, Conta: $AccountName)"
    }
    catch {
        throw "Erro ao criar arquivo de lock: $_"
    }
}

function Remove-ScriptLock {
    <#
    .SYNOPSIS
        Remove o arquivo de lock do script
    #>
    try {
        if (Test-Path $script:LOCK_FILE) {
            Remove-Item $script:LOCK_FILE -Force
            Write-Verbose "Lock removido: $script:LOCK_FILE"
        }
    }
    catch {
        Write-Warning "Erro ao remover lock: $_"
    }
}

function Test-Administrator {
    <#
    .SYNOPSIS
        Verifica se o script está sendo executado com privilégios de administrador
    #>
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ScriptFullPath {
    <#
    .SYNOPSIS
        Obtém o caminho completo do script atual com fallbacks
    #>
    if ($PSCommandPath) {
        return $PSCommandPath
    } elseif ($MyInvocation.MyCommand.Path) {
        return $MyInvocation.MyCommand.Path
    } else {
        return Join-Path -Path $script:REGEDIT_ROOT -ChildPath "Start-LastWar.ps1"
    }
}

function Build-ElevatedProcessArguments {
    <#
    .SYNOPSIS
        Constrói a lista de argumentos para o processo elevado
    #>
    param(
        [string]$ScriptPath,
        [string]$Conta,
        [int]$MaxBackups,
        [hashtable]$BoundParameters
    )

    $argList = @(
        "-NoProfile"
        "-ExecutionPolicy", "Bypass"
        "-File", '"{0}"' -f $ScriptPath
        "-Conta", '"{0}"' -f $Conta
        "-MaxBackups", $MaxBackups
    )

    if ($BoundParameters['Verbose']) {
        $argList += "-Verbose"
    }

    return $argList
}

function Initialize-Workspace {
    param (
        [string]$Conta
    )

    $regFilePath = Join-Path -Path $script:REGEDIT_ROOT -ChildPath "Accounts" -AdditionalChildPath "$Conta.reg"
    if (-not (Test-Path $regFilePath)) {
        throw "Arquivo de registro não encontrado: $regFilePath"
    }

    return $regFilePath
}

function Test-BackupNeeded {
    <#
    .SYNOPSIS
        Verifica se um novo backup é necessário comparando com o mais recente
    #>
    param(
        [string]$SourceFile,
        [string]$BackupFolder,
        [string]$Conta
    )

    $latestBackup = Get-ChildItem -Path $BackupFolder -Filter "Backup_${Conta}_*.reg" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latestBackup) {
        return $true
    }

    try {
        $hashSource = Get-FileHash -Path $SourceFile -Algorithm SHA256
        $hashLatest = Get-FileHash -Path $latestBackup.FullName -Algorithm SHA256

        if ($hashSource.Hash -eq $hashLatest.Hash) {
            Write-Host ("Arquivo atual é idêntico ao backup mais recente ({0}). Pulando criação de backup." -f $latestBackup.Name)
            return $false
        }

        return $true
    }
    catch {
        Write-Warning "Não foi possível comparar hashes dos arquivos: $_"
        return $true  # Em caso de erro, cria o backup por segurança
    }
}

function Remove-OldBackups {
    <#
    .SYNOPSIS
        Remove backups antigos mantendo apenas os N mais recentes
    #>
    param(
        [string]$BackupFolder,
        [string]$Conta,
        [int]$MaxBackups
    )

    $oldBackups = Get-ChildItem -Path $BackupFolder -Filter "Backup_${Conta}_*.reg" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $MaxBackups

    if ($oldBackups) {
        $oldBackups | Remove-Item -Force
        Write-Verbose ("Removidos {0} backups antigos" -f $oldBackups.Count)
    }
}

function New-RegistryBackup {
    <#
    .SYNOPSIS
        Cria backup do arquivo de registro da conta
    #>
    param (
        [string]$Path,
        [string]$Conta,
        [string]$SourceFile,
        [int]$MaxBackups
    )

    # Cria pasta de backup
    $backupFolder = Join-Path -Path $Path -ChildPath "Backups" -AdditionalChildPath $Conta
    if (-not (Test-Path $backupFolder)) {
        New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
    }

    # Verifica se backup é necessário
    if (-not (Test-BackupNeeded -SourceFile $SourceFile -BackupFolder $backupFolder -Conta $Conta)) {
        return
    }

    # Cria backup com timestamp
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path -Path $backupFolder -ChildPath "Backup_${Conta}_${timestamp}.reg"

    try {
        Write-Host "Fazendo backup do arquivo atual em: $backupPath"
        Copy-Item -Path $SourceFile -Destination $backupPath -Force
        Write-Host "Backup realizado com sucesso"

        # Remove backups antigos
        Remove-OldBackups -BackupFolder $backupFolder -Conta $Conta -MaxBackups $MaxBackups
    }
    catch {
        Write-Warning "Não foi possível fazer o backup: $_"
    }
}

function Show-ErrorMessage {
    <#
    .SYNOPSIS
        Exibe mensagem de erro formatada de forma consistente
    #>
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [string]$Title = "ERRO CRÍTICO",

        [switch]$WaitForKeyPress
    )

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  $Title" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $ErrorRecord.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Detalhes técnicos:" -ForegroundColor Yellow
    Write-Host $ErrorRecord.ScriptStackTrace -ForegroundColor Gray
    Write-Host ""

    if ($WaitForKeyPress) {
        Write-Host "Pressione qualquer tecla para fechar..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
}
