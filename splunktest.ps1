import-module -name "C:\Apps\splunkutils\splunkutils.psm1" -Force

<# Helpful commands to get started

Get-Command -Module splunkutils         # explore available commands
get-help Get-SplunkSessionKey           # list details of first function to run

#>

$splunk_server = "win-9iksdb1vgmj.mshome.net"
$splunk_rest_port = "8089"
$BaseUrl = "https://$($splunk_server):$($splunk_rest_port)"

# gather username/password for Splunk
if (-not($mycred)) { $mycred = Get-Credential -Message "Enter credential for interacting with $($BaseUrl)." }

# trade username/password for session key
if (-not($SplunkSessionKey)) { $SplunkSessionKey = Get-SplunkSessionKey -Credential $myCred -BaseUrl $BaseUrl }

# invoke search 
$maxResultRowsLimit = 50000
$query = '| makeresults count=100'

$searchjob = Invoke-SplunkSearchJob -SessionKey $SplunkSessionKey -BaseUrl $BaseUrl -query $query 

if ($searchjob ) {
 
    # Wait for the job to complete
    $counter = 0
    do {
        # sleep 
        $counter++
        Start-Sleep -Seconds 1

        # get the job status object
        $jobstatus = Get-SplunkSearchJobStatus -sessionKey $SplunkSessionKey -BaseUrl $BaseUrl -jobsid $searchjob.response.sid
 
        # retrieve the dispatchState property (Can be any of QUEUED, PARSING, RUNNING, PAUSED, FINALIZING, FAILED, DONE)
        $dispatchState = [string]($jobstatus.entry.content.dict.key | Where-Object { $_.Name -eq "dispatchState" })."#text"

        # show status of the job
        write-host (get-date) "- Current dispatch sid $($searchjob.response.sid) has status [$($dispatchState)]."     
    }
    until ($dispatchState -match "(FAILED|DONE)")

    if ($dispatchState -match "FAILED") {
        write-host (get-date) "- Job execution failed. Exiting."
    }
    else {

        # now that the job is DONE, retrieve other job properties of interest:
        $jobSid = [string]($jobstatus.entry.content.dict.key | Where-Object { $_.Name -eq "sid" })."#text"
        $jobEventCount = [int]($jobstatus.entry.content.dict.key | Where-Object { $_.Name -eq "eventCount" })."#text"
        $jobResultCount = [int]($jobstatus.entry.content.dict.key | Where-Object { $_.Name -eq "resultCount" })."#text"
        $jobResultDiskUsage = [int]($jobstatus.entry.content.dict.key | Where-Object { $_.Name -eq "diskUsage" })."#text"
        $jobResultrunDuration = [float]($jobstatus.entry.content.dict.key | Where-Object { $_.Name -eq "runDuration" })."#text"
        $jobttl = [int]($jobstatus.entry.content.dict.key | Where-Object { $_.Name -eq "ttl" })."#text"

        write-host (get-date) "- Job completed with EventCount=$($jobEventCount) ResultCount=$($jobResultCount) DiskUsage=$($jobResultDiskUsage) RunDuration=$($jobResultrunDuration) ttl=$($jobttl)"

        <#
        # now we have to retrieve the job results. Since this is REST, there are limits (default 50,000) [$maxResultRowsLimit] to count of records that can be returned.
        # https://answers.splunk.com/answers/25411/upper-limit-for-rest-api-limits-conf-maxresultrows.html
        #>
   
        $totalResultsExpected = ($jobEventCount + $jobResultCount)
        $totalResultsReturned = 0
        $jobResults = @()

        # create a tmp file to append results to (better than appending an object in memory)
        $tmpString = Get-Random -Minimum 10000 -Maximum 99999
        $tmpFileName = "SplunkSearchResultsTemp$($tmpString).csv"
        $tmpFilePath = $env:temp
        if (Test-Path -Path "$($tmpFilePath)\$($tmpFileName)") { Remove-Item -Path "$($tmpFilePath)\$($tmpFileName)" -Force }
    
        $downloadPart = 1
        do {
            # download the data in batches       
            $downloadPartFile = "$($tmpFilePath)\$($tmpFileName).part$($downloadPart)"
            write-host (get-date) "- Downloading up to $($maxResultRowsLimit) rows offset from $($totalResultsReturned) to $($downloadPartFile)"
            $jobresults = Get-SplunkSearchJobResults -sessionKey $SplunkSessionKey -BaseUrl $BaseUrl -jobsid $searchjob.response.sid -offset $totalResultsReturned

            $jobresults | ConvertFrom-Csv | Export-Csv -NoTypeInformation -Path $downloadPartFile
    
            $totalResultsReturned += $maxResultRowsLimit
            $downloadPart += 1
    
        }
        until ($totalResultsReturned -ge $totalResultsExpected)

        # now we need to coalesce the download parts
        $PartFiles = Get-ChildItem -Path $tmpFilePath -Filter "$($tmpFileName).part*" | Sort-Object -Property LastWriteTime

        foreach ($partfile in $partfiles) {

            write-host (get-date) "- Collating $($partfile.name) into $($tmpFileName)."

            # commit partfile 1 in it's entirety
            if ($partfile.name -match "\.part1$") {

                $partfile.FullName | Rename-Item -NewName "$($tmpFilePath)\$($tmpFileName)"
            }
            else {
                # commit all but line 1 in other partfiles
                $skip = 1

                # create the FileStream and StreamWriter objects
                $ins = New-Object System.IO.StreamReader($partfile.FullName)
                $fs = New-Object IO.FileStream "$($tmpFilePath)\$($tmpFileName)" , 'Append', 'Write', 'Read'
                $outs = New-Object System.IO.StreamWriter($fs)

                try {
                    # Skip the first N lines, but allow for fewer than N, as well
                    for ( $s = 1; $s -le $skip -and !$ins.EndOfStream; $s++ ) {
                        # waste the top line
                        $ins.ReadLine() | Out-Null
                    }
                    while ( !$ins.EndOfStream ) {
                        $outs.writeline( $ins.ReadLine() )
                    }
                }
                finally {
                    $outs.Close()
                    $ins.close()
                    $fs.Dispose()
                }
            }
            $partfile | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        write-host (get-date) "- Operation complete.  Result file is $($tmpFilePath)\$($tmpFileName)"

    }
}


