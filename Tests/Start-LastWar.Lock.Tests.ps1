BeforeAll {
    # Import only the functions, without executing the complete script
    . "$PSScriptRoot\..\Start-LastWar.Functions.ps1"

    # Override script variables for testing
    $script:LOCK_FILE = Join-Path -Path $TestDrive -ChildPath ".lastwar.lock.test"
    $script:REGEDIT_ROOT = $TestDrive
}

Describe "Test-ScriptLock" {
    BeforeEach {
        # Clean lock file before each test
        if (Test-Path $script:LOCK_FILE) {
            Remove-Item $script:LOCK_FILE -Force
        }
    }

    Context "When there is no lock file" {
        It "Should return null" {
            $result = Test-ScriptLock
            $result | Should -BeNullOrEmpty
        }
    }

    Context "When there is a lock file with active process" {
        It "Should return IsLocked = true" {
            # Create lock file with current PID
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

    Context "When there is a lock file with non-existent process" {
        It "Should return IsOrphaned = true" {
            # Create lock file with non-existent PID (99999)
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

    Context "When there is a corrupted lock file" {
        It "Should return IsCorrupted = true" {
            # Create lock file with invalid content
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

    Context "When there is an orphaned lock" {
        It "Should remove the lock file" {
            # Create orphaned lock
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

    Context "When there is a corrupted lock" {
        It "Should remove the lock file" {
            "invalid json" | Set-Content -Path $script:LOCK_FILE -Force

            Remove-OrphanedLock

            Test-Path $script:LOCK_FILE | Should -Be $false
        }
    }

    Context "When there is an active lock" {
        It "Should not remove the lock file" {
            # Create lock with active process
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

    Context "When there is no lock" {
        It "Should not generate error" {
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

    Context "When creating new lock" {
        It "Should create lock file with correct data" {
            New-ScriptLock -AccountName "TestAccount"

            Test-Path $script:LOCK_FILE | Should -Be $true

            $lockContent = Get-Content $script:LOCK_FILE -Raw | ConvertFrom-Json
            $lockContent.AccountName | Should -Be "TestAccount"
            $lockContent.ProcessId | Should -Be $PID
            $lockContent.LockTime | Should -Not -BeNullOrEmpty
        }

        It "Should create lock with valid timestamp" {
            New-ScriptLock -AccountName "TestAccount"

            $lockContent = Get-Content $script:LOCK_FILE -Raw | ConvertFrom-Json

            # ConvertFrom-Json can deserialize ISO 8601 to DateTime automatically
            # Check if it's DateTime or valid ISO 8601 string
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

    Context "When there is an existing lock" {
        It "Should remove the lock file" {
            # Create lock
            New-ScriptLock -AccountName "TestAccount"

            Test-Path $script:LOCK_FILE | Should -Be $true

            Remove-ScriptLock

            Test-Path $script:LOCK_FILE | Should -Be $false
        }
    }

    Context "When there is no lock" {
        It "Should not generate error" {
            { Remove-ScriptLock } | Should -Not -Throw
        }
    }

    AfterEach {
        if (Test-Path $script:LOCK_FILE) {
            Remove-Item $script:LOCK_FILE -Force -ErrorAction SilentlyContinue
        }
    }
}
