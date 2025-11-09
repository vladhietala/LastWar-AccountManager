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
    $maxAttempts = 30 # 30 segundos
    $attempt = 0
    $gameProcess = $null

    while ($attempt -lt $maxAttempts) {
        # Procura por LastWar.exe em qualquer pasta 'app-x.x.x
        $gameProcess = Get-Process -Name "*LastWar*" | Select-Object -First 1

        if ($gameProcess) {
            Write-Host "Processo do jogo encontrado: $($gameProcess.Path)"
            return $gameProcess
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

        # Aguarda um pouco para garantir que atualizações sejam finalizadas
        Start-Sleep -Seconds 2
    }
    catch {
        throw "Erro ao iniciar/monitorar o jogo: $_"
    }
}



try {
    Write-Verbose "Script rodando a partir de: $($script:REGEDIT_ROOT)"

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
    Start-Sleep -Seconds 5
}
catch {
    Write-Error $_
    exit 1
}
