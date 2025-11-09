BeforeAll {
    # Import apenas das funções, sem executar o script completo
    . "$PSScriptRoot\..\Start-LastWar.Functions.ps1"
}

Describe "Test-Administrator" {
    Context "Verificação de privilégios" {
        It "Deve retornar um valor booleano" {
            $result = Test-Administrator
            $result | Should -BeOfType [bool]
        }

        It "Deve retornar true ou false sem erro" {
            { Test-Administrator } | Should -Not -Throw
        }
    }
}

Describe "Get-ScriptFullPath" {
    Context "Quando PSCommandPath está disponível" {
        It "Deve retornar caminho absoluto" {
            $result = Get-ScriptFullPath
            $result | Should -Not -BeNullOrEmpty
            [System.IO.Path]::IsPathRooted($result) | Should -Be $true
        }

        It "Deve terminar com .ps1" {
            $result = Get-ScriptFullPath
            $result | Should -Match '\.ps1$'
        }
    }
}

Describe "Build-ElevatedProcessArguments" {
    Context "Argumentos básicos" {
        It "Deve incluir parâmetros obrigatórios" {
            $args = Build-ElevatedProcessArguments `
                -ScriptPath "C:\Test\Script.ps1" `
                -Conta "TestAccount" `
                -MaxBackups 10 `
                -BoundParameters @{}

            $args | Should -Contain "-NoProfile"
            $args | Should -Contain "-ExecutionPolicy"
            $args | Should -Contain "Bypass"
            # -File vem junto com o caminho: '-File "C:\Test\Script.ps1"'
            $args | Should -Contain '-File "C:\Test\Script.ps1"'
            # -Conta vem junto com o valor: '-Conta "TestAccount"'
            $args | Should -Contain '-Conta "TestAccount"'
            $args | Should -Contain "-MaxBackups"
            $args | Should -Contain 10
        }

        It "Deve incluir caminho do script com aspas no formato correto" {
            $args = Build-ElevatedProcessArguments `
                -ScriptPath "C:\Test\Script.ps1" `
                -Conta "TestAccount" `
                -MaxBackups 10 `
                -BoundParameters @{}

            # A função usa formato -f para criar: '-File "path"'
            $args | Should -Contain '-File "C:\Test\Script.ps1"'
        }

        It "Deve incluir conta com aspas no formato correto" {
            $args = Build-ElevatedProcessArguments `
                -ScriptPath "C:\Test\Script.ps1" `
                -Conta "TestAccount" `
                -MaxBackups 10 `
                -BoundParameters @{}

            # A função usa formato -f para criar: '-Conta "name"'
            $args | Should -Contain '-Conta "TestAccount"'
        }
    }

    Context "Com parâmetro Verbose" {
        It "Deve incluir -Verbose quando presente" {
            $args = Build-ElevatedProcessArguments `
                -ScriptPath "C:\Test\Script.ps1" `
                -Conta "TestAccount" `
                -MaxBackups 10 `
                -BoundParameters @{ Verbose = $true }

            $args | Should -Contain "-Verbose"
        }

        It "Não deve incluir -Verbose quando ausente" {
            $args = Build-ElevatedProcessArguments `
                -ScriptPath "C:\Test\Script.ps1" `
                -Conta "TestAccount" `
                -MaxBackups 10 `
                -BoundParameters @{}

            $args | Should -Not -Contain "-Verbose"
        }
    }
}

Describe "Initialize-Workspace" {
    BeforeEach {
        $script:REGEDIT_ROOT = $TestDrive
        $script:TestAccountsFolder = Join-Path -Path $TestDrive -ChildPath "Accounts"
        New-Item -ItemType Directory -Path $script:TestAccountsFolder -Force | Out-Null
    }

    Context "Quando arquivo de conta existe" {
        It "Deve retornar caminho do arquivo" {
            $testFile = Join-Path -Path $script:TestAccountsFolder -ChildPath "TestAccount.reg"
            "Test content" | Set-Content -Path $testFile -Force

            $result = Initialize-Workspace -Conta "TestAccount"

            $result | Should -Be $testFile
            Test-Path $result | Should -Be $true
        }
    }

    Context "Quando arquivo de conta não existe" {
        It "Deve lançar exceção" {
            { Initialize-Workspace -Conta "NonExistent" } | Should -Throw "*não encontrado*"
        }
    }

    AfterEach {
        if (Test-Path $script:TestAccountsFolder) {
            Remove-Item $script:TestAccountsFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Show-ErrorMessage" {
    Context "Formatação de erro" {
        It "Não deve lançar exceção ao mostrar erro" {
            try {
                throw "Test error"
            }
            catch {
                { Show-ErrorMessage -ErrorRecord $_ } | Should -Not -Throw
            }
        }

        It "Deve aceitar título customizado" {
            try {
                throw "Test error"
            }
            catch {
                { Show-ErrorMessage -ErrorRecord $_ -Title "CUSTOM ERROR" } | Should -Not -Throw
            }
        }
    }
}
