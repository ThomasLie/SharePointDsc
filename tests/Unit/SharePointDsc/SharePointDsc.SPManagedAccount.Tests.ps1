[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
param
(
    [Parameter()]
    [string]
    $SharePointCmdletModule = (Join-Path -Path $PSScriptRoot `
            -ChildPath "..\Stubs\SharePoint\15.0.4805.1000\Microsoft.SharePoint.PowerShell.psm1" `
            -Resolve)
)

$script:DSCModuleName = 'SharePointDsc'
$script:DSCResourceName = 'SPManagedAccount'
$script:DSCResourceFullName = 'MSFT_' + $script:DSCResourceName

function Invoke-TestSetup
{
    try
    {
        Import-Module -Name DscResource.Test -Force

        Import-Module -Name (Join-Path -Path $PSScriptRoot `
                -ChildPath "..\UnitTestHelper.psm1" `
                -Resolve)

        $Global:SPDscHelper = New-SPDscUnitTestHelper -SharePointStubModule $SharePointCmdletModule `
            -DscResource $script:DSCResourceName
    }
    catch [System.IO.FileNotFoundException]
    {
        throw 'DscResource.Test module dependency not found. Please run ".\build.ps1 -Tasks build" first.'
    }

    $script:testEnvironment = Initialize-TestEnvironment `
        -DSCModuleName $script:DSCModuleName `
        -DSCResourceName $script:DSCResourceFullName `
        -ResourceType 'Mof' `
        -TestType 'Unit'
}

function Invoke-TestCleanup
{
    Restore-TestEnvironment -TestEnvironment $script:testEnvironment
}

Invoke-TestSetup

try
{
    InModuleScope -ModuleName $script:DSCResourceFullName -ScriptBlock {
        Describe -Name $Global:SPDscHelper.DescribeHeader -Fixture {
            BeforeAll {
                Invoke-Command -Scriptblock $Global:SPDscHelper.InitializeScript -NoNewScope

                # Initialize tests
                $mockPassword = ConvertTo-SecureString -String "password" -AsPlainText -Force
                $mockCredential = New-Object -TypeName System.Management.Automation.PSCredential `
                    -ArgumentList @("username", $mockPassword)

                # Mocks for all contexts
                Mock -CommandName New-SPManagedAccount -MockWith { }
                Mock -CommandName Set-SPManagedAccount -MockWith { }
                Mock -CommandName Remove-SPManagedAccount -MockWith { }

                function Add-SPDscEvent
                {
                    param (
                        [Parameter(Mandatory = $true)]
                        [System.String]
                        $Message,

                        [Parameter(Mandatory = $true)]
                        [System.String]
                        $Source,

                        [Parameter()]
                        [ValidateSet('Error', 'Information', 'FailureAudit', 'SuccessAudit', 'Warning')]
                        [System.String]
                        $EntryType,

                        [Parameter()]
                        [System.UInt32]
                        $EventID
                    )
                }
            }

            # Test contexts
            Context -Name "The specified managed account does not exist in the farm and it should" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Account           = $mockCredential
                        EmailNotification = 7
                        PreExpireDays     = 7
                        Schedule          = ""
                        Ensure            = "Present"
                        AccountName       = $mockCredential.Username
                    }

                    Mock -CommandName Get-SPManagedAccount -MockWith { return $null }
                }

                It "Should return null from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Absent"
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should call the new and set methods from the set function" {
                    Set-TargetResource @testParams
                    Assert-MockCalled New-SPManagedAccount
                    Assert-MockCalled Set-SPManagedAccount
                }
            }

            Context -Name "The specified managed account exists and it should but has an incorrect schedule" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Account           = $mockCredential
                        EmailNotification = 7
                        PreExpireDays     = 7
                        Schedule          = ""
                        Ensure            = "Present"
                        AccountName       = $mockCredential.Username
                    }

                    Mock -CommandName Get-SPManagedAccount -MockWith {
                        return @{
                            Username                 = $testParams.AccountName
                            DaysBeforeChangeToEmail  = $testParams.EmailNotification
                            DaysBeforeExpiryToChange = $testParams.PreExpireDays
                            ChangeSchedule           = "wrong schedule"
                        }
                    }
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should call the set methods from the set function" {
                    Set-TargetResource @testParams
                    Assert-MockCalled Set-SPManagedAccount
                }
            }

            Context -Name "The specified managed account exists and it should but has incorrect notifcation settings" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Account           = $mockCredential
                        EmailNotification = 7
                        PreExpireDays     = 7
                        Schedule          = ""
                        Ensure            = "Present"
                        AccountName       = $mockCredential.Username
                    }

                    Mock -CommandName Get-SPManagedAccount -MockWith {
                        return @{
                            Username                 = $testParams.AccountName
                            DaysBeforeChangeToEmail  = 0
                            DaysBeforeExpiryToChange = 0
                            ChangeSchedule           = $testParams.Schedule
                        }
                    }
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }
            }

            Context -Name "The specified managed account exists and it should and is also configured correctly" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Account           = $mockCredential
                        EmailNotification = 7
                        PreExpireDays     = 7
                        Schedule          = ""
                        Ensure            = "Present"
                        AccountName       = $mockCredential.Username
                    }

                    Mock -CommandName Get-SPManagedAccount -MockWith {
                        return @{
                            Username                 = $testParams.AccountName
                            DaysBeforeChangeToEmail  = $testParams.EmailNotification
                            DaysBeforeExpiryToChange = $testParams.PreExpireDays
                            ChangeSchedule           = $testParams.Schedule
                        }
                    }
                }

                It "Should return the current values from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Present"
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }
            }

            Context -Name "The specified account should exist but the account property has not been specified" -Fixture {
                BeforeAll {
                    $testParams = @{
                        EmailNotification = 7
                        PreExpireDays     = 7
                        Schedule          = ""
                        Ensure            = "Present"
                        AccountName       = "username"
                    }

                    Mock -CommandName Get-SPManagedAccount -MockWith {
                        return @{
                            Username                 = $testParams.AccountName
                            DaysBeforeChangeToEmail  = $testParams.EmailNotification
                            DaysBeforeExpiryToChange = $testParams.PreExpireDays
                            ChangeSchedule           = $testParams.Schedule
                        }
                    }
                }

                It "Should throw an exception in the set method" {
                    { Set-TargetResource @testParams } | Should -Throw
                }
            }

            Context -Name "The specified account exists but it should not" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Ensure      = "Absent"
                        AccountName = "username"
                    }

                    Mock -CommandName Get-SPManagedAccount -MockWith {
                        return @{
                            Username                 = $testParams.AccountName
                            DaysBeforeChangeToEmail  = $testParams.EmailNotification
                            DaysBeforeExpiryToChange = $testParams.PreExpireDays
                            ChangeSchedule           = $testParams.Schedule
                        }
                    }
                }

                It "Should return present from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Present"
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should call the remove cmdlet from the set method" {
                    Set-TargetResource @testParams
                    Assert-MockCalled Remove-SPManagedAccount
                }
            }

            Context -Name "The specified account does not exist and it should not" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Ensure      = "Absent"
                        AccountName = "username"
                    }

                    Mock -CommandName Get-SPManagedAccount -MockWith {
                        return $null
                    }
                }

                It "Should return absent from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Absent"
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }
            }

            Context -Name "Running ReverseDsc Export" -Fixture {
                BeforeAll {
                    Import-Module (Join-Path -Path (Split-Path -Path (Get-Module SharePointDsc -ListAvailable).Path -Parent) -ChildPath "Modules\SharePointDSC.Reverse\SharePointDSC.Reverse.psm1")

                    Mock -CommandName Write-Host -MockWith { }

                    Mock -CommandName Get-TargetResource -MockWith {
                        return @{
                            AccountName       = $mockCredential.UserName
                            EmailNotification = 10
                            PreExpireDays     = 5
                            Schedule          = "monthly between 7 02:00:00 and 7 03:00:00"
                            Account           = $mockCredential
                            Ensure            = "Present"
                        }
                    }

                    Mock -CommandName Get-SPManagedAccount -MockWith {
                        $spManagedAccounts = @(
                            [PSCustomObject]@{
                                UserName                 = $mockCredential.UserName
                                ChangeSchedule           = "monthly between 7 02:00:00 and 7 03:00:00"
                                DaysBeforeExpiryToChange = 5
                                DaysBeforeChangeToEmail  = 10
                            }
                        )
                        return $spManagedAccounts
                    }

                    if ($null -eq (Get-Variable -Name 'spFarmAccount' -ErrorAction SilentlyContinue))
                    {
                        $mockPassword = ConvertTo-SecureString -String "password" -AsPlainText -Force
                        $Global:spFarmAccount = New-Object -TypeName System.Management.Automation.PSCredential ("contoso\spfarm", $mockPassword)
                    }

                    $result = @'
        SPManagedAccount [0-9A-Fa-f]{8}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{12}
        {
            Account              = \$Credsusername;
            AccountName          = \$Credsusername.UserName;
            EmailNotification    = 10;
            Ensure               = "Present";
            PreExpireDays        = 5;
            PsDscRunAsCredential = \$Credsspfarm;
            Schedule             = "monthly between 7 02:00:00 and 7 03:00:00";
        }

'@
                }

                It "Should return valid DSC block from the Export method" {
                    Export-TargetResource | Should -Match $result
                }
            }
        }
    }
}
finally
{
    Invoke-TestCleanup
}
