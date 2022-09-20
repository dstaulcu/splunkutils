$script_start = get-date

# import moduel providing for various Splunk related functions
import-module -name "C:\Apps\splunkutils\splunkutils.psm1" -force

<# Toggle global verbosity Level
$VerbosePreference = 'Continue'
$VerbosePreference = 'SilentlyContinue'
#>

# gather username/password for Splunk
if (-not($mycred)) { $mycred = Get-Credential -Message "Enter credential for interacting with Splunkbase" }

# trade username/password for session key
$Session = Get-SplunkbaseSession -credential $mycred

# get splunkbase apps
$SplunkbaseApps = Get-SplunkbaseApps -session $Session
if (-not($SplunkbaseApps.count -ge 1)) {
    write-host "$(get-date) - Get-SplunkbaseApps function returned unexpected results."
    break
}

# show most recently updated app as preview of results
write-host "$(get-date) - Get-SplunkbaseApps function returned $($SplunkbaseApps.count) results.  Preview:"
$SplunkbaseApps | Sort-Object -Property updated_time -Descending | Select-Object -First 1

# display script execution runtime summary
$timespan = New-TimeSpan -Start $script_start
write-output "$(get-date) - Script execution completed with runtime duration of [$($timespan)]."
