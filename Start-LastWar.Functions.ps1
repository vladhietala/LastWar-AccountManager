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

    .DESCRIPTION
        Verifica se o diretório do jogo e o launcher existem antes de tentar executar

    .THROWS
        Lança exceção se o jogo não estiver instalado corretamente
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

    .DESCRIPTION
        Verifica a existência de um arquivo de lock e valida se o processo associado ainda está ativo.
        Esta função apenas lê o estado do lock sem modificá-lo.

    .OUTPUTS
        Retorna um objeto com informações do lock incluindo:
        - IsLocked: Se há um processo ativo
        - IsOrphaned: Se o lock existe mas o processo não
        - IsCorrupted: Se o arquivo está corrompido
        - AccountName, ProcessId, LockTime: Dados do lock (quando disponíveis)
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

    .DESCRIPTION
        Verifica o estado do lock e remove se estiver órfão ou corrompido
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

function Assert-NoExistingLock {
    <#
    .SYNOPSIS
        Verifica se existe um lock ativo e aborta a execução se houver

    .DESCRIPTION
        Valida que não há outra instância do script em execução.
        Se houver, exibe mensagem de erro detalhada e encerra o processo.
    #>
    $existingLock = Test-ScriptLock

    if (-not ($existingLock -and $existingLock.IsLocked)) {
        return  # Sem lock ativo, pode continuar
    }

    # ConvertFrom-Json já deserializa ISO 8601 para DateTime
    $lockTime = if ($existingLock.LockTime -is [DateTime]) {
        $existingLock.LockTime
    } else {
        [DateTime]::ParseExact($existingLock.LockTime, "o", [System.Globalization.CultureInfo]::InvariantCulture)
    }

    $duration = (Get-Date) - $lockTime

    Write-Host ""
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "ERRO: Outra instância do script já está em execução!" -ForegroundColor Red
    Write-Host "================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host ("Conta em execução: {0}" -f $existingLock.AccountName) -ForegroundColor Yellow
    Write-Host ("Process ID: {0}" -f $existingLock.ProcessId) -ForegroundColor Yellow
    Write-Host ("Iniciado em: {0}" -f $lockTime.ToString('dd/MM/yyyy HH:mm:ss')) -ForegroundColor Yellow
    Write-Host ("Tempo decorrido: {0} minutos e {1} segundos" -f [Math]::Floor($duration.TotalMinutes), $duration.Seconds) -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Aguarde a outra instância finalizar antes de iniciar uma nova." -ForegroundColor Cyan
    Write-Host "Isso previne que o Export-GameRegistry de uma conta sobrescreva" -ForegroundColor Cyan
    Write-Host "incorretamente o arquivo .reg de outra conta." -ForegroundColor Cyan
    Write-Host ""
    Start-Sleep -Seconds $script:ERROR_MESSAGE_DISPLAY_SECONDS
    exit 1
}

