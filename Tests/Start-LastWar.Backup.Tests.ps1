BeforeAll {
    # Import only the functions, without executing the complete script
    . "$PSScriptRoot\..\Start-LastWar.Functions.ps1"

    # Override script variables for testing
    $script:REGEDIT_ROOT = $TestDrive
}

Describe "Test-BackupNeeded" {
    BeforeEach {
        $script:TestBackupFolder = Join-Path -Path $TestDrive -ChildPath "Backups\TestAccount"
        New-Item -ItemType Directory -Path $script:TestBackupFolder -Force | Out-Null

        $script:TestSourceFile = Join-Path -Path $TestDrive -ChildPath "source.reg"
        "Test content" | Set-Content -Path $script:TestSourceFile -Force
    }

    Context "When there are no existing backups" {
        It "Should return true" {
            $result = Test-BackupNeeded -SourceFile $script:TestSourceFile -BackupFolder $script:TestBackupFolder -Account "TestAccount"
            $result | Should -Be $true
        }
    }

    Context "When there is an identical backup" {
        It "Should return false" {
            # Create identical backup
            $backupFile = Join-Path -Path $script:TestBackupFolder -ChildPath "Backup_TestAccount_20250101_120000.reg"
            Copy-Item -Path $script:TestSourceFile -Destination $backupFile -Force

            $result = Test-BackupNeeded -SourceFile $script:TestSourceFile -BackupFolder $script:TestBackupFolder -Account "TestAccount"
            $result | Should -Be $false
        }
    }

    Context "When there is a different backup" {
        It "Should return true" {
            # Create backup with different content
            $backupFile = Join-Path -Path $script:TestBackupFolder -ChildPath "Backup_TestAccount_20250101_120000.reg"
            "Different content" | Set-Content -Path $backupFile -Force

            $result = Test-BackupNeeded -SourceFile $script:TestSourceFile -BackupFolder $script:TestBackupFolder -Account "TestAccount"
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

    Context "When there are more backups than the limit" {
        It "Should keep only the N most recent" {
            # Create 5 backups with different timestamps
            for ($i = 1; $i -le 5; $i++) {
                $backupFile = Join-Path -Path $script:TestBackupFolder -ChildPath "Backup_TestAccount_2025010$i`_120000.reg"
                "Backup $i" | Set-Content -Path $backupFile -Force
                Start-Sleep -Milliseconds 100
            }

            # Keep only 3
            Remove-OldBackups -BackupFolder $script:TestBackupFolder -Account "TestAccount" -MaxBackups 3

            $remainingBackups = Get-ChildItem -Path $script:TestBackupFolder -Filter "Backup_TestAccount_*.reg"
            $remainingBackups.Count | Should -Be 3
        }

        It "Should remove the oldest backups" {
            # Create backups with ordered timestamps
            $timestamps = @("20250101_120000", "20250102_120000", "20250103_120000", "20250104_120000", "20250105_120000")
            foreach ($ts in $timestamps) {
                $backupFile = Join-Path -Path $script:TestBackupFolder -ChildPath "Backup_TestAccount_$ts.reg"
                "Backup" | Set-Content -Path $backupFile -Force
                Start-Sleep -Milliseconds 100
            }

            Remove-OldBackups -BackupFolder $script:TestBackupFolder -Account "TestAccount" -MaxBackups 2

            $remainingBackups = Get-ChildItem -Path $script:TestBackupFolder -Filter "Backup_TestAccount_*.reg" | Sort-Object LastWriteTime -Descending
            $remainingBackups.Count | Should -Be 2
            # The 2 most recent should be the last ones created
            $remainingBackups[0].Name | Should -BeLike "*20250105*"
            $remainingBackups[1].Name | Should -BeLike "*20250104*"
        }
    }

    Context "When there are fewer backups than the limit" {
        It "Should not remove any backup" {
            # Create only 2 backups
            for ($i = 1; $i -le 2; $i++) {
                $backupFile = Join-Path -Path $script:TestBackupFolder -ChildPath "Backup_TestAccount_2025010$i`_120000.reg"
                "Backup $i" | Set-Content -Path $backupFile -Force
            }

            Remove-OldBackups -BackupFolder $script:TestBackupFolder -Account "TestAccount" -MaxBackups 5

            $remainingBackups = Get-ChildItem -Path $script:TestBackupFolder -Filter "Backup_TestAccount_*.reg"
            $remainingBackups.Count | Should -Be 2
        }
    }

    Context "When there are no backups" {
        It "Should not generate error" {
            { Remove-OldBackups -BackupFolder $script:TestBackupFolder -Account "TestAccount" -MaxBackups 3 } | Should -Not -Throw
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

    Context "When creating first backup" {
        It "Should create backup file" {
            New-RegistryBackup -Path $TestDrive -Account "TestAccount" -SourceFile $script:TestSourceFile -MaxBackups 10

            $backupFolder = Join-Path -Path $TestDrive -ChildPath "Backups\TestAccount"
            Test-Path $backupFolder | Should -Be $true

            $backups = Get-ChildItem -Path $backupFolder -Filter "Backup_TestAccount_*.reg"
            $backups.Count | Should -Be 1
        }

        It "Should name backup with correct timestamp" {
            New-RegistryBackup -Path $TestDrive -Account "TestAccount" -SourceFile $script:TestSourceFile -MaxBackups 10

            $backupFolder = Join-Path -Path $TestDrive -ChildPath "Backups\TestAccount"
            $backup = Get-ChildItem -Path $backupFolder -Filter "Backup_TestAccount_*.reg" | Select-Object -First 1

            # Format: Backup_TestAccount_YYYYMMDD_HHMMSS.reg
            $backup.Name | Should -Match "^Backup_TestAccount_\d{8}_\d{6}\.reg$"
        }
    }

    Context "When backup is not necessary" {
        It "Should not create new backup" {
            # Create first backup
            New-RegistryBackup -Path $TestDrive -Account "TestAccount" -SourceFile $script:TestSourceFile -MaxBackups 10

            # Try to create second backup without modifying the file
            New-RegistryBackup -Path $TestDrive -Account "TestAccount" -SourceFile $script:TestSourceFile -MaxBackups 10

            $backupFolder = Join-Path -Path $TestDrive -ChildPath "Backups\TestAccount"
            $backups = Get-ChildItem -Path $backupFolder -Filter "Backup_TestAccount_*.reg"
            $backups.Count | Should -Be 1
        }
    }

    Context "When file changes" {
        It "Should create new backup" {
            # Create first backup
            New-RegistryBackup -Path $TestDrive -Account "TestAccount" -SourceFile $script:TestSourceFile -MaxBackups 10

            Start-Sleep -Milliseconds 1100  # Ensure different timestamp

            # Modify file
            "Windows Registry Editor Version 5.00`n[HKEY_CURRENT_USER\Software\Test]" | Set-Content -Path $script:TestSourceFile -Force

            # Create second backup
            New-RegistryBackup -Path $TestDrive -Account "TestAccount" -SourceFile $script:TestSourceFile -MaxBackups 10

            $backupFolder = Join-Path -Path $TestDrive -ChildPath "Backups\TestAccount"
            $backups = Get-ChildItem -Path $backupFolder -Filter "Backup_TestAccount_*.reg"
            $backups.Count | Should -Be 2
        }
    }

    Context "When exceeding backup limit" {
        It "Should keep only most recent MaxBackups" {
            # Create 5 backups by modifying the file
            for ($i = 1; $i -le 5; $i++) {
                "Content $i" | Set-Content -Path $script:TestSourceFile -Force
                New-RegistryBackup -Path $TestDrive -Account "TestAccount" -SourceFile $script:TestSourceFile -MaxBackups 3
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
