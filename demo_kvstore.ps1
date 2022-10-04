$splunk_server = "win-9iksdb1vgmj.mshome.net"
$splunk_rest_port = "8089"
$BaseUrl = "https://$($splunk_server):$($splunk_rest_port)"
$script_start = get-date

<# Toggle Global Verbosity Level
$VerbosePreference = "Continue"
$VerbosePreference = "SilentlyContinue"
#>


# import module providing for various Splunk related functions
import-module -name "C:\Apps\splunkutils\splunkutils.psm1" -Force

# gather username/password for Splunk
if (-not($mycred)) { $mycred = Get-Credential -Message "Enter credential for interacting with $($BaseUrl)." }

# trade username/password for session key
try {
    $SplunkSessionKey = Get-SplunkSessionKey -Credential $myCred -BaseUrl $BaseUrl
}
catch {
    Write-Error "$($error[0].Exception.Message)"
    break   
}

# define properties of collection to create, update, etc.  
$CollectionSchema = @{
    'field.id'                    = 'number'    
    'field.user'                  = 'string'
    'field.message'               = 'string'
    'field.message_date'          = 'time'
    'field._time'                 = 'time'    
    'accelerated_fields.my_accel' = '{"id": 1}'
} 
# note: possible collection schema item types include (array|number|boolean|time|string|cidr)

$AppName = 'search'
$CollectionName = "test_collection_$($env:USERNAME)_3"

$TransformSchema = @{
    'fields_list'   = '_key, id, user, message, message_date, _time'
    'external_type' = 'kvstore'
    'name'          = $CollectionName
    'collection'    = $CollectionName
}

# produce some random records to place in collection once created
$Records = New-Object System.Collections.ArrayList
for ($i = 1; $i -le 12345; $i++) {

    $Record = [ordered]@{
        id           = $i
        name         = "$($env:USERNAME)-$($i)"
        message      = "Hello World $($i)!"
        message_date = (New-TimeSpan -Start "01/01/1970" -End $(get-date)).TotalSeconds
        _time        = (New-TimeSpan -Start "01/01/1970" -End $(get-date)).TotalSeconds        
    }
    $Records.add([pscustomobject]$Record) | out-null
}

# get list of kvstore collections in specified app
try {
    $collections = Get-SplunkKVStoreCollectionList -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -AppName $AppName
}
catch {
    Write-Error "$($error[0].Exception.Message)"
    break        
}

# if target collection not present in list then prepare it
if ($CollectionName -notin $collections.title) {
 
    write-output "$(get-date) - Collection [$($CollectionName)] not present in [$($AppName)] app.  Preparing it."


    # add new collection  
    try {
        $SplunkKVStoreCollection = Add-SplunkKVStoreCollection -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -AppName $AppName -CollectionName $CollectionName
    }
    catch {
        Write-Error "$($error[0].Exception.Message)"
        break        
    }
    write-output "$(get-date) - Collection [$($CollectionName)] created in [$($AppName)] app."


    # define collection schema
    try {
        $SplunkKVStoreCollectionSchema = Set-SplunkKVStoreCollectionSchema -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -AppName $AppName -CollectionName $CollectionName -CollectionSchema $CollectionSchema

    }
    catch {
        Write-Error "$($error[0].Exception.Message)"
        break         
    }
    write-output "$(get-date) - Collection schema set for [$($CollectionName)] in [$($AppName)] app."

}
else {
    write-output "$(get-date) - Collection [$($CollectionName)] already present in [$($AppName)] app."
}


# create the transform lookup if it does not exist
write-output "$(get-date) - Invoking Get-SplunkTransformLookup function to dermine if lookup exists."
try {
    Get-SplunkTransformLookup -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -LookupName $CollectionName | Out-Null
}
catch {
    write-output "$(get-date) - Invoking Add-SplunkTransformLookup function."    
    try {
        Add-SplunkTransformLookup -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -User "nobody" -AppName $AppName -TransformSchema $TransformSchema | Out-Null
    }
    catch {
        Write-Error "$($error[0].Exception.Message)"
        break                 
    }
}


# add multiple kvstore records in specified collection in specified app (can also Add-SplunkKVStoreCollectionRecord for a single record)
write-output "$(get-date) - Invoking Add-SplunkKVStoreCollectionRecordsBatch function with recordset having $($records.count) entries."
try {
    Add-SplunkKVStoreCollectionRecordsBatch -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -AppName $AppName -CollectionName $CollectionName -Records $Records | Out-Null
}
catch {
    Write-Error "$($error[0].Exception.Message)"
    break           
}



# get kvstore records in specified collection in specified app
write-output "$(get-date) - Invoking Get-SplunkKVStoreCollectionRecords function."
try {
    $SplunkKVStoreCollectionRecords = Get-SplunkKVStoreCollectionRecords -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -AppName $AppName -CollectionName $CollectionName
}
catch {
    Write-Error "$($error[0].Exception.Message)"
    break           
}
write-output "$(get-date) - Get-SplunkKVStoreCollectionRecords returned [$($SplunkKVStoreCollectionRecords.count)] records."    


<####  OTHER OPERATIONS ####

# List all transform lookups
Get-SplunkTransformLookups -sessionKey $SplunkSessionKey -BaseURL $BaseUrl

# Remove kvstore records in specified collection in specified app (does not return anything)
Remove-SplunkKVStoreCollectionRecords -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -AppName $AppName -CollectionName $CollectionName

# Remove kvstore collection in specified app (does not return anything)
Remove-SplunkKVStoreCollection -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -AppName $AppName -CollectionName $CollectionName

# Remove transform lookup (does not return anything except error)
Remove-SplunkTransformLookup -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -LookupName $CollectionName

###### END CLEANUP OPERATINS ####>

# display script execution runtime summary
$timespan = New-TimeSpan -Start $script_start
write-output "$(get-date) - Script execution completed with runtime duration of [$($timespan)]."