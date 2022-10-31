
<# PUBLIC AUTHENTICATION FUNCTIONS #>
function Get-SplunkSessionKey {

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string[]]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        $Credential
    )

    write-host "$(get-date) - Attempting to exchnage Splunk credential for web session key." | Out-Null

    $body = @{
        username = $Credential.username
        password = $Credential.GetNetworkCredential().Password;
    }

    try {
        $WebRequest = Invoke-RestMethod -Uri "$($BaseUrl)/services/auth/login" -Body $body -SkipCertificateCheck -ContentType 'application/x-www-form-urlencoded' -Method Post
    }
    catch {
        Write-Error "$($error[0].Exception.Message)"
        break     
    }

    return $WebRequest.response.sessionKey
}

<# PUBLIC SEARCH FUNCTIONS #>
function Watch-SplunkSearchJob {

    [CmdletBinding()]
    param (
        [ValidateNotNullOrEmpty()]
        [string]$sessionKey, 
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl, 
        [ValidateNotNullOrEmpty()]
        [string]$SearchJobSid
    )
    
    # wait for search job completion
    do {
    
        Start-Sleep -Seconds 1
    
        try {
            $SplunkSearchJobStatusResponse = Get-SplunkSearchJobStatus -sessionKey $SplunkSessionKey -BaseUrl $BaseUrl -jobsid $SearchJobSid
        }
        catch {
            Write-Error "$($error[0].Exception.Message)"
            break      
        }
    
        $isDone = ((([xml] $SplunkSearchJobStatusResponse.InnerXml).entry.content.dict.key) | Where-Object { $_.Name -eq "isDone" }).'#text'
        $dispatchState = [string]((([xml] $SplunkSearchJobStatusResponse.InnerXml).entry.content.dict.key) | Where-Object { $_.Name -eq "dispatchState" }).'#text'
    
        write-host "$(get-date) - Search with id [$($SearchJobSid)] has status [$($dispatchState)]." | Out-Null
    
    } while ($isDone -eq 0)
    
    $JobSummary = @{
        sid         = $SearchJobSid
        runDuration = [decimal]((([xml] $SplunkSearchJobStatusResponse.InnerXml).entry.content.dict.key) | Where-Object { $_.Name -eq "runDuration" }).'#text'
        resultCount = [int]((([xml] $SplunkSearchJobStatusResponse.InnerXml).entry.content.dict.key) | Where-Object { $_.Name -eq "resultCount" }).'#text'
        eventCount  = [int]((([xml] $SplunkSearchJobStatusResponse.InnerXml).entry.content.dict.key) | Where-Object { $_.Name -eq "eventCount" }).'#text'
    }

    write-host "$(get-date) - Search with id [$($JobSummary.Sid)] completed having eventcount [$($JobSummary.eventCount)] and resultcount [$($JobSummary.resultCount)] with runtime duration of [$($JobSummary.runDuration)] seconds." | Out-Null
    
    return $JobSummary
}

function Invoke-SplunkSearchJob {

    [CmdletBinding()]
    param (
        [ValidateNotNullOrEmpty()]
        [string]$sessionKey, 
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl, 
        [string]$User = 'nobody',
        [string]$Namespace = 'search',
        [ValidateNotNullOrEmpty()]
        [string]$query,
        [ValidateSet("fast", "smart", "verbose")]
        [string]$adhoc_search_level = "smart",
        [int]$sample_ratio = 1

    )
 
    $uri = "$($BaseUrl)/servicesNS/$($User)/$($Namespace)/search/v2/jobs"    

    $headers = [ordered]@{
        Authorization  = "Splunk $($SessionKey)"
        Accept         = 'application/json'
        'Content-Type' = 'application/json'
    }     

    $body = @{
        search             = $query
        output_mode        = "json"
        count              = "0"
        exec_mode          = "normal"
        max_count          = 10000
        adhoc_search_level = $adhoc_search_level  # verbose, fast, smart
        sample_ratio       = $sample_ratio 
        namespace          = $Namespace
    }

    Write-Host -Message "$(get-date) - Invoking-SplunkSearchJob with query:" | Out-Null
    Write-Host -Message "$($query)" | Out-Null    
     
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -SkipCertificateCheck

    return $response
}