function New-ScriptLock {
    <#
    .SYNOPSIS
        Cria um arquivo de lock para prevenir execuções simultâneas

    .PARAMETER AccountName
        Nome da conta que está sendo executada
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

    .DESCRIPTION
        Tenta múltiplas estratégias para obter o caminho do script,
        garantindo compatibilidade em diferentes contextos de execução
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

    .PARAMETER ScriptPath
        Caminho completo do script a ser executado

    .PARAMETER Conta
        Nome da conta

    .PARAMETER MaxBackups
        Número máximo de backups

    .PARAMETER BoundParameters
        Parâmetros bound do cmdlet original
    #>
    param(
        [string]$ScriptPath,
        [string]$Conta,
        [int]$MaxBackups,
        [hashtable]$BoundParameters
    )

    $argList = @("-NoProfile")

    # Adiciona -NoExit se Verbose estiver ativo (para manter janela aberta e ver as mensagens)
    if ($BoundParameters['Verbose']) {
        $argList += "-NoExit"
    }

    $argList += @(
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

function Show-ElevationPrompt {
    <#
    .SYNOPSIS
        Exibe mensagem informativa sobre a elevação de privilégios
    #>
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "  Elevação de Privilégios Necessária" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "O jogo requer permissões de administrador." -ForegroundColor Cyan
    Write-Host "Solicitando elevação..." -ForegroundColor Cyan
    Write-Host ""
}

function Request-Elevation {
    <#
    .SYNOPSIS
        Solicita elevação de privilégios e relança o script como administrador

    .PARAMETER Conta
        Nome da conta que está sendo carregada

    .PARAMETER MaxBackups
        Número máximo de backups

    .PARAMETER BoundParameters
        Parâmetros bound do cmdlet original
    #>
    param (
        [string]$Conta,
        [int]$MaxBackups,
        [hashtable]$BoundParameters
    )

    Show-ElevationPrompt

    try {
        $scriptFullPath = Get-ScriptFullPath
        Write-Verbose "Caminho do script para elevação: $scriptFullPath"

        $argList = Build-ElevatedProcessArguments `
            -ScriptPath $scriptFullPath `
            -Conta $Conta `
            -MaxBackups $MaxBackups `
            -BoundParameters $BoundParameters

        Write-Verbose "Argumentos para processo elevado: $($argList -join ' ')"

        $process = Start-Process -FilePath "pwsh.exe" -ArgumentList $argList -Verb RunAs -PassThru
        Write-Verbose "Processo elevado iniciado com PID: $($process.Id)"

        exit 0
    }
    catch {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "  ERRO" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "Falha ao elevar privilégios: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "O script precisa ser executado como administrador." -ForegroundColor Yellow
        Write-Host ""
        Start-Sleep -Seconds 5
        exit 1
    }
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

    .PARAMETER SourceFile
        Arquivo fonte a ser verificado

    .PARAMETER BackupFolder
        Pasta onde estão os backups

    .PARAMETER Conta
        Nome da conta para filtrar backups

    .OUTPUTS
        $true se backup é necessário, $false se arquivo é idêntico ao último backup
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

    .PARAMETER BackupFolder
        Pasta onde estão os backups

    .PARAMETER Conta
        Nome da conta para filtrar backups

    .PARAMETER MaxBackups
        Número máximo de backups a manter
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

    .PARAMETER Path
        Caminho base onde criar a pasta de backups

    .PARAMETER Conta
        Nome da conta

    .PARAMETER SourceFile
        Arquivo fonte a ser copiado

    .PARAMETER MaxBackups
        Número máximo de backups a manter
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

function Invoke-RegistryCommand {
    <#
    .SYNOPSIS
        Executa comandos reg.exe com tratamento de erro padronizado

    .PARAMETER Operation
        A operação a executar (import, export, etc)

    .PARAMETER Arguments
        Array de argumentos para passar ao reg.exe

    .PARAMETER SuccessMessage
        Mensagem a exibir em caso de sucesso

    .PARAMETER ErrorContext
        Contexto do erro para mensagens mais claras

    .OUTPUTS
        Retorna $true se sucesso, lança exceção se falhar
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('import', 'export')]
        [string]$Operation,

        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$SuccessMessage,

        [Parameter(Mandatory)]
        [string]$ErrorContext
    )

    try {
        $result = & reg $Operation @Arguments 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host $SuccessMessage
            return $true
        }
        else {
            throw ("reg {0} retornou erro (código {1}): {2}" -f $Operation, $LASTEXITCODE, $result)
        }
    }
    catch {
        throw ("{0}: {1}" -f $ErrorContext, $_)
    }
}

function Import-GameRegistry {
    param (
        [string]$RegFilePath
    )

    Write-Host "Importando configurações do registro..."

    Invoke-RegistryCommand `
        -Operation 'import' `
        -Arguments @($RegFilePath) `
        -SuccessMessage "Configurações importadas com sucesso" `
        -ErrorContext "Erro ao importar configurações"
}

function Export-GameRegistry {
    param (
        [string]$RegFilePath
    )

    Write-Host "Atualizando arquivo de registro com as novas configurações..."

    Invoke-RegistryCommand `
        -Operation 'export' `
        -Arguments @($script:REGISTRY_PATH, $RegFilePath, '/y') `
        -SuccessMessage "Configurações salvas com sucesso" `
        -ErrorContext "Erro ao salvar configurações"
}

