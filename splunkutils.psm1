
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
        sid = $SearchJobSid
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
        [ValidateNotNullOrEmpty()]
        [string]$query,
        [string]$namespace = "search",
        [ValidateSet("fast","smart","verbose")]
        [string]$adhoc_search_level = "smart",
        [int]$sample_ratio = 1

    )
 
    $uri = "$($BaseUrl)/services/search/v2/jobs"

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
        namespace          = $namespace
    }

    Write-Host -Message "$(get-date) - Invoking-SplunkSearchJob with query: $($query)." | Out-Null
     
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
            $SplunkSearchJobResults = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -Body  @{ output_mode = "json" ; offset=$offset ; count = 0 } -SkipCertificateCheck
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
    <#
.SYNOPSIS
    Returns a list of KVstore collections registered in Splunk.

.DESCRIPTION
    Get-KVStoreCollectionList is a function that returns a list of Returns a list of KVstore
    collections registered in Splunk.

.PARAMETER BaseUrl
    A string representing a url path to the management interface of a Spunk server.
    The string is constructed with https://<hostname>:<port>
    The default port is 8089.

.PARAMETER SessionKey
    A session key composed from output of the Get-SplunkSessionKey function

.PARAMETER AppName
    The name of the splunk app (search, home, etc.) that the KVStore of interest
    are associated with.

.EXAMPLE
     Get-SplunkKVStoreCollectionList -BaseURL 'https://mysplunk:8089' -SessionKey 'Splunk asdfAasdfasdfasdfasdf....' -AppName 'search'
#>

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [Parameter(Mandatory)]
        [string]$AppName = "search"
    )

    Write-Host -Message "$(get-date) - getting KVstore collection list within `"$($AppName)`" app." | Out-Null

    $uri = "$($BaseUrl)/servicesNS/nobody/$($AppName)/storage/collections/config"

    $headers = [ordered]@{
        Authorization  = "Splunk $($SessionKey)"
        'Content-Type' = 'application/json'    
        output_mode    = 'json'
    }

    $Response = Invoke-Restmethod -Uri $uri -SkipCertificateCheck -Headers $headers -body $body -Method GET

    return $Response
}

function Add-SplunkKVStoreCollectionRecord {
    <#
.SYNOPSIS
    Add a single record into kvstore collection

.DESCRIPTION
    Add a single record into kvstore collection

.PARAMETER BaseUrl
    A string representing a url path to the management interface of a Spunk server.
    The string is constructed with https://<hostname>:<port>
    The default port is 8089.

.PARAMETER SessionKey
    A session key composed from output of the Get-SplunkSessionKey function

.PARAMETER AppName
    The name of the splunk app (search, home, etc.) that the KVStore of interest
    is associated with.

.PARAMETER CollectionName
    The name of the kvstore collection that will registered

.PARAMETER Record
    A hash table with values for fields_list entities

.EXAMPLE
     Add-SplunkKVStoreCollectionRecord -BaseURL 'https://mysplunk:8089' -SessionKey 'Splunk asdfAasdfasdfasdfasdf....' -AppName 'search' -CollectionName 'test' -Record @{
            name='David''
            message = 'Hello world!'
        }
#>

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [Parameter(Mandatory)]
        [string]$AppName = "search",
        [ValidateNotNullOrEmpty()]
        [string]$CollectionName,
        $Record
    )

    Write-Host -Message "$(get-date) - adding single record to collection named `"$($CollectionName)`" within `"$($AppName)`" app." | Out-Null

    $uri = "$($BaseUrl)/servicesNS/nobody/$($AppName)/storage/collections/data/$($CollectionName)"

    $headers = [ordered]@{
        Authorization  = "Splunk $($SessionKey)"
        'Content-Type' = 'application/json'
    }

    $body = $Record | ConvertTo-Json -Compress

    $Response = Invoke-WebRequest -Uri $uri -SkipCertificateCheck -Headers $headers -Body $body -Method Post

    return $Response
}