<# PRIVATE SEARCH FUNCTIONS #>
 
function Get-SplunkSearchJobStatus {

    [CmdletBinding()]
    param (
        [ValidateNotNullOrEmpty()]
        [string]$sessionKey,
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$jobsid
    )
  
    $uri = "$($BaseUrl)/services/search/v2/jobs/$($jobsid)"

    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
    }     

    $Response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -SkipCertificateCheck

    return $Response

}

<# under construction
function Get-SplunkSearchJobEvents {

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$sessionKey,
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$jobsid
    )
  
    $uri = "$($BaseUrl)/services/search/v2/jobs/$($jobsid)/events/"

    $headers = [ordered]@{
        Authorization  = "Splunk $($SessionKey)"
        Accept         = 'application/json'
        'Content-Type' = 'application/json'
    }     

    $offset = 0
    $Items = New-Object System.Collections.ArrayList

    do {
        
        try {
            $SplunkSearchJobResults = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -Body  @{ output_mode = "xml" ; offset=$offset ; count = 0 } -SkipCertificateCheck
        }
        catch {
            Write-Error "$($error[0].Exception.Message)"
            break        
        }
    
        # append batch of events to results array
        foreach ($result in $SplunkSearchJobResults.results) {
            $Items.Add($result) | out-null
        }

        # give the user an idea of progress toward completion.
        write-host "$(get-date) - Downloaded $($Items.count) of $($jobsummary.resultCount) results." | Out-Null


        $offset = $Items.count
        
    } until ($Items.count -ge $jobSummary.resultCount)    
     
    return $Items        

}
#>

function Get-SplunkSearchJobResults {

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$sessionKey,
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [System.Collections.Hashtable]$jobSummary,
        [ValidateNotNullOrEmpty()]
        [int]$offset = 0
    )
  
    $uri = "$($BaseUrl)/services/search/v2/jobs/$($jobSummary.sid)/results/"

    $headers = [ordered]@{
        Authorization  = "Splunk $($SessionKey)"
        Accept         = 'application/json'
        'Content-Type' = 'application/json'
    }     

    $offset = 0
    $Items = New-Object System.Collections.ArrayList

    do {
        
        try {
            $SplunkSearchJobResults = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -Body @{ output_mode = "json" ; offset = $offset ; count = 0 } -SkipCertificateCheck
        }
        catch {
            Write-Error "$($error[0].Exception.Message)"
            break        
        }
    
        # append batch of events to results array
        foreach ($result in $SplunkSearchJobResults.results) {
            $Items.Add($result) | out-null
        }

        # give the user an idea of progress toward completion.
        write-host "$(get-date) - Downloaded $($Items.count) of $($jobsummary.resultCount) results." | Out-Null


        $offset = $Items.count
        
    } until ($Items.count -ge $jobSummary.resultCount)    
     
    return $Items

}

<# PUBLIC KVSTORE/COLLECTION FUNCTIONS #>

