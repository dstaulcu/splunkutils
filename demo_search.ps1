$splunk_server = "win-9iksdb1vgmj.mshome.net"
$splunk_rest_port = "8089"
$BaseUrl = "https://$($splunk_server):$($splunk_rest_port)"
$script_start = get-date

# import moduel providing for various Splunk related functions
import-module -name "C:\Apps\splunkutils\splunkutils.psm1" -force

<# Toggle Verbosity Level
$VerbosePreference = 'Continue'
$VerbosePreference = 'SilentlyContinue'
#>

# gather username/password for Splunk
if (-not($mycred)) { $mycred = Get-Credential -Message "Enter credential for interacting with $($BaseUrl)." }

# trade username/password for session key
$SplunkSessionKey = Get-SplunkSessionKey -Credential $myCred -BaseUrl $BaseUrl

# specify search query to execute
$query = '| makeresults count=150234
| streamstats count as eventnumber
| eval _time = _time + eventnumber
| delta eventnumber as delta
| eval delta=coalesce(delta,"0")
| table _time delta, eventnumber
| sort 0 _time '

# specify search query to execute
$query = ' search earliest=-24h index=_internal
| stats count by _time, index, sourcetype, source, host, _raw
| fields - count
| sort 0 _time '


# execute search job
try { $SplunkSearchJob = Invoke-SplunkSearchJob -sessionKey $SplunkSessionKey -BaseUrl $BaseUrl -query $query -namespace "search" -adhoc_search_level "smart" -sample_ratio 1 } catch { break }

# wait for search job to complete
try { $JobSummary = Watch-SplunkSearchJob -sessionKey $SplunkSessionKey -BaseUrl $BaseUrl -SearchJobSid $SplunkSearchJob.Sid } catch { break }

# download search job results (as statistics)
if ($jobInfo.resultCount -gt 0) {
    $SearchJobResults = Get-SplunkSearchJobResults -sessionKey $SplunkSessionKey -BaseUrl $BaseUrl -jobSummary $JobSummary
    write-output "$(get-date) - Function returned $($SearchJobResults.results.Count) items."
    write-output $SearchJobResults[0]

}

# display preview of results
if ($SearchJobResult.count -ge 1) {
    write-output "$(get-date) - Result Preview:"
    $SearchJobResults | Group-Object index, sourcetype, source

}

# todo:  delete job

# display script execution runtime summary
$timespan = New-TimeSpan -Start $script_start
write-output "$(get-date) - Script execution completed with runtime duration of [$($timespan)]."