function Find-GameProcess {
    [CmdletBinding()]
    param()

    # Aguarda até encontrar o processo do jogo
    $maxAttempts = $script:GAME_PROCESS_TIMEOUT_SECONDS
    $attempt = 0
    $gameProcess = $null

    Write-Verbose "Procurando processo do jogo (timeout: $maxAttempts segundos)..."

    while ($attempt -lt $maxAttempts) {
        # Procura por LastWar.exe em qualquer pasta 'app-x.x.x
        $gameProcess = Get-Process -Name "*LastWar*" -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($gameProcess) {
            Write-Host ("Processo do jogo encontrado: {0}" -f $gameProcess.Path)
            return $gameProcess
        }

        # Mostra progresso periodicamente
        if (($attempt % $script:VERBOSE_STATUS_INTERVAL_SECONDS) -eq 0 -and $attempt -gt 0) {
            Write-Verbose "Ainda aguardando processo do jogo... ($attempt/$maxAttempts segundos)"
        }

        Start-Sleep -Seconds 1
        $attempt++
    }

    throw "Não foi possível encontrar o processo do jogo após $maxAttempts segundos"
}

function Start-GameProcess {
    Write-Host "Iniciando The Last War..."
    try {
        # Inicia o launcher
        Start-Process -FilePath $script:LAUNCHER_PATH -PassThru | Out-Null
        Write-Host "Launcher iniciado, procurando processo do jogo..."

        # Encontra o processo real do jogo
        $gameProcess = Find-GameProcess

        Write-Host "Aguardando o jogo fechar..."
        $gameProcess.WaitForExit()

        # Aguarda um pouco para garantir que operações de escrita no registro sejam finalizadas
        Start-Sleep -Seconds $script:REGISTRY_WRITE_GRACE_PERIOD_SECONDS
    }
    catch {
        throw "Erro ao iniciar/monitorar o jogo: $_"
    }
}

function Invoke-AccountSwitch {
    <#
    .SYNOPSIS
        Orquestra o fluxo completo de troca de conta

    .DESCRIPTION
        Executa o fluxo completo para trocar de conta:
        1. Inicializa workspace e valida arquivo da conta
        2. Cria backup do estado atual da conta
        3. Importa configurações de registro da conta
        4. Inicia o jogo e aguarda finalização
        5. Exporta configurações de registro atualizadas

    .PARAMETER Conta
        Nome da conta a ser carregada

    .PARAMETER MaxBackups
        Número máximo de backups a manter por conta
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Conta,

        [Parameter(Mandatory)]
        [int]$MaxBackups
    )

    # Inicializa e verifica o ambiente
    $regFilePath = Initialize-Workspace -Conta $Conta
    Write-Host ("Carregando conta {0} a partir de: {1}" -f $Conta, $regFilePath)

    # Cria backup das configurações atuais
    New-RegistryBackup -Path $script:REGEDIT_ROOT -Conta $Conta -SourceFile $regFilePath -MaxBackups $MaxBackups

    # Importa as configurações da conta
    Import-GameRegistry -RegFilePath $regFilePath

    Start-Sleep -Seconds $script:POST_IMPORT_DELAY_SECONDS

    # Inicia o jogo e aguarda finalizar
    Start-GameProcess

    # Exporta as novas configurações
    Export-GameRegistry -RegFilePath $regFilePath

    Write-Host "Processo finalizado!"
    Start-Sleep -Seconds $script:REGISTRY_WRITE_GRACE_PERIOD_SECONDS
}

function Show-ErrorMessage {
    <#
    .SYNOPSIS
        Exibe mensagem de erro formatada de forma consistente

    .PARAMETER ErrorRecord
        O registro de erro a ser exibido

    .PARAMETER Title
        Título da mensagem de erro (padrão: "ERRO CRÍTICO")

    .PARAMETER WaitForKeyPress
        Se deve aguardar o usuário pressionar uma tecla antes de continuar
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
