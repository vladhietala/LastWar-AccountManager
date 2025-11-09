BeforeAll {
    # Import apenas das funções, sem executar o script completo
    . "$PSScriptRoot\..\Start-LastWar.Functions.ps1"

    # Sobrescreve variáveis de script para testes
    $script:LOCK_FILE = Join-Path -Path $TestDrive -ChildPath ".lastwar.lock.test"
    $script:REGEDIT_ROOT = $TestDrive
}

Describe "Test-ScriptLock" {
    BeforeEach {
        # Limpa o lock file antes de cada teste
        if (Test-Path $script:LOCK_FILE) {
            Remove-Item $script:LOCK_FILE -Force
        }
    }

    Context "Quando não há arquivo de lock" {
        It "Deve retornar null" {
            $result = Test-ScriptLock
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Quando há arquivo de lock com processo ativo" {
        It "Deve retornar IsLocked = true" {
            # Cria lock file com PID atual
            $lockData = @{
                AccountName = "TestAccount"
                ProcessId = $PID
                LockTime = (Get-Date).ToString("o")
            } | ConvertTo-Json

            $lockData | Set-Content -Path $script:LOCK_FILE -Force

            $result = Test-ScriptLock
            $result | Should -Not -BeNullOrEmpty
            $result.IsLocked | Should -Be $true
            $result.IsOrphaned | Should -Be $false
            $result.IsCorrupted | Should -Be $false
            $result.AccountName | Should -Be "TestAccount"
            $result.ProcessId | Should -Be $PID
        }
    }

    Context "Quando há arquivo de lock com processo inexistente" {
        It "Deve retornar IsOrphaned = true" {
            # Cria lock file com PID que não existe (99999)
            $lockData = @{
                AccountName = "TestAccount"
                ProcessId = 99999
                LockTime = (Get-Date).ToString("o")
            } | ConvertTo-Json

            $lockData | Set-Content -Path $script:LOCK_FILE -Force

            $result = Test-ScriptLock
            $result | Should -Not -BeNullOrEmpty
            $result.IsLocked | Should -Be $false
            $result.IsOrphaned | Should -Be $true
            $result.IsCorrupted | Should -Be $false
            $result.ProcessId | Should -Be 99999
        }
    }

    Context "Quando há arquivo de lock corrompido" {
        It "Deve retornar IsCorrupted = true" {
            # Cria lock file com conteúdo inválido
            "invalid json content {{{" | Set-Content -Path $script:LOCK_FILE -Force

            $result = Test-ScriptLock
            $result | Should -Not -BeNullOrEmpty
            $result.IsLocked | Should -Be $false
            $result.IsOrphaned | Should -Be $false
            $result.IsCorrupted | Should -Be $true
        }
    }

    AfterEach {
        if (Test-Path $script:LOCK_FILE) {
            Remove-Item $script:LOCK_FILE -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Remove-OrphanedLock" {
    BeforeEach {
        if (Test-Path $script:LOCK_FILE) {
            Remove-Item $script:LOCK_FILE -Force
        }
    }

    Context "Quando há lock órfão" {
        It "Deve remover o arquivo de lock" {
            # Cria lock órfão
            $lockData = @{
                AccountName = "TestAccount"
                ProcessId = 99999
                LockTime = (Get-Date).ToString("o")
            } | ConvertTo-Json

            $lockData | Set-Content -Path $script:LOCK_FILE -Force

            Remove-OrphanedLock

            Test-Path $script:LOCK_FILE | Should -Be $false
        }
    }

    Context "Quando há lock corrompido" {
        It "Deve remover o arquivo de lock" {
            "invalid json" | Set-Content -Path $script:LOCK_FILE -Force

            Remove-OrphanedLock

            Test-Path $script:LOCK_FILE | Should -Be $false
        }
    }

    Context "Quando há lock ativo" {
        It "Não deve remover o arquivo de lock" {
            # Cria lock com processo ativo
            $lockData = @{
                AccountName = "TestAccount"
                ProcessId = $PID
                LockTime = (Get-Date).ToString("o")
            } | ConvertTo-Json

            $lockData | Set-Content -Path $script:LOCK_FILE -Force

            Remove-OrphanedLock

            Test-Path $script:LOCK_FILE | Should -Be $true
        }
    }

    Context "Quando não há lock" {
        It "Não deve gerar erro" {
            { Remove-OrphanedLock } | Should -Not -Throw
        }
    }

    AfterEach {
        if (Test-Path $script:LOCK_FILE) {
            Remove-Item $script:LOCK_FILE -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "New-ScriptLock" {
    BeforeEach {
        if (Test-Path $script:LOCK_FILE) {
            Remove-Item $script:LOCK_FILE -Force
        }
    }

    Context "Quando cria novo lock" {
        It "Deve criar arquivo de lock com dados corretos" {
            New-ScriptLock -AccountName "TestAccount"

            Test-Path $script:LOCK_FILE | Should -Be $true

            $lockContent = Get-Content $script:LOCK_FILE -Raw | ConvertFrom-Json
            $lockContent.AccountName | Should -Be "TestAccount"
            $lockContent.ProcessId | Should -Be $PID
            $lockContent.LockTime | Should -Not -BeNullOrEmpty
        }

        It "Deve criar lock com timestamp válido" {
            New-ScriptLock -AccountName "TestAccount"

            $lockContent = Get-Content $script:LOCK_FILE -Raw | ConvertFrom-Json

            # ConvertFrom-Json pode deserializar ISO 8601 para DateTime automaticamente
            # Verifica se é DateTime ou string ISO 8601 válida
            if ($lockContent.LockTime -is [DateTime]) {
                $lockContent.LockTime | Should -BeOfType [DateTime]
            } else {
                { [DateTime]::ParseExact($lockContent.LockTime, "o", [System.Globalization.CultureInfo]::InvariantCulture) } | Should -Not -Throw
            }
        }
    }

    AfterEach {
        if (Test-Path $script:LOCK_FILE) {
            Remove-Item $script:LOCK_FILE -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Remove-ScriptLock" {
    BeforeEach {
        if (Test-Path $script:LOCK_FILE) {
            Remove-Item $script:LOCK_FILE -Force
        }
    }

    Context "Quando há lock existente" {
        It "Deve remover o arquivo de lock" {
            # Cria lock
            New-ScriptLock -AccountName "TestAccount"

            Test-Path $script:LOCK_FILE | Should -Be $true

            Remove-ScriptLock

            Test-Path $script:LOCK_FILE | Should -Be $false
        }
    }

    Context "Quando não há lock" {
        It "Não deve gerar erro" {
            { Remove-ScriptLock } | Should -Not -Throw
        }
    }

    AfterEach {
        if (Test-Path $script:LOCK_FILE) {
            Remove-Item $script:LOCK_FILE -Force -ErrorAction SilentlyContinue
        }
    }
}
