function Get-SplunkSessionKey
{   
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string[]]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        $Credential
    )

    write-host "$(get-date) - Attempting to exchnage Splunk credential for web session key."

    $body = @{
        username = $Credential.username
        password = $Credential.GetNetworkCredential().Password;
    }

    try
    {
        $WebRequest = Invoke-RestMethod -Uri "$($BaseUrl)/services/auth/login" -Body $body -SkipCertificateCheck -ContentType 'application/x-www-form-urlencoded' -Method Post
    }
    catch
    {
        Write-Warning -Message "An exception occured with text: $($_.Exception)"
        return $WebRequest
    }

    return $WebRequest.response.sessionKey
}

function Get-KVStoreCollectionList
{
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
     Get-KVStoreCollectionList -BaseURL 'https://mysplunk:8089' -SessionKey 'Splunk asdfAasdfasdfasdfasdf....' -AppName 'search'
#>

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [Parameter(Mandatory)]
        [string]$AppName="search"
    )

    Write-Verbose -Message "$(get-date) - getting KVstore collection list within `"$($AppName)`" app."

    $uri = "$($BaseUrl)/servicesNS/nobody/$($AppName)/storage/collections/config"

    $headers = [ordered]@{
        Authorization = "$($SessionKey)"
        'Content-Type' = 'application/json'    
        output_mode = 'json'
    }

    try
    {
        $WebRequest = Invoke-WebRequest -Uri $uri -SkipCertificateCheck -Headers $headers -body $body -Method GET
    }
    catch
    {
        Write-Warning -Message "An exception occured with text: $($_.Exception)"
        return $WebRequest
    }

    return $WebRequest 
}

function Add-SplunkTransformLookup
{
<#
.SYNOPSIS
    Add a KVstore transform entry (lookup) to a specified app in Splunk.

.DESCRIPTION
    Add a KVstore transform entry (lookup) to a specified app in Splunk.

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

.PARAMETER TransformSchema
    A hash table with values for fields_list, type, external_type and name.

.EXAMPLE
     Add-KVStoreTransform -BaseURL 'https://mysplunk:8089' -SessionKey 'Splunk asdfAasdfasdfasdfasdf....' -AppName 'search' -CollectionName 'test' -TransformSchema @{
            'fields_list' = '_key, id, name, message'
            'type' = 'extenal'
            'external_type' = 'kvstore'
            'name' = 'test'
        }
#>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [Parameter(Mandatory)]
        [string]$AppName="search",
        [ValidateNotNullOrEmpty()]
        [string]$CollectionName,
        $TransformSchema
    )    

    Write-Verbose -Message "$(get-date) - adding transform for KVstore collection named `"$($CollectionName)`" within `"$($AppName)`" app."

    <# Example TransformSchema:
        @{
            'fields_list' = '_key, id, name, message'
            'type' = 'extenal'
            'external_type' = 'kvstore'
            'name' = $CollectionName
        }
    #>

    $uri = "$($BaseUrl)/servicesNS/admin/$($AppName)/data/transforms/lookups"
    
    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
    }

    $body = $TransformSchema

    try
    {
        $WebRequest = Invoke-WebRequest -Uri $uri -SkipCertificateCheck -Headers $headers -Body $body -Method Post
    }
    catch
    {
        Write-Warning -Message "An exception occured with text: $($_.Exception)"
        return $WebRequest
    }

    return $WebRequest 
}

function Add-SplunkCollectionRecord
{
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
     Add-KVStoreRecord -BaseURL 'https://mysplunk:8089' -SessionKey 'Splunk asdfAasdfasdfasdfasdf....' -AppName 'search' -CollectionName 'test' -Record @{
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
        [string]$AppName="search",
        [ValidateNotNullOrEmpty()]
        [string]$CollectionName,
        $Record
    )

    Write-Verbose -Message "$(get-date) - adding single record to collection named `"$($CollectionName)`" within `"$($AppName)`" app."

    $uri = "$($BaseUrl)/servicesNS/nobody/$($AppName)/storage/collections/data/$($CollectionName)"

    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
        'Content-Type' = 'application/json'
    }

    $body = $Record | ConvertTo-Json -Compress

    try
    {
        $WebRequest = Invoke-WebRequest -Uri $uri -SkipCertificateCheck -Headers $headers -Body $body -Method Post
    }
    catch
    {
        Write-Warning -Message "An exception occured with text: $($_.Exception)"
        return $WebRequest
    }

    return $WebRequest 
}

