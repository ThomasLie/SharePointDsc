[CmdletBinding()]
param
(
    [Parameter()]
    [string]
    $SharePointCmdletModule = (Join-Path -Path $PSScriptRoot `
            -ChildPath "..\Stubs\SharePoint\15.0.4805.1000\Microsoft.SharePoint.PowerShell.psm1" `
            -Resolve)
)

$script:DSCModuleName = 'SharePointDsc'
$script:DSCResourceName = 'SPDesignerSettings'
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
    Describe -Name $Global:SPDscHelper.DescribeHeader -Fixture {
        InModuleScope -ModuleName $Global:SPDscHelper.ModuleName -ScriptBlock {
            Invoke-Command -ScriptBlock $Global:SPDscHelper.InitializeScript -NoNewScope

            # Mocks for all contexts
            Mock -CommandName Get-SPFarm -MockWith {
                return @{ }
            }

            # Test contexts
            Context -Name "The server is not part of SharePoint farm" -Fixture {
                $testParams = @{
                    WebAppUrl                              = "https://intranet.sharepoint.contoso.com"
                    SettingsScope                          = "WebApplication"
                    AllowSharePointDesigner                = $false
                    AllowDetachPagesFromDefinition         = $false
                    AllowCustomiseMasterPage               = $false
                    AllowManageSiteURLStructure            = $false
                    AllowCreateDeclarativeWorkflow         = $false
                    AllowSavePublishDeclarativeWorkflow    = $false
                    AllowSaveDeclarativeWorkflowAsTemplate = $false
                }

                Mock -CommandName Get-SPFarm -MockWith {
                    throw "Unable to detect local farm"
                }

                It "Should return null from the get method" {
                    (Get-TargetResource @testParams).AllowSharePointDesigner | Should Be $null
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should Be $false
                }

                It "Should throw an exception in the set method to say there is no local farm" {
                    { Set-TargetResource @testParams } | Should throw "No local SharePoint farm was detected"
                }
            }

            Context -Name "The server is in a farm, target web application and the incorrect settings have been applied" -Fixture {
                $testParams = @{
                    WebAppUrl                              = "https://intranet.sharepoint.contoso.com"
                    SettingsScope                          = "WebApplication"
                    AllowSharePointDesigner                = $false
                    AllowDetachPagesFromDefinition         = $false
                    AllowCustomiseMasterPage               = $false
                    AllowManageSiteURLStructure            = $false
                    AllowCreateDeclarativeWorkflow         = $false
                    AllowSavePublishDeclarativeWorkflow    = $false
                    AllowSaveDeclarativeWorkflowAsTemplate = $false
                }

                Mock -CommandName Get-SPDesignerSettings -MockWith { return @{
                        AllowDesigner                          = $true
                        AllowRevertFromTemplate                = $true
                        AllowMasterPageEditing                 = $true
                        ShowURLStructure                       = $true
                        AllowCreateDeclarativeWorkflow         = $true
                        AllowSavePublishDeclarativeWorkflow    = $true
                        AllowSaveDeclarativeWorkflowAsTemplate = $true
                    }
                }

                Mock -CommandName Get-SPWebapplication -MockWith {
                    $result = @{ }
                    $result.DisplayName = "Test"
                    $result.Url = "https://intranet.sharepoint.contoso.com"

                    $result = $result | Add-Member -MemberType ScriptMethod -Name Update -Value {
                        $Global:SPDscDesignerUpdated = $true
                    } -PassThru

                    return $result
                }

                It "Should return values from the get method" {
                    (Get-TargetResource @testParams).AllowSharePointDesigner | Should Be $true
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should Be $false
                }

                $Global:SPDscDesignerUpdated = $false
                It "Should update the SharePoint Designer settings" {
                    Set-TargetResource @testParams
                    $Global:SPDscDesignerUpdated | Should Be $true
                }
            }

            Context -Name "The server is in a farm, target site collection and the incorrect settings have been applied" -Fixture {
                $testParams = @{
                    WebAppUrl                              = "https://intranet.sharepoint.contoso.com"
                    SettingsScope                          = "SiteCollection"
                    AllowSharePointDesigner                = $false
                    AllowDetachPagesFromDefinition         = $false
                    AllowCustomiseMasterPage               = $false
                    AllowManageSiteURLStructure            = $false
                    AllowCreateDeclarativeWorkflow         = $false
                    AllowSavePublishDeclarativeWorkflow    = $false
                    AllowSaveDeclarativeWorkflowAsTemplate = $false
                }

                Mock -CommandName Get-SPSite -MockWith {
                    return @{
                        Url                                    = "https://intranet.sharepoint.contoso.com"
                        AllowDesigner                          = $true
                        AllowRevertFromTemplate                = $true
                        AllowMasterPageEditing                 = $true
                        ShowURLStructure                       = $true
                        AllowCreateDeclarativeWorkflow         = $true
                        AllowSavePublishDeclarativeWorkflow    = $true
                        AllowSaveDeclarativeWorkflowAsTemplate = $true
                    }
                }

                Mock -CommandName Test-SPDscRunAsCredential { return $true }

                It "Should return values from the get method" {
                    (Get-TargetResource @testParams).AllowSharePointDesigner | Should Be $true
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should Be $false
                }

                It "Should update the SharePoint Designer settings" {
                    Set-TargetResource @testParams
                }
            }

            Context -Name "The server is in a farm, target site collection and InstallAccount is used" -Fixture {
                $testParams = @{
                    WebAppUrl                              = "https://intranet.sharepoint.contoso.com"
                    SettingsScope                          = "SiteCollection"
                    AllowSharePointDesigner                = $false
                    AllowDetachPagesFromDefinition         = $false
                    AllowCustomiseMasterPage               = $false
                    AllowManageSiteURLStructure            = $false
                    AllowCreateDeclarativeWorkflow         = $false
                    AllowSavePublishDeclarativeWorkflow    = $false
                    AllowSaveDeclarativeWorkflowAsTemplate = $false
                }
                Mock -CommandName Get-SPSite -MockWith {
                    return @{
                        Url                                    = "https://intranet.sharepoint.contoso.com"
                        AllowDesigner                          = $true
                        AllowRevertFromTemplate                = $true
                        AllowMasterPageEditing                 = $true
                        ShowURLStructure                       = $true
                        AllowCreateDeclarativeWorkflow         = $true
                        AllowSavePublishDeclarativeWorkflow    = $true
                        AllowSaveDeclarativeWorkflowAsTemplate = $true
                    }
                }
                Mock -CommandName Test-SPDscRunAsCredential { return $false }

                It "Should throw an exception in the get method to say that this is not supported" {
                    { Get-TargetResource @testParams } | Should throw "http://aka.ms/xSharePointRemoteIssues"
                }

                It "Should throw an exception in the test method to say that this is not supported" {
                    { Test-TargetResource @testParams } | Should throw "http://aka.ms/xSharePointRemoteIssues"
                }

                It "Should throw an exception in the set method to say that this is not supported" {
                    { Set-TargetResource @testParams } | Should throw "http://aka.ms/xSharePointRemoteIssues"
                }
            }

            Context -Name "The server is in a farm, target is web application and the correct settings have been applied" -Fixture {
                $testParams = @{
                    WebAppUrl                              = "https://intranet.sharepoint.contoso.com"
                    SettingsScope                          = "SiteCollection"
                    AllowSharePointDesigner                = $false
                    AllowDetachPagesFromDefinition         = $false
                    AllowCustomiseMasterPage               = $false
                    AllowManageSiteURLStructure            = $false
                    AllowCreateDeclarativeWorkflow         = $false
                    AllowSavePublishDeclarativeWorkflow    = $false
                    AllowSaveDeclarativeWorkflowAsTemplate = $false
                }

                Mock -CommandName Get-SPSite -MockWith {
                    $returnVal = @{
                        Url                                    = "https://intranet.sharepoint.contoso.com"
                        AllowDesigner                          = $false
                        AllowRevertFromTemplate                = $false
                        AllowMasterPageEditing                 = $false
                        ShowURLStructure                       = $false
                        AllowCreateDeclarativeWorkflow         = $false
                        AllowSavePublishDeclarativeWorkflow    = $false
                        AllowSaveDeclarativeWorkflowAsTemplate = $false
                    }
                    $returnVal = $returnVal | Add-Member -MemberType ScriptMethod -Name Update -Value {
                        $Global:SPDscDesignerUpdated = $true
                    } -PassThru
                    return $returnVal
                }

                Mock -CommandName Test-SPDscRunAsCredential { return $true }

                Mock -CommandName Get-SPWebApplication -MockWith {
                    $result = @{ }
                    $result.DisplayName = "Test"
                    $result.Url = "https://intranet.sharepoint.contoso.com"

                    return $result
                }

                It "Should return values from the get method" {
                    (Get-TargetResource @testParams).AllowSharePointDesigner | Should Be $false
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should Be $true
                }
            }

            Context -Name "The server is in a farm, target is site collection and the correct settings have been applied" -Fixture {
                $testParams = @{
                    WebAppUrl                              = "https://intranet.sharepoint.contoso.com"
                    SettingsScope                          = "SiteCollection"
                    AllowSharePointDesigner                = $false
                    AllowDetachPagesFromDefinition         = $false
                    AllowCustomiseMasterPage               = $false
                    AllowManageSiteURLStructure            = $false
                    AllowCreateDeclarativeWorkflow         = $false
                    AllowSavePublishDeclarativeWorkflow    = $false
                    AllowSaveDeclarativeWorkflowAsTemplate = $false
                }

                Mock -CommandName Get-SPSite -MockWith {
                    $returnVal = @{
                        Url                                    = "https://intranet.sharepoint.contoso.com"
                        AllowDesigner                          = $false
                        AllowRevertFromTemplate                = $false
                        AllowMasterPageEditing                 = $false
                        ShowURLStructure                       = $false
                        AllowCreateDeclarativeWorkflow         = $false
                        AllowSavePublishDeclarativeWorkflow    = $false
                        AllowSaveDeclarativeWorkflowAsTemplate = $false
                    }
                    $returnVal = $returnVal | Add-Member -MemberType ScriptMethod -Name Update -Value {
                        $Global:SPDscDesignerUpdated = $true
                    } -PassThru
                    return $returnVal
                }

                Mock -CommandName Test-SPDscRunAsCredential -MockWith { return $true }

                It "Should return values from the get method" {
                    (Get-TargetResource @testParams).AllowSharePointDesigner | Should Be $false
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should Be $true
                }
            }
        }
    }
}
finally
{
    Invoke-TestCleanup
}
