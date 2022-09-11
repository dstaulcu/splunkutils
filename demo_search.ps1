$splunk_server = "win-9iksdb1vgmj.mshome.net"
$splunk_rest_port = "8089"
$BaseUrl = "https://$($splunk_server):$($splunk_rest_port)"
$script_start = get-date

# import moduel providing for various Splunk related functions
import-module -name "C:\Apps\splunkutils\splunkutils.psm1"

# gather username/password for Splunk
if (-not($mycred)) { $mycred = Get-Credential -Message "Enter credential for interacting with $($BaseUrl)." }

# trade username/password for session key
$SplunkSessionKey = Get-SplunkSessionKey -Credential $myCred -BaseUrl $BaseUrl

# specify search query to execute
$query = '| makeresults count=150000
| streamstats count as eventnumber
| eval _time = _time + eventnumber
| delta eventnumber as delta
| eval delta=coalesce(delta,"0")'

# execute search
write-output "$(get-date) - Invoking Read-SplunkSearchResults function with query: `n$($query)"
$Events = Read-SplunkSearchResults -sessionKey $SplunkSessionKey -BaseUrl $BaseUrl -query $query -Verbose
write-output "$(get-date) - Read-SplunkSearchResults function returned with $($events.count) events."

# provide preview of events
write-output $events[0..9]
write-output "..."
write-output $events[-2..-1]

# display script execution runtime summary
$timespan = New-TimeSpan -Start $script_start
write-output "$(get-date) - Script execution completed with runtime duration of [$($timespan)]."
