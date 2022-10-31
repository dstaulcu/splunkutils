$splunk_server = 'localhost'
$splunk_port = '9088'
$BaseUrl = "https://$($splunk_server):$($splunk_port)"

$Token = 'a6ce405b-5b0f-4fba-bd21-4950de999602'


$response = ""
$formatteddate = "{0:MM/dd/yyyy hh:mm:sstt zzz}" -f (Get-Date)
$arraySeverity = 'INFO','WARN','ERROR'
$severity = $arraySeverity[(Get-Random -Maximum ([array]$arraySeverity).count)]

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Authorization", "Splunk $($Token)")
$Channel = (New-Guid).Guid
$headers.Add("X-Splunk-Request-Channel", $Channel)

$body = '{
        "host":"' + $env:computername + '",
        "sourcetype":"testevents",
        "source":"Geoff''s PowerShell Script",
        "index":"main",
        "event":{
            "message":"Something Happened on host ' + $env:computername + '",
            "severity":"' + $severity + '",
            "user": "'+ $env:username + '",
            "date":"' + $formatteddate + '"
            }
        }'

$splunkserver = "https://$($splunk_server):$($splunk_port)/services/collector/event"
$response = Invoke-RestMethod -Uri $splunkserver -Method Post -Headers $headers -Body $body -SkipCertificateCheck
$response

