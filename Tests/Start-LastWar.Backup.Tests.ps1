BeforeAll {
    # Import apenas das funções, sem executar o script completo
    . "$PSScriptRoot\..\Start-LastWar.Functions.ps1"

    # Sobrescreve variáveis de script para testes
    $script:REGEDIT_ROOT = $TestDrive
}

Describe "Test-BackupNeeded" {
    BeforeEach {
        $script:TestBackupFolder = Join-Path -Path $TestDrive -ChildPath "Backups\TestAccount"
        New-Item -ItemType Directory -Path $script:TestBackupFolder -Force | Out-Null

        $script:TestSourceFile = Join-Path -Path $TestDrive -ChildPath "source.reg"
        "Test content" | Set-Content -Path $script:TestSourceFile -Force
    }

    Context "Quando não há backups existentes" {
        It "Deve retornar true" {
            $result = Test-BackupNeeded -SourceFile $script:TestSourceFile -BackupFolder $script:TestBackupFolder -Conta "TestAccount"
            $result | Should -Be $true
        }
    }

    Context "Quando há backup idêntico" {
        It "Deve retornar false" {
            # Cria backup idêntico
            $backupFile = Join-Path -Path $script:TestBackupFolder -ChildPath "Backup_TestAccount_20250101_120000.reg"
            Copy-Item -Path $script:TestSourceFile -Destination $backupFile -Force

            $result = Test-BackupNeeded -SourceFile $script:TestSourceFile -BackupFolder $script:TestBackupFolder -Conta "TestAccount"
            $result | Should -Be $false
        }
    }

    Context "Quando há backup diferente" {
        It "Deve retornar true" {
            # Cria backup com conteúdo diferente
            $backupFile = Join-Path -Path $script:TestBackupFolder -ChildPath "Backup_TestAccount_20250101_120000.reg"
            "Different content" | Set-Content -Path $backupFile -Force

            $result = Test-BackupNeeded -SourceFile $script:TestSourceFile -BackupFolder $script:TestBackupFolder -Conta "TestAccount"
            $result | Should -Be $true
        }
    }

    AfterEach {
        if (Test-Path $script:TestBackupFolder) {
            Remove-Item $script:TestBackupFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $script:TestSourceFile) {
            Remove-Item $script:TestSourceFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Remove-OldBackups" {
    BeforeEach {
        $script:TestBackupFolder = Join-Path -Path $TestDrive -ChildPath "Backups\TestAccount"
        New-Item -ItemType Directory -Path $script:TestBackupFolder -Force | Out-Null
    }

    Context "Quando há mais backups que o limite" {
        It "Deve manter apenas os N mais recentes" {
            # Cria 5 backups com timestamps diferentes
            for ($i = 1; $i -le 5; $i++) {
                $backupFile = Join-Path -Path $script:TestBackupFolder -ChildPath "Backup_TestAccount_2025010$i`_120000.reg"
                "Backup $i" | Set-Content -Path $backupFile -Force
                Start-Sleep -Milliseconds 100
            }

            # Mantém apenas 3
            Remove-OldBackups -BackupFolder $script:TestBackupFolder -Conta "TestAccount" -MaxBackups 3

            $remainingBackups = Get-ChildItem -Path $script:TestBackupFolder -Filter "Backup_TestAccount_*.reg"
            $remainingBackups.Count | Should -Be 3
        }

        It "Deve remover os backups mais antigos" {
            # Cria backups com timestamps ordenados
            $timestamps = @("20250101_120000", "20250102_120000", "20250103_120000", "20250104_120000", "20250105_120000")
            foreach ($ts in $timestamps) {
                $backupFile = Join-Path -Path $script:TestBackupFolder -ChildPath "Backup_TestAccount_$ts.reg"
                "Backup" | Set-Content -Path $backupFile -Force
                Start-Sleep -Milliseconds 100
            }

            Remove-OldBackups -BackupFolder $script:TestBackupFolder -Conta "TestAccount" -MaxBackups 2

            $remainingBackups = Get-ChildItem -Path $script:TestBackupFolder -Filter "Backup_TestAccount_*.reg" | Sort-Object LastWriteTime -Descending
            $remainingBackups.Count | Should -Be 2
            # Os 2 mais recentes devem ser os últimos criados
            $remainingBackups[0].Name | Should -BeLike "*20250105*"
            $remainingBackups[1].Name | Should -BeLike "*20250104*"
        }
    }

    Context "Quando há menos backups que o limite" {
        It "Não deve remover nenhum backup" {
            # Cria apenas 2 backups
            for ($i = 1; $i -le 2; $i++) {
                $backupFile = Join-Path -Path $script:TestBackupFolder -ChildPath "Backup_TestAccount_2025010$i`_120000.reg"
                "Backup $i" | Set-Content -Path $backupFile -Force
            }

            Remove-OldBackups -BackupFolder $script:TestBackupFolder -Conta "TestAccount" -MaxBackups 5

            $remainingBackups = Get-ChildItem -Path $script:TestBackupFolder -Filter "Backup_TestAccount_*.reg"
            $remainingBackups.Count | Should -Be 2
        }
    }

    Context "Quando não há backups" {
        It "Não deve gerar erro" {
            { Remove-OldBackups -BackupFolder $script:TestBackupFolder -Conta "TestAccount" -MaxBackups 3 } | Should -Not -Throw
        }
    }

    AfterEach {
        if (Test-Path $script:TestBackupFolder) {
            Remove-Item $script:TestBackupFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "New-RegistryBackup" {
    BeforeEach {
        $script:TestSourceFile = Join-Path -Path $TestDrive -ChildPath "Accounts\TestAccount.reg"
        New-Item -ItemType Directory -Path (Split-Path $script:TestSourceFile) -Force | Out-Null
        "Windows Registry Editor Version 5.00" | Set-Content -Path $script:TestSourceFile -Force
    }

    Context "Quando cria primeiro backup" {
        It "Deve criar arquivo de backup" {
            New-RegistryBackup -Path $TestDrive -Conta "TestAccount" -SourceFile $script:TestSourceFile -MaxBackups 10

            $backupFolder = Join-Path -Path $TestDrive -ChildPath "Backups\TestAccount"
            Test-Path $backupFolder | Should -Be $true

            $backups = Get-ChildItem -Path $backupFolder -Filter "Backup_TestAccount_*.reg"
            $backups.Count | Should -Be 1
        }

        It "Deve nomear backup com timestamp correto" {
            New-RegistryBackup -Path $TestDrive -Conta "TestAccount" -SourceFile $script:TestSourceFile -MaxBackups 10

            $backupFolder = Join-Path -Path $TestDrive -ChildPath "Backups\TestAccount"
            $backup = Get-ChildItem -Path $backupFolder -Filter "Backup_TestAccount_*.reg" | Select-Object -First 1

            # Formato: Backup_TestAccount_YYYYMMDD_HHMMSS.reg
            $backup.Name | Should -Match "^Backup_TestAccount_\d{8}_\d{6}\.reg$"
        }
    }

    Context "Quando backup não é necessário" {
        It "Não deve criar novo backup" {
            # Cria primeiro backup
            New-RegistryBackup -Path $TestDrive -Conta "TestAccount" -SourceFile $script:TestSourceFile -MaxBackups 10

            # Tenta criar segundo backup sem alterar o arquivo
            New-RegistryBackup -Path $TestDrive -Conta "TestAccount" -SourceFile $script:TestSourceFile -MaxBackups 10

            $backupFolder = Join-Path -Path $TestDrive -ChildPath "Backups\TestAccount"
            $backups = Get-ChildItem -Path $backupFolder -Filter "Backup_TestAccount_*.reg"
            $backups.Count | Should -Be 1
        }
    }

    Context "Quando arquivo muda" {
        It "Deve criar novo backup" {
            # Cria primeiro backup
            New-RegistryBackup -Path $TestDrive -Conta "TestAccount" -SourceFile $script:TestSourceFile -MaxBackups 10

            Start-Sleep -Milliseconds 1100  # Garante timestamp diferente

            # Modifica arquivo
            "Windows Registry Editor Version 5.00`n[HKEY_CURRENT_USER\Software\Test]" | Set-Content -Path $script:TestSourceFile -Force

            # Cria segundo backup
            New-RegistryBackup -Path $TestDrive -Conta "TestAccount" -SourceFile $script:TestSourceFile -MaxBackups 10

            $backupFolder = Join-Path -Path $TestDrive -ChildPath "Backups\TestAccount"
            $backups = Get-ChildItem -Path $backupFolder -Filter "Backup_TestAccount_*.reg"
            $backups.Count | Should -Be 2
        }
    }

    Context "Quando excede limite de backups" {
        It "Deve manter apenas MaxBackups mais recentes" {
            # Cria 5 backups alterando o arquivo
            for ($i = 1; $i -le 5; $i++) {
                "Content $i" | Set-Content -Path $script:TestSourceFile -Force
                New-RegistryBackup -Path $TestDrive -Conta "TestAccount" -SourceFile $script:TestSourceFile -MaxBackups 3
                Start-Sleep -Milliseconds 1100
            }

            $backupFolder = Join-Path -Path $TestDrive -ChildPath "Backups\TestAccount"
            $backups = Get-ChildItem -Path $backupFolder -Filter "Backup_TestAccount_*.reg"
            $backups.Count | Should -Be 3
        }
    }

    AfterEach {
        if (Test-Path $script:TestSourceFile) {
            Remove-Item $script:TestSourceFile -Force -ErrorAction SilentlyContinue
        }
        $backupFolder = Join-Path -Path $TestDrive -ChildPath "Backups"
        if (Test-Path $backupFolder) {
            Remove-Item $backupFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
