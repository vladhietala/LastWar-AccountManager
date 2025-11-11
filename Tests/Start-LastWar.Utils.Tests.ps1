BeforeAll {
    # Import only the functions, without executing the complete script
    . "$PSScriptRoot\..\Start-LastWar.Functions.ps1"
}

Describe "Test-Administrator" {
    Context "Privilege verification" {
        It "Should return a boolean value" {
            $result = Test-Administrator
            $result | Should -BeOfType [bool]
        }

        It "Should return true or false without error" {
            { Test-Administrator } | Should -Not -Throw
        }
    }
}

Describe "Get-ScriptFullPath" {
    Context "When PSCommandPath is available" {
        It "Should return absolute path" {
            $result = Get-ScriptFullPath
            $result | Should -Not -BeNullOrEmpty
            [System.IO.Path]::IsPathRooted($result) | Should -Be $true
        }

        It "Should end with .ps1" {
            $result = Get-ScriptFullPath
            $result | Should -Match '\.ps1$'
        }
    }
}

Describe "Build-ElevatedProcessArguments" {
    Context "Basic arguments" {
        It "Should include mandatory parameters" {
            $argList = Build-ElevatedProcessArguments `
                -ScriptPath "C:\Test\Script.ps1" `
                -Account "TestAccount" `
                -MaxBackups 10 `
                -BoundParameters @{}

            $argList | Should -Contain "-NoProfile"
            $argList | Should -Contain "-ExecutionPolicy"
            $argList | Should -Contain "Bypass"
            # -File comes with the path: '-File "C:\Test\Script.ps1"'
            $argList | Should -Contain '-File "C:\Test\Script.ps1"'
            # -Account comes with the value: '-Account "TestAccount"'
            $argList | Should -Contain '-Account "TestAccount"'
            $argList | Should -Contain "-MaxBackups"
            $argList | Should -Contain 10
        }

        It "Should include script path with quotes in correct format" {
            $argList = Build-ElevatedProcessArguments `
                -ScriptPath "C:\Test\Script.ps1" `
                -Account "TestAccount" `
                -MaxBackups 10 `
                -BoundParameters @{}

            # The function uses -f format to create: '-File "path"'
            $argList | Should -Contain '-File "C:\Test\Script.ps1"'
        }

        It "Should include account with quotes in correct format" {
            $argList = Build-ElevatedProcessArguments `
                -ScriptPath "C:\Test\Script.ps1" `
                -Account "TestAccount" `
                -MaxBackups 10 `
                -BoundParameters @{}

            # The function uses -f format to create: '-Account "name"'
            $argList | Should -Contain '-Account "TestAccount"'
        }
    }

    Context "With Verbose parameter" {
        It "Should include -Verbose when present" {
            $argList = Build-ElevatedProcessArguments `
                -ScriptPath "C:\Test\Script.ps1" `
                -Account "TestAccount" `
                -MaxBackups 10 `
                -BoundParameters @{ Verbose = $true }

            $argList | Should -Contain "-Verbose"
        }

        It "Should include -NoExit when Verbose present (to keep window open)" {
            $argList = Build-ElevatedProcessArguments `
                -ScriptPath "C:\Test\Script.ps1" `
                -Account "TestAccount" `
                -MaxBackups 10 `
                -BoundParameters @{ Verbose = $true }

            $argList | Should -Contain "-NoExit"
        }

        It "Should not include -Verbose when absent" {
            $argList = Build-ElevatedProcessArguments `
                -ScriptPath "C:\Test\Script.ps1" `
                -Account "TestAccount" `
                -MaxBackups 10 `
                -BoundParameters @{}

            $argList | Should -Not -Contain "-Verbose"
        }

        It "Should not include -NoExit when Verbose absent" {
            $argList = Build-ElevatedProcessArguments `
                -ScriptPath "C:\Test\Script.ps1" `
                -Account "TestAccount" `
                -MaxBackups 10 `
                -BoundParameters @{}

            $argList | Should -Not -Contain "-NoExit"
        }
    }
}

Describe "Initialize-Workspace" {
    BeforeEach {
        $script:REGEDIT_ROOT = $TestDrive
        $script:TestAccountsFolder = Join-Path -Path $TestDrive -ChildPath "Accounts"
        New-Item -ItemType Directory -Path $script:TestAccountsFolder -Force | Out-Null
    }

    Context "When account file exists" {
        It "Should return file path" {
            $testFile = Join-Path -Path $script:TestAccountsFolder -ChildPath "TestAccount.reg"
            "Test content" | Set-Content -Path $testFile -Force

            $result = Initialize-Workspace -Account "TestAccount"

            $result | Should -Be $testFile
            Test-Path $result | Should -Be $true
        }
    }

    Context "When account file does not exist" {
        It "Should throw exception" {
            { Initialize-Workspace -Account "NonExistent" } | Should -Throw "*not found*"
        }
    }

    AfterEach {
        if (Test-Path $script:TestAccountsFolder) {
            Remove-Item $script:TestAccountsFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Show-ErrorMessage" {
    Context "Error formatting" {
        It "Should not throw exception when showing error" {
            try {
                throw "Test error"
            }
            catch {
                { Show-ErrorMessage -ErrorRecord $_ } | Should -Not -Throw
            }
        }

        It "Should accept custom title" {
            try {
                throw "Test error"
            }
            catch {
                { Show-ErrorMessage -ErrorRecord $_ -Title "CUSTOM ERROR" } | Should -Not -Throw
            }
        }
    }
}