function Get-SplunkKVStoreCollectionList {

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [string]$User = 'nobody',
        [string]$Namespace = 'search'
    )

    Write-Host -Message "$(get-date) - getting KVstore collection list within `"$($Namespace)`" namespace." | Out-Null

    $uri = "$($BaseUrl)/servicesNS/$($User)/$($Namespace)/storage/collections/config"

    $headers = [ordered]@{
        Authorization  = "Splunk $($SessionKey)"
        'Content-Type' = 'application/json'    
        output_mode    = 'json'
    }

    $Response = Invoke-Restmethod -Uri $uri -SkipCertificateCheck -Headers $headers -body $body -Method GET

    return $Response
}

function Add-SplunkKVStoreCollectionRecord {

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [string]$User = 'nobody',
        [string]$Namespace = 'search',
        [ValidateNotNullOrEmpty()]
        [string]$CollectionName,
        $Record
    )

    Write-Host -Message "$(get-date) - adding single record to collection named `"$($CollectionName)`" within `"$($Namespace)`" namespace." | Out-Null

    $uri = "$($BaseUrl)/servicesNS/$($User)/$($Namespace)/storage/collections/data/$($CollectionName)"

    $headers = [ordered]@{
        Authorization  = "Splunk $($SessionKey)"
        'Content-Type' = 'application/json'
    }

    $body = $Record | ConvertTo-Json -Compress

    $Response = Invoke-WebRequest -Uri $uri -SkipCertificateCheck -Headers $headers -Body $body -Method Post

    return $Response
}

function Add-SplunkKVStoreCollectionRecordsBatch {

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [string]$User = 'nobody',
        [string]$Namespace = 'search',
        [ValidateNotNullOrEmpty()]
        [string]$CollectionName,
        $Records
    )

    # kvstore batch operation limited to 1000 records. Handle paging or array elements
    $pageSize = 1000
    
    for ($i = 0; $i -le $records.count - 1; $i += $pageSize) {
        $lbound = $i
        $ubound = $i + $pageSize - 1
        if ($ubound -ge ($records.count - 1)) { $ubound = $records.count - 1 } 

        write-host -Message "$(get-date) - adding elements $($lbound) to $($ubound) of array to collection." | Out-Null

        $uri = "$($BaseUrl)/servicesNS/$($User)/$($Namespace)/storage/collections/data/$($CollectionName)/batch_save"
    
        $headers = [ordered]@{
            Authorization  = "Splunk $($SessionKey)"
            'Content-Type' = 'application/json'
        }
        
        $body = $Records[$lbound..$ubound] | ConvertTo-Json -Compress
    
        $Response = Invoke-WebRequest -Uri $uri -SkipCertificateCheck -Headers $headers -Body $body -Method Post

    }
    
    return $Response
}

function Get-SplunkKVStoreCollectionRecords {

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [string]$User = 'nobody',
        [string]$Namespace = 'search',
        [ValidateNotNullOrEmpty()]
        [string]$CollectionName
    )

    Write-Host -Message "$(get-date) - retrieving records from collection named `"$($CollectionName)`" within `"$($Namespace)`" namespace." | Out-Null

    $uri = "$($BaseUrl)/servicesNS/$($User)/$($Namespace)/storage/collections/data/$($CollectionName)"

    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
        output_mode   = 'json'
    }

    $Response = Invoke-RestMethod -Uri $uri -SkipCertificateCheck -Headers $headers

    return $Response
}

function Remove-SplunkKVStoreCollectionRecords {

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [string]$User = 'nobody',
        [string]$Namespace = 'search',
        [ValidateNotNullOrEmpty()]
        [string]$CollectionName
    )

    Write-Host -Message "$(get-date) - removing records in collection named `"$($CollectionName)`" within `"$($Namespace)`" namespace." | Out-Null

    $uri = "$($BaseUrl)/servicesNS/$($User)/$($Namespace)/storage/collections/data/$($CollectionName)"

    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
    }

    $Response = Invoke-RestMethod -Uri $uri -SkipCertificateCheck -Headers $headers -Body $body -Method Delete

    return $Response
}

