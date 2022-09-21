$splunk_server = "win-9iksdb1vgmj.mshome.net"
$splunk_rest_port = "8089"
$BaseUrl = "https://$($splunk_server):$($splunk_rest_port)"
$script_start = get-date

# import moduel providing for various Splunk related functions
import-module -name "C:\Apps\splunkutils\splunkutils.psm1" -force

<# Toggle global verbosity Level
$VerbosePreference = 'Continue'
$VerbosePreference = 'SilentlyContinue'
#>

# gather username/password for Splunk
if (-not($mycred)) { $mycred = Get-Credential -Message "Enter credential for interacting with $($BaseUrl)." }

# trade username/password for session key
$SplunkSessionKey = Get-SplunkSessionKey -Credential $myCred -BaseUrl $BaseUrl

# specify search query to execute (non-events)
$query = '| tstats count WHERE (index=*) AND earliest=0 by index, sourcetype, source'

# execute search job
try { $SplunkSearchJob = Invoke-SplunkSearchJob -sessionKey $SplunkSessionKey -BaseUrl $BaseUrl -query $query -namespace "search" -adhoc_search_level "smart" -sample_ratio 1 } catch { break }

# wait for search job to complete
try { $JobSummary = Watch-SplunkSearchJob -sessionKey $SplunkSessionKey -BaseUrl $BaseUrl -SearchJobSid $SplunkSearchJob.Sid } catch { break }

# download search job results (as statistics)
if ($jobSummary.resultCount -gt 0) {
    $SearchJobResults = Get-SplunkSearchJobResults -sessionKey $SplunkSessionKey -BaseUrl $BaseUrl -jobSummary $JobSummary
    write-output "$(get-date) - Function returned $($SearchJobResults.results.Count) items."
}

$SplunkObjects = $SearchJobResults
$FieldSummaries = New-Object System.Collections.ArrayList

foreach ($object in $SplunkObjects) {

    # todo -- dnyamically compute sample ratio based on count events observed via tstats
    $key = $object.index + '*' + $object.sourcetype + '*' + $object.source    
    $sample_ratio = 1
    $sample_ratio = [int]$sample_ratio.tostring().PadRight(($object.count.length-1),'0')

    write-host "$(get-date) - key [$($key)] has [$($object.count)] events. Using sample ratio of $($sample_ratio)."


    # specify search query to execute (non-events)

    $query = '| search index="' + $object.index + '" sourcetype="' + $object.sourcetype + '" source="' + $object.source + '" | fieldsummary | fields field | mvcombine field | eval key="' + $key + '"'

    # execute search job
    try { $SplunkSearchJob = Invoke-SplunkSearchJob -sessionKey $SplunkSessionKey -BaseUrl $BaseUrl -query $query -namespace "search" -adhoc_search_level "verbose" -sample_ratio $sample_ratio   } catch { break }

    # wait for search job to complete
    try { $JobSummary = Watch-SplunkSearchJob -sessionKey $SplunkSessionKey -BaseUrl $BaseUrl -SearchJobSid $SplunkSearchJob.Sid } catch { break }

    # download search job results (as statistics)
    if ($jobSummary.resultCount -gt 0) {
        $SearchJobResults = Get-SplunkSearchJobResults -sessionKey $SplunkSessionKey -BaseUrl $BaseUrl -jobSummary $JobSummary
        write-output "$(get-date) - Function returned $($SearchJobResults.results.Count) items."
        $FieldSummaries.add($SearchJobResults) | out-null   
    }

}

$FieldSummaries

# display script execution runtime summary
$timespan = New-TimeSpan -Start $script_start
write-output "$(get-date) - Script execution completed with runtime duration of [$($timespan)]."
