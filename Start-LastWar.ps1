#Requires -PSEdition core

<#
.SYNOPSIS
    Script para gerenciar configurações do The Last War para múltiplas contas.

.DESCRIPTION
    Este script gerencia as configurações do registro do The Last War, permitindo
    alternar entre diferentes contas, fazer backup das configurações e restaurá-las
    automaticamente.

.PARAMETER Conta
    Nome da conta a ser carregada. Valores permitidos: Vlad, Galahad, Coconut,
    sgtPincel, Camotroni, Amanda, Nick

.NOTES
    Estrutura de pastas:
    - Accounts/ : Arquivos .reg das contas
    - Backups/  : Backups automáticos das contas

.PARAMETER MaxBackups
    Número máximo de backups a serem mantidos por conta. Padrão: 10

.EXAMPLE
    .\Start-LastWar.ps1 -Conta Vlad
    Inicia o jogo com as configurações da conta Vlad

.NOTES
    Autor: Vlad
    Última Atualização: 26/10/2025
#>

[CmdletBinding()]
param (
    [string]$Conta = 'Vlad',
    [int]$MaxBackups = 10
)

# Função usada na validação dos parâmetros
function Get-AvailableAccounts {
    # Lista todos os arquivos .reg da pasta Accounts
    $accountsPath = Join-Path -Path $PSScriptRoot -ChildPath "Accounts"
    Get-ChildItem -Path $accountsPath -Filter "*.reg" |
    ForEach-Object { $_.BaseName } |
    Sort-Object
}

# Validação da conta (dinâmica, executada após o parsing dos parâmetros)
$availableAccounts = Get-AvailableAccounts
$matched = $availableAccounts | Where-Object { $_.Equals($Conta, 'InvariantCultureIgnoreCase') } | Select-Object -First 1
if (-not $matched) {
    throw "Conta '$Conta' inválida. Contas disponíveis: $($availableAccounts -join ', ')"
}
# Normaliza casing para o nome do arquivo
$Conta = $matched

# Constantes
$script:REGISTRY_PATH = "HKEY_CURRENT_USER\Software\FirstFun\Last War-Survival Game"
$script:LAUNCHER_PATH = "C:\Users\vladh\AppData\Local\TheLastWar\Launch.exe"
$script:GAME_ROOT = "C:\Users\vladh\AppData\Local\TheLastWar"
# Determina o diretório do script mesmo quando executado com -NoProfile
$script:REGEDIT_ROOT = if ($PSScriptRoot) {
    $PSScriptRoot # Usa $PSScriptRoot se disponível
} else {
    Split-Path -Parent -Path $MyInvocation.MyCommand.Definition # Fallback
}
$script:LOCK_FILE = Join-Path -Path $script:REGEDIT_ROOT -ChildPath ".lastwar.lock"

