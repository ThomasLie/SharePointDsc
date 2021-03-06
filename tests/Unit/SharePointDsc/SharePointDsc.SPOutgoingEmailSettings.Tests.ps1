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
$script:DSCResourceName = 'SPOutgoingEmailSettings'
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
            Context -Name "The Web Application isn't available" -Fixture {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl      = "http://sharepoint.contoso.com"
                        SMTPServer     = "smtp.contoso.com"
                        FromAddress    = "from@email.com"
                        ReplyToAddress = "reply@email.com"
                        CharacterSet   = "65001"
                    }

                    Mock -CommandName Get-SPWebApplication -MockWith {
                        return $null
                    }
                }

                It "Should return null from the get method" {
                    (Get-TargetResource @testParams).WebAppUrl | Should -BeNullOrEmpty
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should throw an exception in the set method" {
                    { Set-TargetResource @testParams } | Should -Throw
                }
            }

            Context -Name "The web application exists and the properties match" -Fixture {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl      = "http://sharepoint.contoso.com"
                        SMTPServer     = "smtp.contoso.com"
                        FromAddress    = "from@email.com"
                        ReplyToAddress = "reply@email.com"
                        CharacterSet   = "65001"
                    }

                    Mock -CommandName Get-SPWebapplication -MockWith {
                        return @{
                            Url                         = "http://sharepoint.contoso.com"
                            OutboundMailServiceInstance = @{
                                Server = @{
                                    Name = "smtp.contoso.com"
                                }
                            }
                            OutboundMailSenderAddress   = "from@email.com"
                            OutboundMailReplyToAddress  = "reply@email.com"
                            OutboundMailCodePage        = "65001"
                        }
                    }
                }

                It "Should return web app properties from the get method" {
                    (Get-TargetResource @testParams).WebAppUrl | Should -Be $testParams.WebAppUrl
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }
            }

            Context -Name "The web application exists and the properties don't match" -Fixture {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl      = "http://sharepoint.contoso.com"
                        SMTPServer     = "smtp.contoso.com"
                        FromAddress    = "from@email.com"
                        ReplyToAddress = "reply@email.com"
                        CharacterSet   = "65001"
                    }

                    Mock -CommandName Get-SPWebapplication -MockWith {
                        $result = @{
                            Url                         = "http://sharepoint.contoso.com"
                            OutboundMailServiceInstance = @{
                                Server = @{
                                    Name = "smtp2.contoso.com"
                                }
                            }
                            OutboundMailSenderAddress   = "from@email.com"
                            OutboundMailReplyToAddress  = "reply@email.com"
                            OutboundMailCodePage        = "65001"
                        }
                        $result = $result | Add-Member -MemberType ScriptMethod `
                            -Name UpdateMailSettings `
                            -Value {
                            param(
                                [string]
                                $SMTPServer,

                                [string]
                                $FromAddress,

                                [string]
                                $ReplyToAddress,
                                [string]
                                $CharacterSet
                            )
                            $Global:SPDscUpdateMailSettingsCalled = $true;
                        } -PassThru
                        return $result
                    }
                }

                It "Should return false from the get method" {
                    (Get-TargetResource @testParams).WebAppUrl | Should -Be $testParams.WebAppUrl
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should call the new and set methods from the set function" {
                    $Global:SPDscUpdateMailSettingsCalled = $false
                    Set-TargetResource @testParams
                    $Global:SPDscUpdateMailSettingsCalled | Should -Be $true
                }
            }

            if ($Global:SPDscHelper.CurrentStubBuildNumber.Major -eq 15)
            {
                Context -Name "UseTLS is using in SharePoint 2013" -Fixture {
                    BeforeAll {
                        $testParams = @{
                            WebAppUrl      = "http://sharepoint.contoso.com"
                            SMTPServer     = "smtp.contoso.com"
                            FromAddress    = "from@email.com"
                            ReplyToAddress = "reply@email.com"
                            UseTLS         = $true
                            CharacterSet   = "65001"
                        }
                    }

                    It "Should throw an exception in the get method" {
                        { Get-TargetResource @testParams } | Should -Throw "UseTLS is only supported in SharePoint 2016 and SharePoint 2019."
                    }

                    It "Should throw an exception in the test method" {
                        { Test-TargetResource @testParams } | Should -Throw "UseTLS is only supported in SharePoint 2016 and SharePoint 2019."
                    }

                    It "Should throw an exception in the set method" {
                        { Set-TargetResource @testParams } | Should -Throw "UseTLS is only supported in SharePoint 2016 and SharePoint 2019."
                    }
                }

                Context -Name "SMTPPort is using in SharePoint 2013" -Fixture {
                    BeforeAll {
                        $testParams = @{
                            WebAppUrl      = "http://sharepoint.contoso.com"
                            SMTPServer     = "smtp.contoso.com"
                            FromAddress    = "from@email.com"
                            ReplyToAddress = "reply@email.com"
                            SMTPPort       = 25
                            CharacterSet   = "65001"
                        }
                    }

                    It "Should throw an exception in the get method" {
                        { Get-TargetResource @testParams } | Should -Throw "SMTPPort is only supported in SharePoint 2016 and SharePoint 2019."
                    }

                    It "Should throw an exception in the test method" {
                        { Test-TargetResource @testParams } | Should -Throw "SMTPPort is only supported in SharePoint 2016 and SharePoint 2019."
                    }

                    It "Should throw an exception in the set method" {
                        { Set-TargetResource @testParams } | Should -Throw "SMTPPort is only supported in SharePoint 2016 and SharePoint 2019."
                    }
                }
            }

            if ($Global:SPDscHelper.CurrentStubBuildNumber.Major -eq 16)
            {
                Context -Name "The web application exists and the properties match - SharePoint 2016/2019" -Fixture {
                    BeforeAll {
                        $testParams = @{
                            WebAppUrl      = "http://sharepoint.contoso.com"
                            SMTPServer     = "smtp.contoso.com"
                            FromAddress    = "from@email.com"
                            CharacterSet   = "65001"
                            ReplyToAddress = "reply@email.com"
                            UseTLS         = $false
                            SMTPPort       = 25
                        }

                        Mock -CommandName Get-SPWebapplication -MockWith {
                            return @{
                                Url                         = "http://sharepoint.contoso.com"
                                OutboundMailServiceInstance = @{
                                    Server = @{
                                        Name = "smtp.contoso.com"
                                    }
                                }
                                OutboundMailSenderAddress   = "from@email.com"
                                OutboundMailReplyToAddress  = "reply@email.com"
                                OutboundMailCodePage        = "65001"
                                OutboundMailEnableSsl       = $false
                                OutboundMailPort            = 25
                            }
                        }
                    }

                    It "Should return web app properties from the get method" {
                        (Get-TargetResource @testParams).WebAppUrl | Should -Be $testParams.WebAppUrl
                    }

                    It "Should return true from the test method" {
                        Test-TargetResource @testParams | Should -Be $true
                    }
                }

                Context -Name "The web application exists and the properties don't match - SharePoint 2016/2019" -Fixture {
                    BeforeAll {
                        $testParams = @{
                            WebAppUrl      = "http://sharepoint.contoso.com"
                            SMTPServer     = "smtp.contoso.com"
                            FromAddress    = "from@email.com"
                            ReplyToAddress = "reply@email.com"
                            CharacterSet   = "65001"
                            UseTLS         = $true
                            SMTPPort       = 25
                        }

                        Mock -CommandName Get-SPWebapplication -MockWith {
                            $result = @{
                                Url                         = "http://sharepoint.contoso.com"
                                OutboundMailServiceInstance = @{
                                    Server = @{
                                        Name = "smtp.contoso.com"
                                    }
                                }
                                OutboundMailSenderAddress   = "from@email.com"
                                OutboundMailReplyToAddress  = "reply@email.com"
                                OutboundMailCodePage        = "65001"
                                OutboundMailEnableSsl       = $false
                                OutboundMailPort            = 25
                            }
                            $result = $result | Add-Member -MemberType ScriptMethod `
                                -Name UpdateMailSettings `
                                -Value {
                                param(
                                    [string]
                                    $SMTPServer,

                                    [string]
                                    $FromAddress,

                                    [string]
                                    $ReplyToAddress,

                                    [string]
                                    $CharacterSet,

                                    [bool]
                                    $EnableSsl,

                                    [string]
                                    $Port
                                )
                                $Global:SPDscUpdateMailSettingsCalled = $true;
                            } -PassThru
                            return $result
                        }
                    }

                    It "Should return false from the get method" {
                        (Get-TargetResource @testParams).SMTPPort | Should -Be 25
                        (Get-TargetResource @testParams).UseTLS | Should -Be $false
                    }

                    It "Should return false from the test method" {
                        Test-TargetResource @testParams | Should -Be $false
                    }

                    It "Should call the new and set methods from the set function" {
                        $Global:SPDscUpdateMailSettingsCalled = $false
                        Set-TargetResource @testParams
                        $Global:SPDscUpdateMailSettingsCalled | Should -Be $true
                    }
                }
            }

            Context -Name "Running ReverseDsc Export" -Fixture {
                BeforeAll {
                    Import-Module (Join-Path -Path (Split-Path -Path (Get-Module SharePointDsc -ListAvailable).Path -Parent) -ChildPath "Modules\SharePointDSC.Reverse\SharePointDSC.Reverse.psm1")

                    Mock -CommandName Write-Host -MockWith { }

                    Mock -CommandName Get-TargetResource -MockWith {
                        return @{
                            WebAppUrl      = "http://sharepoint1:2013"
                            SMTPServer     = "smtp.contoso.com"
                            FromAddress    = "sharepoint@contoso.com"
                            ReplyToAddress = "noreply@contoso.com"
                            CharacterSet   = "65001"
                            UseTLS         = $false
                            SMTPPort       = 25
                        }
                    }

                    if ($null -eq (Get-Variable -Name 'spFarmAccount' -ErrorAction SilentlyContinue))
                    {
                        $mockPassword = ConvertTo-SecureString -String "password" -AsPlainText -Force
                        $Global:spFarmAccount = New-Object -TypeName System.Management.Automation.PSCredential ("contoso\spfarm", $mockPassword)
                    }

                    $result = @'
        SPOutgoingEmailSettings [0-9A-Fa-f]{8}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{12}
        {
            CharacterSet         = "65001";
            FromAddress          = "sharepoint\@contoso.com";
            PsDscRunAsCredential = \$Credsspfarm;
            ReplyToAddress       = "noreply\@contoso.com";
            SMTPPort             = 25;
            SMTPServer           = "smtp.contoso.com";
            UseTLS               = \$False;
            WebAppUrl            = "http://sharepoint1:2013";
        }

'@
                }

                It "Should return valid DSC block from the Export method" {
                    Export-TargetResource -WebAppUrl "http://sharepoint1:2013" | Should -Match $result
                }
            }
        }
    }
}
finally
{
    Invoke-TestCleanup
}