function Add-SplunkKVStoreCollectionRecordsBatch {
    <#
.SYNOPSIS
    Add a single record into kvstore collection

.DESCRIPTION
    Add a single record into kvstore collection

.PARAMETER BaseUrl
    A string representing a url path to the management interface of a Spunk server.
    The string is constructed with https://<hostname>:<port>
    The default port is 8089.

.PARAMETER SessionKey
    A session key composed from output of the Get-SplunkSessionKey function

.PARAMETER AppName
    The name of the splunk app (search, home, etc.) that the KVStore of interest
    is associated with.

.PARAMETER CollectionName
    The name of the kvstore collection that will registered

.PARAMETER Record
    A hash table with values for fields_list entities

.EXAMPLE
     Add-SplunkKVStoreCollectionRecordsBatch -BaseURL 'https://mysplunk:8089' -SessionKey 'Splunk asdfAasdfasdfasdfasdf....' -AppName 'search' -CollectionName 'test' -Record $Records
#>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [Parameter(Mandatory)]
        [string]$AppName = "search",
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

        $uri = "$($BaseUrl)/servicesNS/nobody/$($AppName)/storage/collections/data/$($CollectionName)/batch_save"
    
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
    <#
.SYNOPSIS
    List records in a specified kvstore collection

.DESCRIPTION
    List records in a specified kvstore collection

.PARAMETER BaseUrl
    A string representing a url path to the management interface of a Spunk server.
    The string is constructed with https://<hostname>:<port>
    The default port is 8089.

.PARAMETER SessionKey
    A session key composed from output of the Get-SplunkSessionKey function

.PARAMETER AppName
    The name of the splunk app (search, home, etc.) that the KVStore of interest
    is associated with.

.PARAMETER CollectionName
    The name of the kvstore collection that will registered

.PARAMETER Records
    A hash table with values for fields_list entities

.EXAMPLE
     Get-SplunkKVStoreCollectionRecords -BaseURL 'https://mysplunk:8089' -SessionKey 'Splunk asdfAasdfasdfasdfasdf....' -AppName 'search' -CollectionName 'test'
#>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [Parameter(Mandatory)]
        [string]$AppName = "search",
        [ValidateNotNullOrEmpty()]
        [string]$CollectionName
    )

    Write-Host -Message "$(get-date) - retrieving records from collection named `"$($CollectionName)`" within `"$($AppName)`" app." | Out-Null

    $uri = "$($BaseUrl)/servicesNS/nobody/$($AppName)/storage/collections/data/$($CollectionName)"

    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
        output_mode   = 'json'
    }

    $Response = Invoke-RestMethod -Uri $uri -SkipCertificateCheck -Headers $headers

    return $Response
}

function Remove-SplunkKVStoreCollectionRecords {
    <#
.SYNOPSIS
    Remove records in a kvstore collection

.DESCRIPTION
    Remove records in a kvstore collection

.PARAMETER BaseUrl
    A string representing a url path to the management interface of a Spunk server.
    The string is constructed with https://<hostname>:<port>
    The default port is 8089.

.PARAMETER SessionKey
    A session key composed from output of the Get-SplunkSessionKey function

.PARAMETER AppName
    The name of the splunk app (search, home, etc.) that the KVStore of interest
    is associated with.

.PARAMETER CollectionName
    The name of the kvstore collection

.EXAMPLE
     Remove-SplunkKVStoreCollectionRecords -BaseURL 'https://mysplunk:8089' -SessionKey 'Splunk asdfAasdfasdfasdfasdf....' -AppName 'search' -CollectionName 'test'
#>    
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [Parameter(Mandatory)]
        [string]$AppName = "search",
        [ValidateNotNullOrEmpty()]
        [string]$CollectionName
    )

    Write-Host -Message "$(get-date) - removing records in collection named `"$($CollectionName)`" within `"$($AppName)`" app." | Out-Null

    $uri = "$($BaseUrl)/servicesNS/nobody/$($AppName)/storage/collections/data/$($CollectionName)"

    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
    }

    $Response = Invoke-RestMethod -Uri $uri -SkipCertificateCheck -Headers $headers -Body $body -Method Delete

    return $Response
}