function Get-SplunkCollectionRecords
{
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
     Get-KVStoreRecords -BaseURL 'https://mysplunk:8089' -SessionKey 'Splunk asdfAasdfasdfasdfasdf....' -AppName 'search' -CollectionName 'test'
#>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [Parameter(Mandatory)]
        [string]$AppName="search",
        [ValidateNotNullOrEmpty()]
        [string]$CollectionName
    )

    Write-Verbose -Message "$(get-date) - retrieving records from collection named `"$($CollectionName)`" within `"$($AppName)`" app."

    $uri = "$($BaseUrl)/servicesNS/nobody/$($AppName)/storage/collections/data/$($CollectionName)"

    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
        output_mode = 'json'
    }

    try
    {
        $WebRequest = Invoke-WebRequest -Uri $uri -SkipCertificateCheck -Headers $headers
    } 
    catch
    {
        Write-Warning -Message "An exception occured with text: $($_.Exception)"
        return $WebRequest
    }

    return $WebRequest 
}

function Add-SplunkCollectionRecordsBatch
{
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
     Add-KVStoreRecordBatch -BaseURL 'https://mysplunk:8089' -SessionKey 'Splunk asdfAasdfasdfasdfasdf....' -AppName 'search' -CollectionName 'test' -Record $Records
#>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [Parameter(Mandatory)]
        [string]$AppName="search",
        [ValidateNotNullOrEmpty()]
        [string]$CollectionName,
        $Records
    )

    Write-Verbose -Message "$(get-date) - adding array of records in collection named `"$($CollectionName)`" within `"$($AppName)`" app."

    $uri = "$($BaseUrl)/servicesNS/nobody/$($AppName)/storage/collections/data/$($CollectionName)/batch_save"

    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
        'Content-Type' = 'application/json'
    }
    
    $body = $Records | ConvertTo-Json -Compress

    try
    {
        $WebRequest = Invoke-WebRequest -Uri $uri -SkipCertificateCheck -Headers $headers -Body $body -Method Post
    }
    catch
    {
        Write-Warning -Message "An exception occured with text: $($_.Exception)"
        return $WebRequest
    }

    return $WebRequest
}

function Remove-SplunkCollectionRecords
{
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
     Remove-KVStoreRecords -BaseURL 'https://mysplunk:8089' -SessionKey 'Splunk asdfAasdfasdfasdfasdf....' -AppName 'search' -CollectionName 'test'
#>    
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [Parameter(Mandatory)]
        [string]$AppName="search",
        [ValidateNotNullOrEmpty()]
        [string]$CollectionName
    )

    Write-Verbose -Message "$(get-date) - removing records in collection named `"$($CollectionName)`" within `"$($AppName)`" app."

    $uri = "$($BaseUrl)/servicesNS/nobody/$($AppName)/storage/collections/data/$($CollectionName)"

    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
    }

    try
    {
        $WebRequest = Invoke-WebRequest -Uri $uri -SkipCertificateCheck -Headers $headers -Body $body -Method Delete
    }
    catch
    {
        Write-Warning -Message "An exception occured with text: $($_.Exception)"
        return $WebRequest
    }

    return $WebRequest 
}

function Remove-SplunkCollection
{
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
     Remove-KVStoreCollection -BaseURL 'https://mysplunk:8089' -SessionKey 'Splunk asdfAasdfasdfasdfasdf....' -AppName 'search' -CollectionName 'test'
#> 
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,
        [ValidateNotNullOrEmpty()]
        [string]$SessionKey,
        [Parameter(Mandatory)]
        [string]$AppName="search",
        [ValidateNotNullOrEmpty()]
        [string]$CollectionName
    )

    Write-Verbose -Message "$(get-date) - removing collection named `"$($CollectionName)`" within `"$($AppName)`" app."

    $uri = "$($BaseUrl)/servicesNS/nobody/$($AppName)/storage/collections/config/$($CollectionName)"

    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
    }

    try
    {
        $WebRequest = Invoke-WebRequest -Uri $uri -SkipCertificateCheck -Headers $headers -Body $body -Method Delete
    }
    catch
    {
        Write-Warning -Message "An exception occured with text: $($_.Exception)"
        return $WebRequest
    }

    return $WebRequest    
}

