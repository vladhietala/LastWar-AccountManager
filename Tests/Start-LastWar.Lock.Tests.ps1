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

Describe "Assert-NoExistingLock" {
    BeforeEach {
        if (Test-Path $script:LOCK_FILE) {
            Remove-Item $script:LOCK_FILE -Force
        }
        # Use shorter timeouts for faster testing
        $script:LOCK_WAIT_TIMEOUT_SECONDS = 2
        $script:LOCK_RETRY_INTERVAL_SECONDS = 0.3
    }

    Context "When there is no lock" {
        It "Should not throw and continue immediately" {
            { Assert-NoExistingLock } | Should -Not -Throw
        }
    }

    Context "When lock is released during wait period" {
        It "Should wait and continue after lock is released" {
            # Create lock with current PID
            $lockData = @{
                AccountName = "TestAccount"
                ProcessId = $PID
                LockTime = (Get-Date).ToString("o")
            } | ConvertTo-Json
            $lockData | Set-Content -Path $script:LOCK_FILE -Force

            # Start background job to remove lock after 0.8 seconds
            $job = Start-Job -ScriptBlock {
                param($lockFile)
                Start-Sleep -Seconds 0.8
                Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue
            } -ArgumentList $script:LOCK_FILE

            $start = Get-Date

            # Should wait and succeed
            { Assert-NoExistingLock } | Should -Not -Throw

            $elapsed = ((Get-Date) - $start).TotalSeconds

            # Should have waited at least 0.8 seconds
            $elapsed | Should -BeGreaterThan 0.7

            # Cleanup
            $job | Remove-Job -Force -ErrorAction SilentlyContinue
        }
    }

    Context "When lock remains active after timeout" {
        It "Should exit process after timeout" {
            # Create lock with current PID
            $lockData = @{
                AccountName = "TestAccount"
                ProcessId = $PID
                LockTime = (Get-Date).ToString("o")
            } | ConvertTo-Json
            $lockData | Set-Content -Path $script:LOCK_FILE -Force

            # Run in separate process to capture exit code
            $testScript = @"
                Import-Module '$PSScriptRoot\..\Start-LastWar.Functions.ps1' -Force
                `$script:LOCK_FILE = '$($script:LOCK_FILE)'
                `$script:LOCK_WAIT_TIMEOUT_SECONDS = 1
                `$script:ERROR_MESSAGE_DISPLAY_SECONDS = 0.1
                Assert-NoExistingLock
                exit 0
"@
            $result = pwsh.exe -NoProfile -Command $testScript

            # Should have exited with code 1
            $LASTEXITCODE | Should -Be 1
        }
    }

    AfterEach {
        if (Test-Path $script:LOCK_FILE) {
            Remove-Item $script:LOCK_FILE -Force -ErrorAction SilentlyContinue
        }
    }
}
