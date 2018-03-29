#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Disable-DbaAgHadr {
    <#
        .SYNOPSIS
            Disables the Hadr service setting on the specified SQL Server.

        .DESCRIPTION
            In order to build an AG a cluster has to be built and then the Hadr enabled for the SQL Server
            service. This function disables that feature for the SQL Server service.

        .PARAMETER SqlInstance
            The SQL Server that you're connecting to.

        .PARAMETER Credential
            Credential object used to connect to the Windows server itself as a different user

        .PARAMETER WhatIf
            Shows what would happen if the command were to run. No actions are actually performed.

        .PARAMETER Confirm
            Prompts you for confirmation before executing any changing operations within the command.

        .PARAMETER Force
            Will restart SQL Server and SQL Server Agent service to apply the change.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: DisasterRecovery, AG, AvailabilityGroup
            Author: Shawn Melton (@wsmelton | http://blog.wsmelton.info)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Disable-DbaAgHadr

        .EXAMPLE
            Disable-DbaAgHadr -SqlInstance sql2016 -Force

            Sets Hadr service to disabled for the instance sql2016, and restart the service to apply the change.

        .EXAMPLE
            Disable-DbaAgHadr -SqlInstance sql2012\dev1 -Force

            Sets Hadr service to disabled for the instance dev1 on sq2012, and restart the service to apply the change.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [switch]$Force,
        [Alias('Silent')]
        [switch]$EnableException
    )
    process {
        $Enabled = 0
        foreach ($instance in $SqlInstance) {
            $computer = $computerFullName = $instance.ComputerName
            $instanceName = $instance.InstanceName

            $noChange = $false

            switch ($instance.InstanceName) {
                'MSSQLSERVER' { $agentName = 'SQLSERVERAGENT' }
                default { $agentName = "SQLAgent`$$instanceName" }
            }

            try {
                Write-Message -Level Verbose -Message "Checking current Hadr setting for $computer"
                $currentState = Get-DbaAgHadr -SqlInstance $instance -Credential $Credential
            }
            catch {
                Stop-Function -Message "Failure to pull current state of Hadr setting on $computer" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $isHadrEnabled = $currentState.IsHadrEnabled
            Write-Message -Level InternalComment -Message "$instance Hadr current value: $isHadrEnabled"

            if (-not $isHadrEnabled) {
                Write-Message -Level Warning -Message "Hadr is already disabled for instance: $($instance.FullName)"
                $noChange = $true
                continue
            }
            
            if ($isHadrEnabled -is [string]) {
                Stop-Function -Message "Failure on $($instance.FullName) | The AlwaysOn Availability Groups feature requires the x86(non-WOW) or x64 Enterprise Edition of SQL Server 2012 (or later version) running on Windows Server 2008 (or later version) with WSFC hotfix KB 2494036 installed."
                $noChange = $true
                continue
            }
            
            $scriptblock = {
                $sqlService = $wmi.Services[$args[0]]
                $sqlService.ChangeHadrServiceSetting(0)
            }
            
            if ($noChange -eq $false) {
                if ($PSCmdlet.ShouldProcess($instance, "Changing Hadr from $isHadrEnabled to $Enabled for $instance")) {
                    try {
                        Invoke-ManagedComputerCommand -ComputerName $computerFullName -Credential $Credential -ScriptBlock $scriptblock -ArgumentList $instancename
                    }
                    catch {
                        Stop-Function -ErrorRecord $_ -Message "Failure on $instance" -Target $instance
                    }
                }
                if (Test-Bound 'Force') {
                    if ($PSCmdlet.ShouldProcess($instance, "Force provided, restarting Engine and Agent service for $instance on $computerFullName")) {
                        try {
                            Stop-DbaSqlService -ComputerName $computerFullName -InstanceName $instanceName -Type Agent, Engine
                            Start-DbaSqlService -ComputerName $computerFullName -InstanceName $instanceName -Type Agent, Engine
                        }
                        catch {
                            Stop-Function -Message "Issue restarting $instance" -Target $instance -Continue
                        }
                    }
                }
                $newState = Get-DbaAgHadr -SqlInstance $instance -Credential $Credential

                [PSCustomObject]@{
                    ComputerName = $newState.ComputerName
                    InstanceName = $newState.InstanceName
                    SqlInstance  = $newState.SqlInstance
                    HadrPrevious = $currentState.IsHadrEnabled
                    HadrCurrent  = $newState.IsHadrEnabled
                }
            }
        } # foreach instance
    }
}