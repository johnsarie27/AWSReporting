#Requires -Module UtilityFunctions

function Export-QuarterlyReport {
    <# =========================================================================
    .SYNOPSIS
        Generate reports for instances offline and running without reservation
    .DESCRIPTION
        This script iterates through all instances in a give AWS Region and creates
        a list of specific attributes. It then finds the last stop time, user who
        stopped the instance, and calculates the number of days the system has been
        stopped (if possible) and creates a data sheet (CSV). The data sheet is then
        imported into Excel and formatted.  This can be done for a single or
        multiple accounts based on AWS Credentail Profiles.
    .PARAMETER Path
        Path to existing folder for report
    .PARAMETER ProfileName
        This is the name of the AWS Credential profile containing the Access Key and
        Secret Key.
    .PARAMETER Region
        This is the AWS region containing the desired resources to be processed
    .INPUTS
        System.String.
    .OUTPUTS
        Excel spreadsheet.
    .EXAMPLE
        PS C:\> Export-QuarterlyReport -Region us-west-1 -ProfileName MyAccount
        Generate new EC2 report for all instances in MyAccount in the us-west-1
        region
    ========================================================================= #>
    [CmdletBinding()]
    Param(
        [Parameter(HelpMessage = 'Path to existing folder for report')]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [Alias('Directory', 'Folder', 'FolderPath')]
        [string] $Path,

        [Parameter(Mandatory, HelpMessage = 'AWS Credential Profie with key and secret')]
        [ValidateScript({(Get-AWSCredential -ListProfileDetail).ProfileName -contains $_ })]
        [Alias('Profile', 'PN')]
        [string[]] $ProfileName,

        [Parameter(HelpMessage = 'AWS Region')]
        [ValidateSet('us-east-1','us-east-2','us-west-1','us-west-2')]
        [string] $Region = 'us-east-1'
    )

    Begin {
        # IMPORT REQUIRED MODULES
        Import-Module -Name UtilityFunctions

        # SET OUTPUT REPORT PATH
        $ReportName = 'AWS-QuarterlyReport' ; $Date = Get-Date -Format "yyyy-MM"
        if ( $PSBoundParameters.ContainsKey('Path') ) {
            $ReportPath = Join-Path -Path $Path -ChildPath ('{0}_{1}.xlsx' -f $Date, $ReportName)
        } else {
            $ReportPath = Join-Path -Path "$HOME\Desktop" -ChildPath ('{0}_{1}.xlsx' -f $Date, $ReportName)
        }

        # SET VAR FOR INSTANCES
        $InstanceList = @()

        # CREATE PARAMETERS FOR EXCEL EXPORT
        $Splat = @{
            Path         = $ReportPath
            AutoSize     = $true
            Freeze       = $true
            SuppressOpen = $true
        }
    }

    Process {
        # POPULATE ARRAY AND ADD DATA VALUES FOR STOP AND COST INFO
        $InstanceList += Get-InstanceList -Region $Region -ProfileName $ProfileName
        foreach ( $instance in $InstanceList ) { $instance.GetStopInfo() }
        Get-CostInfo -Region $Region -InstanceList $InstanceList | Out-Null

        # CREATE ARRAY FOR STOPPED INSTANCES 90 DAYS OR MORE
        $90DayList = @( $InstanceList | Where-Object State -eq 'stopped' |
            Select-Object ProfileName, Id, Name, LastStart, LastStopped, DaysStopped, Stopper |
            Sort-Object DaysStopped )

        # CREATE ARRAY FOR RUNNING INSTANCES NOT RESERVED
        $60DayList = @( $InstanceList | Where-Object State -eq 'running' |
            Select-Object ProfileName, Name, Type, Reserved, LastStart, DaysRunning, OnDemandPrice, ReservedPrice, Savings |
            Sort-Object LastStart )

        # CREATE ARRAY FOR UNATTACHED VOLUMES
        $AllVolumes = Get-AvailableEBS -ProfileName $ProfileName | Group-Object -Property Account | Select-Object Name, Count

        # IF EXISTS EXPORT 60 DAY LIST
        if ( $60DayList.Count -ge 1 ) { $60DayList | Export-ExcelBook @Splat -SheetName '60-Day Report' }

        # IF EXISTS EXPORT 90 DAY LIST
        if ( $90DayList.Count -gt 0 ) { $90DayList | Export-ExcelBook @Splat -SheetName '90-Day Report' }

        # EXPORT VOLUMES LIST
        if ( $AllVolumes ) { $AllVolumes | Export-ExcelBook @Splat -SheetName 'Unattached EBS' }
    }

    End {
        # OPEN REPORT
        Invoke-Item -Path $Splat.Path
    }
}