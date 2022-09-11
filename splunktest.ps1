$splunk_server = "win-9iksdb1vgmj.mshome.net"
$splunk_rest_port = "8089"
$BaseUrl = "https://$($splunk_server):$($splunk_rest_port)"
$script_start = get-date

import-module -name "C:\Apps\splunkutils\splunkutils.psm1" -force

# gather username/password for Splunk
if (-not($mycred)) { $mycred = Get-Credential -Message "Enter credential for interacting with $($BaseUrl)." }

# trade username/password for session key
$SplunkSessionKey = Get-SplunkSessionKey -Credential $myCred -BaseUrl $BaseUrl

$query = '| makeresults count=150000
| streamstats count
| eval _time = _time + count
| delta count as delta
| eval delta=coalesce(delta,"0")'

# invoke search 
write-host "$(get-date) - Executing search with query $($query)"

try {
    $SplunkSearchJobResponse = Invoke-SplunkSearchJob -SessionKey $SplunkSessionKey -BaseUrl $BaseUrl -query $query
}
catch {
    write-host "$(get-date) - Exiting after exception occured in Invoke-SplunkSearchJob function. Exception Message:"
    write-host "$($error[0].Exception.Message)" -ForegroundColor Red
    break
}

$SearchJobSid = $SplunkSearchJobResponse.response.sid

# wait for search job completion
do {

    Start-Sleep -Seconds 1

    try {
        $SplunkSearchJobStatusResponse = Get-SplunkSearchJobStatus -sessionKey $SplunkSessionKey -BaseUrl $BaseUrl -jobsid $SearchJobSid
    }
    catch {
        write-host "$(get-date) - Exiting after exception occured in Get-SplunkSearchJobStatus function. Exception Message:"
        write-host "$($error[0].Exception.Message)" -ForegroundColor Red
        break        
    }

    $isDone = ((([xml] $SplunkSearchJobStatusResponse.InnerXml).entry.content.dict.key) | Where-Object { $_.Name -eq "isDone" }).'#text'
    $dispatchState = [string]((([xml] $SplunkSearchJobStatusResponse.InnerXml).entry.content.dict.key) | Where-Object { $_.Name -eq "dispatchState" }).'#text'

    write-host "$(get-date) - Search with id [$($SearchJobSid)] has status [$($dispatchState)]."         

} while ($isDone -eq 0)
$runDuration = [decimal]((([xml] $SplunkSearchJobStatusResponse.InnerXml).entry.content.dict.key) | Where-Object { $_.Name -eq "runDuration" }).'#text'
$resultCount = [int]((([xml] $SplunkSearchJobStatusResponse.InnerXml).entry.content.dict.key) | Where-Object { $_.Name -eq "resultCount" }).'#text'

write-host "$(get-date) - Search with id [$($SearchJobSid)] completed with result count [$($resultCount)] after run duration [$($runDuration)] seconds."         

# gather search job results
$events = New-Object System.Collections.ArrayList
do {
    
    # get batch of events
    try {
        $SplunkSearchJobResults = Get-SplunkSearchJobResults -sessionKey $SplunkSessionKey -BaseURL $BaseUrl -jobsid $SearchJobSid -offset $events.count
    }
    catch {
        write-host "$(get-date) - Exiting after exception occured in Get-SplunkSearchJobResults. Exception Message:"
        write-host "$($error[0].Exception.Message)" -ForegroundColor Red
        break
    }

    # append batch of events to results array
    foreach ($result in $SplunkSearchJobResults.results) {
        $events.Add($result) | out-null
    }

    # give the user an idea of progress toward completion.
    write-host "$(get-date) - Downloaded search results [$($events.count)] of [$($resultCount)]."         

} while ($events.count -ne $resultCount)

# display script execution duration summary
$timespan = New-TimeSpan -Start $script_start
write-host "$(get-date) - Script execution completed with runtime $($timespan)."

# display script results in gridview
$events | Out-GridView