function Add-SplunkKVStoreCollection {
    <#
.SYNOPSIS
    Add a kvstore collection

.DESCRIPTION
    Add a kvstore collection

.PARAMETER BaseUrl
    A string representing a url path to the management interface of a Spunk server.
    The string is constructed with https://<hostname>:<port>
    The default port is 8089.

.PARAMETER SessionKey
    A session key composed from output of the Get-SplunkSessionKey function

.PARAMETER AppName
    The name of the splunk app (search, home, etc.) that the KVStore of interest
    is associated with.

.PARAMETER CollectionName
    The name of the kvstore collection

.EXAMPLE
     Add-KVStoreCollection -BaseURL 'https://mysplunk:8089' -SessionKey 'Splunk asdfAasdfasdfasdfasdf....' -AppName 'search' -CollectionName 'test'
#> 
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [Parameter(Mandatory)]
        [string]$AppName = "search",
        [string]$CollectionName
    )

    $ProgressPreference = 'SilentlyContinue'

    Write-Host -Message "$(get-date) - creating KVstore collection named `"$($CollectionName)`" within `"$($AppName)`" app." | Out-Null

    $uri = "$($BaseUrl)/servicesNS/nobody/$($AppName)/storage/collections/config"

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
    <#
.SYNOPSIS
    Set the schema associated with a kvstore collection

.DESCRIPTION
    Set the schema associated with a kvstore collection

.PARAMETER BaseUrl
    A string representing a url path to the management interface of a Spunk server.
    The string is constructed with https://<hostname>:<port>
    The default port is 8089.

.PARAMETER SessionKey
    A session key composed from output of the Get-SplunkSessionKey function

.PARAMETER AppName
    The name of the splunk app (search, home, etc.) that the KVStore of interest
    is associated with.

.PARAMETER CollectionName
    The name of the kvstore collection

.PARAMETER CollectionSchema
    A hash containing desired elements of collection schema.  See example.

.EXAMPLE
    Set-SplunkKVStoreCollectionSchema -BaseURL 'https://mysplunk:8089' -SessionKey 'Splunk asdfAasdfasdfasdfasdf....' -AppName 'search' -CollectionName 'test' -CollectionSchema  @{
            'field.id' = 'number'
            'field.name' = 'string'
            'field.message' = 'string'
            'accelerated_fields.my_accel' = '{"id": 1}'
        }
#> 
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [Parameter(Mandatory)]
        [string]$AppName = "search",
        [ValidateNotNullOrEmpty()]
        [string]$CollectionName,
        $CollectionSchema
    )

    Write-Host -Message "$(get-date) - setting schema for KVstore collection named `"$($CollectionName)`" within `"$($AppName)`" app." | Out-Null

    $uri = "$($BaseUrl)/servicesNS/nobody/$($AppName)/storage/collections/config/$($CollectionName)"

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
    <#
.SYNOPSIS
    Remove a kvstore collection

.DESCRIPTION
    Remove a kvstore collection

.PARAMETER BaseUrl
    A string representing a url path to the management interface of a Spunk server.
    The string is constructed with https://<hostname>:<port>
    The default port is 8089.

.PARAMETER SessionKey
    A session key composed from output of the Get-SplunkSessionKey function

.PARAMETER AppName
    The name of the splunk app (search, home, etc.) that the KVStore of interest
    is associated with.

.PARAMETER CollectionName
    The name of the kvstore collection

.EXAMPLE
    Remove-SplunkKVStoreCollection -BaseURL 'https://mysplunk:8089' -SessionKey 'Splunk asdfAasdfasdfasdfasdf....' -AppName 'search' -CollectionName 'test'
#> 
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [Parameter(Mandatory)]
        [string]$AppName = "search",
        [ValidateNotNullOrEmpty()]
        [string]$CollectionName
    )

    Write-Verbose -Message "$(get-date) - removing collection named `"$($CollectionName)`" within `"$($AppName)`" app."

    $uri = "$($BaseUrl)/servicesNS/nobody/$($AppName)/storage/collections/config/$($CollectionName)"

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
        [string]$SessionKey
    )

    $uri = "$($BaseUrl)/services/data/transforms/lookups"

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

    $uri = "$($BaseUrl)/services/data/transforms/lookups"
    
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
        [ValidateNotNullOrEmpty()]
        [string]$LookupName
    )    

    Write-Host -Message "$(get-date) - removing transform having name `"$($LookupName)`"." | Out-Null

    $uri = "$($BaseUrl)/services/data/transforms/lookups/$($LookupName)"
    
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
        [ValidateNotNullOrEmpty()]
        [string]$LookupName
    )    

    Write-Verbose -Message "$(get-date) - removing transform having name `"$($LookupName)`"."

    $uri = "$($BaseUrl)/services/data/transforms/lookups/$($LookupName)"
    
    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
    }

    $WebRequest = Invoke-RestMethod -SkipCertificateCheck -Uri $uri -Headers $headers -Method Get

    return $WebRequest 
}
