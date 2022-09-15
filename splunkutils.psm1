
<# PUBLIC AUTHENTICATION FUNCTIONS #>
function Get-SplunkSessionKey {   
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string[]]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        $Credential
    )

    write-verbose "$(get-date) - Attempting to exchnage Splunk credential for web session key."

    $body = @{
        username = $Credential.username
        password = $Credential.GetNetworkCredential().Password;
    }

    try {
        $WebRequest = Invoke-RestMethod -Uri "$($BaseUrl)/services/auth/login" -Body $body -SkipCertificateCheck -ContentType 'application/x-www-form-urlencoded' -Method Post
    }
    catch {
        Write-Warning -Message "An exception occured with text: $($_.Exception)"
        return $WebRequest
    }

    return $WebRequest.response.sessionKey
}

<# PUBLIC SEARCH FUNCTIONS #>
function Read-SplunkSearchResults {

    [CmdletBinding()]
    param (
        [ValidateNotNullOrEmpty()]
        [string]$sessionKey, 
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl, 
        [ValidateNotNullOrEmpty()]
        [string]$query
    )

    try {
        $SplunkSearchJobResponse = Invoke-SplunkSearchJob -SessionKey $SplunkSessionKey -BaseUrl $BaseUrl -query $query
    }
    catch {
        write-verbose "$(get-date) - Exiting after exception occured in Invoke-SplunkSearchJob function. Exception Message:"
        write-verbose "$($error[0].Exception.Message)"
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
            write-verbose "$(get-date) - Exiting after exception occured in Get-SplunkSearchJobStatus function. Exception Message:"
            write-verbose "$($error[0].Exception.Message)"
            break        
        }
    
        $isDone = ((([xml] $SplunkSearchJobStatusResponse.InnerXml).entry.content.dict.key) | Where-Object { $_.Name -eq "isDone" }).'#text'
        $dispatchState = [string]((([xml] $SplunkSearchJobStatusResponse.InnerXml).entry.content.dict.key) | Where-Object { $_.Name -eq "dispatchState" }).'#text'
    
        write-verbose "$(get-date) - Search with id [$($SearchJobSid)] has status [$($dispatchState)]."         
    
    } while ($isDone -eq 0)
    $runDuration = [decimal]((([xml] $SplunkSearchJobStatusResponse.InnerXml).entry.content.dict.key) | Where-Object { $_.Name -eq "runDuration" }).'#text'
    $resultCount = [int]((([xml] $SplunkSearchJobStatusResponse.InnerXml).entry.content.dict.key) | Where-Object { $_.Name -eq "resultCount" }).'#text'
    
    write-verbose "$(get-date) - Search with id [$($SearchJobSid)] completed having result count [$($resultCount)] after runtime duration of [$($runDuration)] seconds."         
    
    # gather search job results
    $events = New-Object System.Collections.ArrayList
    do {
        
        # get batch of events
        try {
            $SplunkSearchJobResults = Get-SplunkSearchJobResults -sessionKey $SplunkSessionKey -BaseURL $BaseUrl -jobsid $SearchJobSid -offset $events.count
        }
        catch {
            write-verbose "$(get-date) - Exiting after exception occured in Get-SplunkSearchJobResults. Exception Message:"
            write-verbose "$($error[0].Exception.Message)"
            break
        }
    
        # append batch of events to results array
        foreach ($result in $SplunkSearchJobResults.results) {
            $events.Add($result) | out-null
        }
    
        # give the user an idea of progress toward completion.
        write-verbose "$(get-date) - Downloaded search results [$($events.count)] of [$($resultCount)]."         
    
    } while ($events.count -ne $resultCount)

    return $events

}

<# PRIVATE SEARCH FUNCTIONS #>
function Invoke-SplunkSearchJob {

    [CmdletBinding()]
    param (
        [ValidateNotNullOrEmpty()]
        [string]$sessionKey, 
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl, 
        [ValidateNotNullOrEmpty()]
        [string]$query
    )
 
    $uri = "$($BaseUrl)/services/search/jobs"

    $headers = [ordered]@{
        Authorization  = "Splunk $($SessionKey)"
        Accept         = 'application/json'
        'Content-Type' = 'application/json'
    }     

    $body = @{
        search      = $query
        output_mode = "csv"
        count       = "0"
        exec_mode   = "normal"
        max_count   = "0"
    }
     
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -SkipCertificateCheck

    return $response
}
 
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
  
    $uri = "$($BaseUrl)/services/search/jobs/$($jobsid)"

    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
    }     

    $Response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -SkipCertificateCheck

    return $Response

}
 
function Get-SplunkSearchJobResults {

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$sessionKey,
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$jobsid,
        [ValidateNotNullOrEmpty()]
        [int]$offset = 0
    )
  
    $uri = "$($BaseUrl)/services/search/jobs/$($jobsid)/results/"

    $headers = [ordered]@{
        Authorization  = "Splunk $($SessionKey)"
        Accept         = 'application/json'
        'Content-Type' = 'application/json'
    }     

    $body = @{
        output_mode = "json"
        count       = "0"
        offset      = $offset
    }
     
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -Body $body -SkipCertificateCheck

    return $response

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

    Write-Verbose -Message "$(get-date) - getting KVstore collection list within `"$($AppName)`" app."

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

    Write-Verbose -Message "$(get-date) - adding single record to collection named `"$($CollectionName)`" within `"$($AppName)`" app."

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

        write-host -Message "$(get-date) - adding elements $($lbound) to $($ubound) of array to collection."

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

    Write-Verbose -Message "$(get-date) - retrieving records from collection named `"$($CollectionName)`" within `"$($AppName)`" app."

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

    Write-Verbose -Message "$(get-date) - removing records in collection named `"$($CollectionName)`" within `"$($AppName)`" app."

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

    write-verbose -Message "$(get-date) - creating KVstore collection named `"$($CollectionName)`" within `"$($AppName)`" app."

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

    write-verbose -Message "$(get-date) - setting schema for KVstore collection named `"$($CollectionName)`" within `"$($AppName)`" app."

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

    Write-Verbose -Message "$(get-date) - removing transform having name `"$($LookupName)`"."

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