function Add-SplunkKVStoreCollection {

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [string]$User = 'nobody',
        [string]$Namespace = 'search',
        [ValidateNotNullOrEmpty()]        
        [string]$CollectionName
    )

    $ProgressPreference = 'SilentlyContinue'

    Write-Host -Message "$(get-date) - creating KVstore collection named `"$($CollectionName)`" within `"$($Namespace)`" namespace." | Out-Null

    $uri = "$($BaseUrl)/servicesNS/$($User)/$($Namespace)/storage/collections/config"

    $headers = [ordered]@{
        Authorization  = "Splunk $($sessionKey)"
        'Content-Type' = 'application/x-www-form-urlencoded'
    }

    $body = @{
        name = $CollectionName
    } 

    write-verbose -Message "$(get-date) - invoking webrequest to url $($uri) with header of $($headers) and body of $($body)"    

    $Response = Invoke-RestMethod -Uri $uri -SkipCertificateCheck -Headers $headers -Body $body -Method Post

    return $Response
}

function Set-SplunkKVStoreCollectionSchema {

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [string]$User = 'nobody',
        [string]$Namespace = 'search',
        [ValidateNotNullOrEmpty()]
        [string]$CollectionName,
        [ValidateNotNullOrEmpty()]        
        $CollectionSchema
    )

    Write-Host -Message "$(get-date) - setting schema for KVstore collection named `"$($CollectionName)`" within `"$($Namespace)`" namespace." | Out-Null

    $uri = "$($BaseUrl)/servicesNS/$($User)/$($Namespace)/storage/collections/config/$($CollectionName)"

    $headers = [ordered]@{
        Authorization  = "Splunk $($SessionKey)"
        Accept         = 'application/json'
        'Content-Type' = 'application/json'
    }

    $body = $CollectionSchema 

    $Response = Invoke-RestMethod -Uri $uri -SkipCertificateCheck -Headers $headers -Body $body -Method Post

    return $Response
}

function Remove-SplunkKVStoreCollection {

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [string]$User = 'nobody',
        [string]$Namespace = 'search',
        [ValidateNotNullOrEmpty()]
        [string]$CollectionName
    )

    Write-Verbose -Message "$(get-date) - removing collection named `"$($CollectionName)`" within `"$($Namespace)`" namespace."

    $uri = "$($BaseUrl)/servicesNS/$($User)/$($Namespace)/storage/collections/config/$($CollectionName)"

    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
    }

    $Response = Invoke-RestMethod -Uri $uri -SkipCertificateCheck -Headers $headers -Body $body -Method Delete

    return $Response
}

<# PUBLIC TRANSFORM FUNCTIONS #>

function Get-SplunkTransformLookups {

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [string]$User = 'nobody',
        [string]$Namespace = 'search'
    )

    $uri = "$($BaseUrl)/servicesNS/$($User)/$($Namespace)/data/transforms/lookups"

    $headers = [ordered]@{
        Authorization  = "Splunk $($SessionKey)"
        Accept         = 'application/json'
        'Content-Type' = 'application/json'
    }     

    $WebRequest = Invoke-RestMethod -Uri $uri -SkipCertificateCheck -Method Get -Headers $headers

    return $WebRequest
}

function Add-SplunkTransformLookup {

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [string]$User = 'nobody',
        [string]$Namespace = 'search',
        [ValidateNotNullOrEmpty()]
        $TransformSchema
    )    

    <# Example TransformSchema:
        @{
            'fields_list' = '_key, id, name, message'
            'type' = 'extenal'
            'external_type' = 'kvstore'
            'name' = $CollectionName
        }
    #>

    $uri = "$($BaseUrl)/servicesNS/$($User)/$($Namespace)/data/transforms/lookups"
    
    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
    }

    $body = $TransformSchema
    
    $WebRequest = Invoke-RestMethod -SkipCertificateCheck -Uri $uri -Headers $headers -Body $body -Method Post      

    return $WebRequest 
}

