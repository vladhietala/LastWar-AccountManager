#Requires -PSEdition core

<#
.SYNOPSIS
    Cria atalhos no Start Menu para todas as contas do LastWar Account Manager

.DESCRIPTION
    Este script descobre automaticamente todas as contas na pasta Accounts/
    e cria atalhos no Start Menu do Windows para acesso rápido.

    Os atalhos são criados em: Start Menu\Programs\FirstFun\

    Ao mover o repositório, basta executar este script novamente para
    atualizar todos os atalhos com os novos caminhos.

.PARAMETER IconPath
    Caminho opcional para um ícone personalizado (.ico)

.PARAMETER PinToStart
    Tenta fixar os atalhos no Start Menu (Windows 10/11)
    NOTA: Pode não funcionar devido a restrições do Windows

.EXAMPLE
    .\Create-Shortcuts.ps1
    Cria atalhos para todas as contas descobertas

.EXAMPLE
    .\Create-Shortcuts.ps1 -IconPath "C:\Icons\game.ico"
    Cria atalhos com ícone personalizado

.EXAMPLE
    .\Create-Shortcuts.ps1 -PinToStart
    Cria atalhos e tenta fixá-los no Start Menu

.NOTES
    Autor: Vlad
    Última Atualização: 08/11/2025
#>

[CmdletBinding()]
param (
    [string]$IconPath = $null,

    [switch]$PinToStart
)

# Constantes
$script:REPO_PATH = $PSScriptRoot
$script:LAUNCH_SCRIPT = Join-Path -Path $script:REPO_PATH -ChildPath "Launch-LastWar.ps1"
$script:PWSH_PATH = "C:\Program Files\PowerShell\7\pwsh.exe"
$script:SHORTCUTS_FOLDER = Join-Path -Path $env:APPDATA -ChildPath "Microsoft\Windows\Start Menu\Programs\FirstFun"
$script:ACCOUNTS_FOLDER = Join-Path -Path $script:REPO_PATH -ChildPath "Accounts"

function Get-AccountList {
    <#
    .SYNOPSIS
        Descobre todas as contas disponíveis na pasta Accounts/

    .DESCRIPTION
        Exclui arquivos template como "Initial.reg" que não são contas reais
    #>
    if (-not (Test-Path $script:ACCOUNTS_FOLDER)) {
        throw "Pasta de contas não encontrada: $script:ACCOUNTS_FOLDER"
    }

    # Templates que devem ser ignorados
    $excludedTemplates = @("Initial")

    $accounts = Get-ChildItem -Path $script:ACCOUNTS_FOLDER -Filter "*.reg" |
                ForEach-Object { $_.BaseName } |
                Where-Object { $_ -notin $excludedTemplates } |
                Sort-Object

    if ($accounts.Count -eq 0) {
        throw "Nenhuma conta encontrada em: $script:ACCOUNTS_FOLDER"
    }

    return $accounts
}

function Set-ShortcutPinToStart {
    <#
    .SYNOPSIS
        Tenta fixar um atalho no Start Menu

    .PARAMETER ShortcutPath
        Caminho completo do atalho .lnk

    .NOTES
        No Windows 10/11, a Microsoft bloqueou a API "Pin to Start" programaticamente por segurança.
        A chamada verb.DoIt() retorna E_ACCESSDENIED (0x80070005) mesmo quando o verb existe.
        A única forma de fixar é manualmente pelo usuário.

        Nota sobre idiomas:
        - Os nomes dos verbs dependem do idioma do Windows
        - O caractere & indica o atalho de teclado (ex: "Unpi&n from Start")
        - A função remove o & antes de fazer a comparação
        - Suporta EN-US ("Pin to Start") e PT-BR ("Fixar no Iniciar")
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

        # Verifica se o atalho já está pinado
        # Nota: & é usado para atalhos de teclado (ex: "Unpi&n from Start")
        $unpinVerb = $fileObj.Verbs() | Where-Object {
            $_.Name -replace '&', '' -match 'Unpin from Start|Desafixar do Iniciar|Unpin from taskbar'
        }
        if ($unpinVerb) {
            Write-Host "    ✓ Atalho já está fixado no Start Menu" -ForegroundColor Green
            return $true
        }

        # Procura o verb "Pin to Start"
        # Remove & para comparação mais confiável entre idiomas
        $pinVerb = $fileObj.Verbs() | Where-Object {
            $_.Name -replace '&', '' -match 'Pin to Start|Fixar no Iniciar'
        }

        if ($pinVerb) {
            try {
                $pinVerb.DoIt()
                Write-Host "    → Tentativa de fixar realizada" -ForegroundColor Cyan
                Start-Sleep -Milliseconds 500

                # Verifica se realmente fixou
                $fileObj = $folderObj.ParseName($file)
                $unpinCheck = $fileObj.Verbs() | Where-Object {
                    $_.Name -replace '&', '' -match 'Unpin from Start|Desafixar do Iniciar'
                }
                if ($unpinCheck) {
                    Write-Host "    ✓ Atalho fixado com sucesso!" -ForegroundColor Green
                    return $true
                }
            }
            catch {
                # Erro esperado: E_ACCESSDENIED (0x80070005)
                Write-Verbose "Erro ao fixar: $_"
            }
        }

        # Se chegou aqui, não conseguiu fixar automaticamente
        Write-Host "    ⚠ Windows bloqueou fixação automática (segurança do sistema)" -ForegroundColor Yellow
        Write-Host "      → Para fixar: Pressione Win, digite '$($file.Replace('.lnk',''))', clique direito → 'Fixar no Iniciar'" -ForegroundColor Gray
        return $false
    }
    catch {
        Write-Verbose "Erro ao acessar atalho: $_"
        return $false
    }
}

