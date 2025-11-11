#Requires -PSEdition core

<#
.SYNOPSIS
    Script para gerenciar configurações do The Last War para múltiplas contas.

.DESCRIPTION
    Este script gerencia as configurações do registro do The Last War, permitindo
    alternar entre diferentes contas, fazer backup das configurações e restaurá-las
    automaticamente.

.PARAMETER Conta
    Nome da conta a ser carregada. As contas disponíveis são descobertas dinamicamente
    da pasta Accounts/. Use tab completion para ver as opções disponíveis.

.NOTES
    Estrutura de pastas:
    - Accounts/ : Arquivos .reg das contas
    - Backups/  : Backups automáticos das contas

.PARAMETER MaxBackups
    Número máximo de backups a serem mantidos por conta. Padrão: 20

.EXAMPLE
    .\Start-LastWar.ps1 -Conta Vlad
    Inicia o jogo com as configurações da conta Vlad

.NOTES
    Autor: Vlad
    Última Atualização: 26/10/2025
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Nome da conta a ser carregada")]
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        # Descobrir contas dinamicamente da pasta Accounts
        $accountsPath = Join-Path -Path $PSScriptRoot -ChildPath "Accounts"
        if (Test-Path $accountsPath) {
            Get-ChildItem -Path $accountsPath -Filter "*.reg" -File |
                Where-Object { $_.Name -ne "Initial.reg" } |
                ForEach-Object {
                    $accountName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                    if ($accountName -like "$wordToComplete*") {
                        [System.Management.Automation.CompletionResult]::new(
                            $accountName,
                            $accountName,
                            'ParameterValue',
                            "Account: $accountName"
                        )
                    }
                }
        }
    })]
    [string]$Conta,

    [Parameter(Mandatory = $false, HelpMessage = "Número máximo de backups a serem mantidos por conta")]
    [ValidateRange(1, 100)]
    [int]$MaxBackups = 20,

    [Parameter(Mandatory = $false, HelpMessage = "Cria uma nova conta se não existir")]
    [switch]$CreateNew
)

# Caminho completo do script principal (deve ser definido ANTES do dot-sourcing para elevação de privilégios)
$script:MAIN_SCRIPT_PATH = $PSCommandPath

# Import de funções
. "$PSScriptRoot\Start-LastWar.Functions.ps1"

# Função usada na validação dos parâmetros (não está em Functions.ps1 porque depende de $PSScriptRoot)
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

if ($CreateNew) {
    # Modo criação: conta NÃO deve existir
    if ($matched) {
        throw "Conta '{0}' já existe. Use sem -CreateNew para carregá-la, ou escolha outro nome." -f $Conta
    }
    # Mantém o nome fornecido pelo usuário (não há matched para normalizar)
    Write-Host ("Modo de criação: Nova conta '{0}' será criada" -f $Conta) -ForegroundColor Cyan
}
else {
    # Modo normal: conta DEVE existir
    if (-not $matched) {
        throw "Conta '{0}' inválida. Contas disponíveis: {1}`nPara criar nova conta, use: -CreateNew" -f $Conta, ($availableAccounts -join ', ')
    }
    # Normaliza casing para o nome do arquivo
    $Conta = $matched
}

# Constantes (sobrescreve valores padrão de Functions.ps1 com valores de produção)
$script:REGISTRY_PATH = "HKEY_CURRENT_USER\Software\FunFly\Last War-Survival Game"
$script:GAME_ROOT = Join-Path -Path $env:LOCALAPPDATA -ChildPath "FunFly\Last War-Survival Game"
$script:LAUNCHER_PATH = Join-Path -Path $script:GAME_ROOT -ChildPath "LastWarLauncher.exe"

# Determina o diretório do script mesmo quando executado com -NoProfile
$script:REGEDIT_ROOT = if ($PSScriptRoot) {
    $PSScriptRoot # Usa $PSScriptRoot se disponível
} else {
    Split-Path -Parent -Path $MyInvocation.MyCommand.Definition # Fallback
}
$script:LOCK_FILE = Join-Path -Path $script:REGEDIT_ROOT -ChildPath ".lastwar.lock"

# Timing Constants
$script:GAME_PROCESS_TIMEOUT_SECONDS = 90
$script:REGISTRY_WRITE_GRACE_PERIOD_SECONDS = 1
$script:ERROR_MESSAGE_DISPLAY_SECONDS = 10
$script:POST_IMPORT_DELAY_SECONDS = 1
$script:VERBOSE_STATUS_INTERVAL_SECONDS = 10


try {
    Write-Verbose "Script rodando a partir de: $($script:REGEDIT_ROOT)"

    # Valida instalação do jogo
    Test-GameInstallation

    # Remove locks órfãos e verifica se há outra instância em execução
    Remove-OrphanedLock
    Assert-NoExistingLock

    # Verifica se precisa elevar privilégios (após validações de lock)
    if (-not (Test-Administrator)) {
        Request-Elevation -Conta $Conta -MaxBackups $MaxBackups -BoundParameters $PSBoundParameters
    }

    # Cria o lock para esta instância
    New-ScriptLock -AccountName $Conta

    try {
        Invoke-AccountSwitch -Conta $Conta -MaxBackups $MaxBackups -IsNewAccount $CreateNew
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
    Show-ErrorMessage -ErrorRecord $_ -WaitForKeyPress
    exit 1
}