function Remove-SplunkTransformLookup {

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [string]$User = 'nobody',
        [string]$Namespace = 'search',        
        [ValidateNotNullOrEmpty()]
        [string]$LookupName
    )    

    Write-Host -Message "$(get-date) - removing transform having name `"$($LookupName)`"." | Out-Null

    $uri = "$($BaseUrl)/servicesNS/$($User)/$($Namespace)/data/transforms/lookups/$($LookupName)"
    
    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
    }

    $WebRequest = Invoke-RestMethod -SkipCertificateCheck -Uri $uri -Headers $headers -Method Delete

    return $WebRequest 
}

function Get-SplunkTransformLookup {

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [string]$User = 'nobody',
        [string]$Namespace = 'search',      
        [ValidateNotNullOrEmpty()]
        [string]$LookupName
    )    

    Write-Verbose -Message "$(get-date) - removing transform having name `"$($LookupName)`"."

    $uri = "$($BaseUrl)/servicesNS/$($User)/$($Namespace)/data/transforms/lookups/$($LookupName)"
    
    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
    }

    $WebRequest = Invoke-RestMethod -SkipCertificateCheck -Uri $uri -Headers $headers -Method Get

    return $WebRequest 
}


<# SPLUNKBASE #>

function Get-SplunkbaseSession {

    [CmdletBinding()]    
    param(
        $credential
    )

    $user = $credential.UserName
    $pass = [System.Net.NetworkCredential]::new("", $credential.Password).Password

    ## establish logon session to splunk via okta
    $BASE_AUTH_URL = 'https://account.splunk.com/api/v1/okta/auth'
    $Body = @{
        username = $user
        password = $pass
    }
    $WebRequest = Invoke-WebRequest $BASE_AUTH_URL -SessionVariable 'Session' -Body $Body -Method 'POST' -UseBasicParsing
    if (-not($WebRequest.StatusCode -eq "200")) {
        Write-Error -Message "$(get-date) - Get-Splunkbase-Session: There was a problem authenticating to Splunk.  Exit."
        break
    }

    $ssoid_cookie = (($WebRequest.Content | ConvertFrom-Json).cookies).ssoid_cookie

    $cookie = New-Object System.Net.Cookie    
    $cookie.Name = "SSOSID"
    $cookie.Value = $ssoid_cookie
    $cookie.Domain = ".splunk.com"
    $session.Cookies.Add($cookie);

    return $session
}

function Get-SplunkbaseApps {
    
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [Microsoft.PowerShell.Commands.WebRequestSession]$session
    )

    # first run just to get the amount of pages to iterate over.
    $url = "https://splunkbase.splunk.com/api/v1/app/?order=latest&limit=1&offset=0"
    $response = invoke-webrequest $url -WebSession $session -UseBasicParsing
    $content = $response.Content | ConvertFrom-Json

    # gather all of the content available over pages
    $Apps = New-Object System.Collections.ArrayList

    for ($offset = 0; $offset -le $content.total; $offset += 100) {
        write-verbose -message "$(get-date) - Getting next 100 results from offset $($offset) [total=$($content.total)]"

        $url = "https://splunkbase.splunk.com/api/v1/app/?order=latest&limit=100&offset=$($offset)"

        $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
        $response = invoke-webrequest $url -WebSession $Session -UseBasicParsing
        $ProgressPreference = 'Continue'                    

        $batch_of_apps = $response.Content | ConvertFrom-Json   

        foreach ($result in $batch_of_apps.results) {
            $Apps.add($result) | Out-Null
        }

    }    

    return $Apps
}