function New-AccountShortcut {
    <#
    .SYNOPSIS
        Cria um atalho para uma conta específica

    .PARAMETER AccountName
        Nome da conta para criar o atalho

    .PARAMETER IconPath
        Caminho opcional para ícone personalizado

    .PARAMETER PinToStart
        Se deve tentar fixar o atalho no Start Menu
    #>
    param (
        [Parameter(Mandatory)]
        [string]$AccountName,

        [string]$IconPath = $null,

        [bool]$PinToStart = $false
    )

    # Cria pasta de atalhos se não existir
    if (-not (Test-Path $script:SHORTCUTS_FOLDER)) {
        New-Item -ItemType Directory -Path $script:SHORTCUTS_FOLDER -Force | Out-Null
        Write-Host "Pasta de atalhos criada: $script:SHORTCUTS_FOLDER" -ForegroundColor Cyan
    }

    $shortcutPath = Join-Path -Path $script:SHORTCUTS_FOLDER -ChildPath "$AccountName.lnk"

    try {
        # Cria objeto COM para manipular atalhos
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)

        # Configura propriedades do atalho
        $shortcut.TargetPath = $script:PWSH_PATH
        $shortcut.Arguments = "-nop -nol -noni -w hidden -file `"$script:LAUNCH_SCRIPT`" -Conta `"$AccountName`""
        $shortcut.WorkingDirectory = $script:REPO_PATH
        $shortcut.Description = "Inicia LastWar com a conta $AccountName"
        $shortcut.WindowStyle = 7  # Minimizado

        # Define ícone se fornecido
        if ($IconPath -and (Test-Path $IconPath)) {
            $shortcut.IconLocation = $IconPath
        }

        # Salva o atalho
        $shortcut.Save()

        Write-Host "  ✓ Atalho criado: $AccountName.lnk" -ForegroundColor Green

        # Libera objeto COM
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null

        # Tenta fixar no Start Menu se solicitado
        if ($PinToStart) {
            Set-ShortcutPinToStart -ShortcutPath $shortcutPath | Out-Null
        }

        return $true
    }
    catch {
        Write-Host "  ✗ Erro ao criar atalho para $AccountName : $_" -ForegroundColor Red
        return $false
    }
}

function Remove-OrphanedShortcuts {
    <#
    .SYNOPSIS
        Remove atalhos órfãos (contas que não existem mais)

    .PARAMETER ValidAccounts
        Lista de contas válidas
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

        # Pula o atalho Launch.lnk (atalho direto do jogo)
        if ($shortcutName -eq "Launch") {
            continue
        }

        # Se o atalho não corresponde a nenhuma conta válida, remove
        if ($shortcutName -notin $ValidAccounts) {
            try {
                Remove-Item $shortcut.FullName -Force
                Write-Host "  🗑 Atalho órfão removido: $shortcutName.lnk" -ForegroundColor Yellow
            }
            catch {
                Write-Warning "Não foi possível remover atalho órfão: $shortcutName.lnk"
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
    Write-Host "  Criação de Atalhos" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Valida pré-requisitos
    Write-Host "Validando ambiente..." -ForegroundColor Yellow

    if (-not (Test-Path $script:LAUNCH_SCRIPT)) {
        throw "Script Launch-LastWar.ps1 não encontrado em: $script:LAUNCH_SCRIPT"
    }

    if (-not (Test-Path $script:PWSH_PATH)) {
        throw "PowerShell 7 não encontrado em: $script:PWSH_PATH"
    }

    Write-Host "✓ Ambiente validado" -ForegroundColor Green
    Write-Host ""

    # Descobre contas
    Write-Host "Descobrindo contas..." -ForegroundColor Yellow
    $accounts = Get-AccountList
    Write-Host "✓ Encontradas $($accounts.Count) contas: $($accounts -join ', ')" -ForegroundColor Green
    Write-Host ""

    # Cria atalhos
    Write-Host "Criando atalhos em: $script:SHORTCUTS_FOLDER" -ForegroundColor Yellow
    Write-Host ""

    $successCount = 0
    foreach ($account in $accounts) {
        if (New-AccountShortcut -AccountName $account -IconPath $IconPath -PinToStart $PinToStart.IsPresent) {
            $successCount++
        }
    }

    Write-Host ""

    # Remove atalhos órfãos
    Write-Host "Verificando atalhos órfãos..." -ForegroundColor Yellow
    Remove-OrphanedShortcuts -ValidAccounts $accounts
    Write-Host ""

    # Resumo
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Resumo" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "✓ Atalhos criados/atualizados: $successCount de $($accounts.Count)" -ForegroundColor Green
    Write-Host "📁 Local: $script:SHORTCUTS_FOLDER" -ForegroundColor Cyan
    Write-Host ""
    if (-not $PinToStart) {
        Write-Host "💡 Dica: Use o parâmetro -PinToStart para tentar fixar automaticamente no Start Menu" -ForegroundColor Gray
    }
    Write-Host "Para pesquisar rapidamente, pressione Win e digite o nome da conta." -ForegroundColor Gray
    Write-Host ""

    Start-Sleep -Seconds 3
}
catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  ERRO" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Start-Sleep -Seconds 5
    exit 1
}