function Test-ScriptLock {
    <#
    .SYNOPSIS
        Verifica se existe outra instância do script em execução

    .DESCRIPTION
        Verifica a existência de um arquivo de lock e valida se o processo associado ainda está ativo

    .OUTPUTS
        Retorna um objeto com IsLocked, AccountName, ProcessId, LockTime se houver lock ativo
        Retorna $null se não houver lock ou se o processo já finalizou
    #>
    if (-not (Test-Path $script:LOCK_FILE)) {
        return $null
    }

    try {
        $lockContent = Get-Content $script:LOCK_FILE -Raw | ConvertFrom-Json

        # Verifica se o processo ainda está ativo
        $process = Get-Process -Id $lockContent.ProcessId -ErrorAction SilentlyContinue
        if ($process) {
            return [PSCustomObject]@{
                IsLocked = $true
                AccountName = $lockContent.AccountName
                ProcessId = $lockContent.ProcessId
                LockTime = $lockContent.LockTime
            }
        } else {
            # Processo não existe mais, remove lock órfão
            Remove-Item $script:LOCK_FILE -Force -ErrorAction SilentlyContinue
            return $null
        }
    }
    catch {
        # Lock file corrompido ou ilegível, remove
        Remove-Item $script:LOCK_FILE -Force -ErrorAction SilentlyContinue
        return $null
    }
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

function Request-Elevation {
    <#
    .SYNOPSIS
        Solicita elevação de privilégios e relança o script como administrador

    .PARAMETER Conta
        Nome da conta que está sendo carregada

    .PARAMETER MaxBackups
        Número máximo de backups
    #>
    param (
        [string]$Conta,
        [int]$MaxBackups,
        [hashtable]$BoundParameters
    )

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "  Elevação de Privilégios Necessária" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "O jogo requer permissões de administrador." -ForegroundColor Cyan
    Write-Host "Solicitando elevação..." -ForegroundColor Cyan
    Write-Host ""

    try {
        # Obtém o caminho completo do script atual
        $scriptFullPath = if ($PSCommandPath) {
            $PSCommandPath
        } elseif ($MyInvocation.MyCommand.Path) {
            $MyInvocation.MyCommand.Path
        } else {
            Join-Path -Path $script:REGEDIT_ROOT -ChildPath "Start-LastWar.ps1"
        }

        Write-Verbose "Caminho do script para elevação: $scriptFullPath"

        # Reconstrói os argumentos para passar ao processo elevado
        $argList = @(
            "-NoProfile"
            "-ExecutionPolicy", "Bypass"
            "-File", "`"$scriptFullPath`""
            "-Conta", "`"$Conta`""
            "-MaxBackups", $MaxBackups
        )

        # Adiciona -Verbose se estiver ativo
        if ($BoundParameters['Verbose']) {
            $argList += "-Verbose"
        }

        Write-Verbose "Argumentos para processo elevado: $($argList -join ' ')"

        # Inicia processo elevado
        # Nota: -Wait não funciona perfeitamente com -Verb RunAs
        # O processo elevado deve gerenciar sua própria vida útil
        $process = Start-Process -FilePath "pwsh.exe" -ArgumentList $argList -Verb RunAs -PassThru

        Write-Verbose "Processo elevado iniciado com PID: $($process.Id)"

        # Sai do processo não-elevado
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

function New-RegistryBackup {
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

    # Cria backup com timestamp
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path -Path $backupFolder -ChildPath "Backup_${Conta}_${timestamp}.reg"
    Write-Host "Fazendo backup do arquivo atual em: $backupPath"

    # Se já existir backups, compara o arquivo atual com o backup mais recente
    $latestBackup = Get-ChildItem -Path $backupFolder -Filter "Backup_${Conta}_*.reg" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($latestBackup) {
        try {
            $hashSource = Get-FileHash -Path $SourceFile -Algorithm SHA256
            $hashLatest = Get-FileHash -Path $latestBackup.FullName -Algorithm SHA256
            if ($hashSource.Hash -eq $hashLatest.Hash) {
                Write-Host "Arquivo atual é idêntico ao backup mais recente ($($latestBackup.Name)). Pulando criação de backup."
                return
            }
        }
        catch {
            Write-Warning "Não foi possível comparar hashes dos arquivos: $_"
            # Não aborta; segue tentando criar o backup
        }
    }

    try {
        Copy-Item -Path $SourceFile -Destination $backupPath -Force
        Write-Host "Backup realizado com sucesso"

        # Mantém apenas os $MaxBackups backups mais recentes
        Get-ChildItem -Path $backupFolder -Filter "Backup_${Conta}_*.reg" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $MaxBackups |
        Remove-Item -Force
    }
    catch {
        Write-Warning "Não foi possível fazer o backup: $_"
    }
}

function Import-GameRegistry {
    param (
        [string]$RegFilePath
    )

    Write-Host "Importando configurações do registro..."
    try {
        $result = reg import $RegFilePath 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Configurações importadas com sucesso"
        }
        else {
            throw "reg import retornou erro: $result"
        }
    }
    catch {
        throw "Erro ao importar configurações: $_"
    }
}

function Export-GameRegistry {
    param (
        [string]$RegFilePath
    )

    Write-Host "Atualizando arquivo de registro com as novas configurações..."
    try {
        $result = reg export $script:REGISTRY_PATH $RegFilePath /y 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Configurações salvas com sucesso"
        }
        else {
            throw "reg export retornou erro: $result"
        }
    }
    catch {
        throw "Erro ao salvar configurações: $_"
    }
}

function Find-GameProcess {
    [CmdletBinding()]
    param()

    # Aguarda até encontrar o processo do jogo
    # Timeout aumentado para 90 segundos para dar tempo de aceitar UAC (caso o script não esteja elevado)
    $maxAttempts = 90
    $attempt = 0
    $gameProcess = $null

    Write-Verbose "Procurando processo do jogo (timeout: $maxAttempts segundos)..."

    while ($attempt -lt $maxAttempts) {
        # Procura por LastWar.exe em qualquer pasta 'app-x.x.x
        $gameProcess = Get-Process -Name "*LastWar*" -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($gameProcess) {
            Write-Host "Processo do jogo encontrado: $($gameProcess.Path)"
            return $gameProcess
        }

        # Mostra progresso a cada 10 segundos
        if (($attempt % 10) -eq 0 -and $attempt -gt 0) {
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
        $launcher = Start-Process -FilePath $script:LAUNCHER_PATH -PassThru
        Write-Host "Launcher iniciado, procurando processo do jogo..."

        # Encontra o processo real do jogo
        $gameProcess = Find-GameProcess

        Write-Host "Aguardando o jogo fechar..."
        $gameProcess.WaitForExit()

        # Aguarda um pouco para garantir que operações de escrita no registro sejam finalizadas
        Start-Sleep -Seconds 1
    }
    catch {
        throw "Erro ao iniciar/monitorar o jogo: $_"
    }
}



try {
    Write-Verbose "Script rodando a partir de: $($script:REGEDIT_ROOT)"

    # Verifica se já existe outra instância em execução
    $existingLock = Test-ScriptLock
    if ($existingLock) {
        $lockTime = [DateTime]::Parse($existingLock.LockTime)
        $duration = (Get-Date) - $lockTime
        Write-Host ""
        Write-Host "================================================" -ForegroundColor Red
        Write-Host "ERRO: Outra instância do script já está em execução!" -ForegroundColor Red
        Write-Host "================================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "Conta em execução: $($existingLock.AccountName)" -ForegroundColor Yellow
        Write-Host "Process ID: $($existingLock.ProcessId)" -ForegroundColor Yellow
        Write-Host "Iniciado em: $($lockTime.ToString('dd/MM/yyyy HH:mm:ss'))" -ForegroundColor Yellow
        Write-Host "Tempo decorrido: $([Math]::Floor($duration.TotalMinutes)) minutos e $($duration.Seconds) segundos" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Aguarde a outra instância finalizar antes de iniciar uma nova." -ForegroundColor Cyan
        Write-Host "Isso previne que o Export-GameRegistry de uma conta sobrescreva" -ForegroundColor Cyan
        Write-Host "incorretamente o arquivo .reg de outra conta." -ForegroundColor Cyan
        Write-Host ""
        Start-Sleep -Seconds 10
        exit 1
    }

    # Verifica se precisa elevar privilégios (após validações de lock)
    if (-not (Test-Administrator)) {
        Request-Elevation -Conta $Conta -MaxBackups $MaxBackups -BoundParameters $PSBoundParameters
    }

    # Cria o lock para esta instância
    New-ScriptLock -AccountName $Conta

    try {
        # Inicializa e verifica o ambiente
        $regFilePath = Initialize-Workspace -Conta $Conta
        Write-Host "Carregando conta $Conta a partir de: $regFilePath"

        # Cria backup das configurações atuais
        New-RegistryBackup -Path $script:REGEDIT_ROOT -Conta $Conta -SourceFile $regFilePath -MaxBackups $MaxBackups

        # Importa as configurações da conta
        Import-GameRegistry -RegFilePath $regFilePath

        Start-Sleep -Seconds 1

        # Inicia o jogo e aguarda finalizar
        Start-GameProcess

        # Exporta as novas configurações
        Export-GameRegistry -RegFilePath $regFilePath

        Write-Host "Processo finalizado!"
        Start-Sleep -Seconds 1
    }
    catch {
        # Captura erro dentro do try interno, mas ainda remove o lock no finally
        throw
    }
    finally {
        # Garante que o lock seja removido mesmo em caso de erro
        Remove-ScriptLock
    }
}
catch {
    # Erro já foi tratado (lock foi removido no finally acima)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  ERRO CRÍTICO" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Detalhes técnicos:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    Write-Host ""
    Write-Host "Pressione qualquer tecla para fechar..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}