function Get-SplunkKVStoreCollectionACL {

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [string]$User = 'nobody',
        [string]$Namespace = 'search',
        [string]$CollectionName

    )

    Write-Host -Message "$(get-date) - getting KVstore collection ACL for $($CollectionName) within `"$($Namespace)`" namespace." | Out-Null

    $uri = "$($BaseUrl)/servicesNS/$($User)/$($Namespace)/storage/collections/config/$($CollectionName)/acl"

    $headers = [ordered]@{
        Authorization  = "Splunk $($SessionKey)"
        'Content-Type' = 'application/json'    
        output_mode    = 'json'
    }

    $Response = Invoke-Restmethod -Uri $uri -SkipCertificateCheck -Headers $headers -body $body -Method GET

    return $Response
} 

function Set-SplunkKVStoreCollectionACL {

    # https://docs.splunk.com/Documentation/Splunk/9.0.1/RESTUM/RESTusing#Access_Control_List

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [string]$User = 'nobody',
        [string]$Namespace = 'search',
        [string]$CollectionName

    )

    Write-Host -Message "$(get-date) - getting KVstore collection ACL for $($CollectionName) within `"$($Namespace)`" namespace." | Out-Null

    $uri = "$($BaseUrl)/servicesNS/$($User)/$($Namespace)/storage/collections/config/$($CollectionName)/acl"

    $headers = [ordered]@{
        Authorization  = "Splunk $($SessionKey)"
        'Content-Type' = 'application/json'    
        output_mode    = 'json'
    }

    $Response = Invoke-Restmethod -Uri $uri -SkipCertificateCheck -Headers $headers -body $body -Method GET

    return $Response
}    

function Get-SplunkObjectACL {

    # https://docs.splunk.com/Documentation/Splunk/9.0.1/RESTUM/RESTusing#Access_Control_List

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [ValidateNotNullOrEmpty()]        
        [string]$id
    )

    Write-Host -Message "$(get-date) - getting KVstore collection ACL for $($CollectionName) within `"$($Namespace)`" namespace." | Out-Null

    $uri = "$($id)/acl"

    $headers = [ordered]@{
        Authorization  = "Splunk $($SessionKey)"
        'Content-Type' = 'application/json'    
        output_mode    = 'json'
    }

    $Response = Invoke-Restmethod -Uri $uri -SkipCertificateCheck -Headers $headers -body $body -Method GET

    return $Response
}  

function Set-SplunkObjectACL {

    # https://docs.splunk.com/Documentation/Splunk/9.0.1/RESTUM/RESTusing#Access_Control_List

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [ValidateNotNullOrEmpty()]        
        [string]$id,
        [string]$app = 'search',
        [string]$owner = 'nobody',
        [string]$perms_read = '*',
        [string]$perms_write = 'admin',
        [string]$removable = $true,
        [ValidateSet("app", "global", "user")]
        [string]$sharing = 'app'
    )

    Write-Host -Message "$(get-date) - getting KVstore collection ACL for $($CollectionName) within `"$($Namespace)`" namespace." | Out-Null

    $uri = "$($id)/acl"

    $headers = [ordered]@{
        Authorization  = "Splunk $($SessionKey)"
        'Content-Type' = 'application/json'    
        output_mode    = 'json'
    }

    # app and removable do not appy in context of kvstore collection
    $body = @{
#        app             = $app
        owner           = $owner
        'perms.read'    = $perms_read
        'perms.write'   = $perms_write
#        removable       = $removable
        sharing         = $sharing
    }

    $body                  
        

    $Response = Invoke-Restmethod -Uri $uri -SkipCertificateCheck -Headers $headers -body $body -Method Post

    return $Response
}  


function Get-SplunkAuthorizationRoles {

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey
    )

    Write-Host -Message "$(get-date) - getting server roles" | Out-Null

    $uri = "$($BaseUrl)/services/authorization/roles"

    $headers = [ordered]@{
        Authorization  = "Splunk $($SessionKey)"
        'Content-Type' = 'application/json'    
        output_mode    = 'json'
    }

    $Response = Invoke-Restmethod -Uri $uri -SkipCertificateCheck -Headers $headers -body $body -Method GET

    return $Response
}    


function Get-SplunkAuthenticationUsers {

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey
    )

    Write-Host -Message "$(get-date) - getting server users" | Out-Null

    $uri = "$($BaseUrl)/services/authentication/users"

    $headers = [ordered]@{
        Authorization  = "Splunk $($SessionKey)"
        'Content-Type' = 'application/json'    
        output_mode    = 'json'
    }

    $Response = Invoke-Restmethod -Uri $uri -SkipCertificateCheck -Headers $headers -body $body -Method GET

    return $Response
}   