function Add-SplunkCollection
{
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
        [string]$AppName="search",
        [string]$CollectionName
    )

    $ProgressPreference = 'SilentlyContinue'

    write-verbose -Message "$(get-date) - creating KVstore collection named `"$($CollectionName)`" within `"$($AppName)`" app."

    $uri = "$($BaseUrl)/servicesNS/nobody/$($AppName)/storage/collections/config"

    $headers = [ordered]@{
        Authorization = "Splunk $($sessionKey)"
        'Content-Type' = 'application/x-www-form-urlencoded'
    }

    $body = @{
        name = $CollectionName
    } 

    write-verbose -Message "$(get-date) - invoking webrequest to url $($uri) with header of $($headers) and body of $($body)"    

    try
    {
        $WebRequest = Invoke-WebRequest -Uri $uri -SkipCertificateCheck -Headers $headers -Body $body -Method Post
    } 
    catch
    {
        Write-Warning -Message "An exception occured with text: $($_.Exception)"
        return $WebRequest
    }

    return $WebRequest
}

function Set-SplunkCollectionSchema
{
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
     Set-KVStoreSchema -BaseURL 'https://mysplunk:8089' -SessionKey 'Splunk asdfAasdfasdfasdfasdf....' -AppName 'search' -CollectionName 'test' -CollectionSchema  @{
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
        [string]$AppName="search",
        [ValidateNotNullOrEmpty()]
        [string]$CollectionName,
        $CollectionSchema
    )

    write-verbose -Message "$(get-date) - setting schema for KVstore collection named `"$($CollectionName)`" within `"$($AppName)`" app."

    $uri = "$($BaseUrl)/servicesNS/nobody/$($AppName)/storage/collections/config/$($CollectionName)"

    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
        Accept = 'application/json'
        'Content-Type' = 'application/json'
    }

    $body = $CollectionSchema 

    try
    {
        $WebRequest = Invoke-WebRequest -Uri $uri -SkipCertificateCheck -Headers $headers -Body $body -Method Post
    }
    catch
    {
        Write-Warning -Message "An exception occured with text: $($_.Exception)"
        return $WebRequest
    }

    return $WebRequest
}

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
 
    # This will allow for self-signed SSL certs to work
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12   #(ssl3,SystemDefault,Tls,Tls11,Tls12)

    $uri = "$($BaseUrl)/services/search/jobs"

    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
        Accept = 'application/json'
        'Content-Type' = 'application/json'
    }     

    $body = @{
        search = $query
        output_mode = "csv"
        count = "0"
        exec_mode = "normal"
        max_count = "0"
    }
     
     $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body

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
 
    # This will allow for self-signed SSL certs to work
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12   #(ssl3,SystemDefault,Tls,Tls11,Tls12)
 
    $uri = "$($BaseUrl)/services/search/jobs/$($jobsid)"

    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
        Accept = 'application/json'
        'Content-Type' = 'application/json'
    }     

    $body = @{
        output_mode = "csv"
        count = "0"
        max_count = "0"
        exec_mode = "normal"
        offset = $offset
    }

    $response = Invoke-RestMethod -Method Post -Uri $url -Headers $headers -Body $body
    return $response
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
        [int]$offset=0
   )
 
    # This will allow for self-signed SSL certs to work
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12   #(ssl3,SystemDefault,Tls,Tls11,Tls12)
 
    $uri = "$($BaseUrl)/services/search/jobs/$($jobsid)/results/"

    $headers = [ordered]@{
        Authorization = "Splunk $($SessionKey)"
        Accept = 'application/json'
        'Content-Type' = 'application/json'
    }     

    $body = @{
        output_mode = "csv"
        count = "0"
        max_count = "0"
        exec_mode = "normal"
        offset = $offset
    }
     
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -Body $body

    return $response

}
 