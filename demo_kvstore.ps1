$splunk_server = "win-9iksdb1vgmj.mshome.net"
$splunk_rest_port = "8089"
$BaseUrl = "https://$($splunk_server):$($splunk_rest_port)"
$script_start = get-date

# import module providing for various Splunk related functions
import-module -name "C:\Apps\splunkutils\splunkutils.psm1" -Force

# gather username/password for Splunk
if (-not($mycred)) { $mycred = Get-Credential -Message "Enter credential for interacting with $($BaseUrl)." }

# trade username/password for session key
$SplunkSessionKey = Get-SplunkSessionKey -Credential $myCred -BaseUrl $BaseUrl

# define properties of collection to create, update, etc.  
$CollectionSchema = @{
    'field.id'                    = 'number'    
    'field.user'                  = 'string'
    'field.message'               = 'string'
    'field.message_date'          = 'time'
    'accelerated_fields.my_accel' = '{"id": 1}'
} 
# note: possible collection schema item types include (array|number|boolean|time|string|cidr)

$AppName = 'search'
$CollectionName = "test_collection_$($env:USERNAME)_3"

$TransformSchema = @{
    'fields_list'   = '_key, id, user, message, message_date'
    'type'          = 'extenal'
    'external_type' = 'kvstore'
    'name'          = $CollectionName
}

# produce some random records to place in collection once created
$Records = New-Object System.Collections.ArrayList
for ($i = 0; $i -le 10; $i++) {

    $message_date_random = (get-date).AddMinutes($(Get-Random -Minimum -500 -Maximum 500))

    $Record = [ordered]@{
        id           = $i
        name         = "$($env:USERNAME)-$($i)"
        message      = "Hello World $($i)!"
        message_date = $message_date_random
    }
    $Records.add([pscustomobject]$Record) | out-null
}

# get list of kvstore collections in specified app
try {
    $collections = Get-SplunkKVStoreCollectionList -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -AppName $AppName
}
catch {
    write-output "$(get-date) - Exiting after exception occured in Get-SplunkKVStoreCollectionList function. Exception Message:"
    write-output "$($error[0].Exception.Message)"
    break        
}

# perform collection prepration actions if not already defined
if ($CollectionName -notin $collections.title) {
 
    write-output "$(get-date) - Collection [$($CollectionName)] not present in [$($AppName)] app.  Preparing it."

    # add new collection  
    try {
        $SplunkKVStoreCollection = Add-SplunkKVStoreCollection -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -AppName $AppName -CollectionName $CollectionName
    }
    catch {
        write-output "$(get-date) - Exiting after exception occured in Add-SplunkKVStoreCollection function. Exception Message:"
        write-output "$($error[0].Exception.Message)"
        break        
    }
    write-output "$(get-date) - Collection [$($CollectionName)] created in [$($AppName)] app."

    # define collection schema
    try {
        $SplunkKVStoreCollectionSchema = Set-SplunkKVStoreCollectionSchema -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -AppName $AppName -CollectionName $CollectionName -CollectionSchema $CollectionSchema

    }
    catch {
        write-output "$(get-date) - Exiting after exception occured in Set-SplunkKVStoreCollectionSchema function. Exception Message:"
        write-output "$($error[0].Exception.Message)"
        break        
    }
    write-output "$(get-date) - Collection schema set for [$($CollectionName)] in [$($AppName)] app."

}
else {
    write-output "$(get-date) - Collection [$($CollectionName)] already present in [$($AppName)] app."
}


# add single kvstore record in specified collection in specified app
write-output "$(get-date) - Invoking Add-SplunkKVStoreCollectionRecord function."
try {
    $SplunkKVStoreCollectionRecord = Add-SplunkKVStoreCollectionRecord -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -AppName $AppName -CollectionName $CollectionName -Record $Records[0]
}
catch {
    write-output "$(get-date) - Exiting after exception occured in Add-SplunkKVStoreCollectionRecord function. Exception Message:"
    write-output "$($error[0].Exception.Message)"
    break            
}
if ($SplunkKVStoreCollectionRecord.StatusCode -notmatch "^(200|201)$") { 
    write-output "$(get-date) - Unexpected status code returned from Add-SplunkKVStoreCollectionRecord function. Exiting."
    break 
}
else {
    write-output "$(get-date) - Add-SplunkKVStoreCollectionRecord completed with status description [$($SplunkKVStoreCollectionRecord.StatusDescription)]."    
}


# get kvstore records in specified collection in specified app
write-output "$(get-date) - Invoking Get-SplunkKVStoreCollectionRecords function."
try {
    $SplunkKVStoreCollectionRecords = Get-SplunkKVStoreCollectionRecords -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -AppName $AppName -CollectionName $CollectionName
}
catch {
    write-output "$(get-date) - Exiting after exception occured in Get-SplunkKVStoreCollectionRecords function. Exception Message:"
    write-output "$($error[0].Exception.Message)"
    break                
}
write-output "$(get-date) - Get-SplunkKVStoreCollectionRecords returned [$($SplunkKVStoreCollectionRecords.count)] records."    


# add multiple kvstore records in specified collection in specified app
# todo -- there is a limit on count of records you can add so .... deal with that
write-output "$(get-date) - Invoking Add-SplunkKVStoreCollectionRecordsBatch function."
try {
    $SplunkKVStoreCollectionRecordsBatch = Add-SplunkKVStoreCollectionRecordsBatch -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -AppName $AppName -CollectionName $CollectionName -Records $Records
}
catch {
    write-output "$(get-date) - Exiting after exception occured in Add-SplunkKVStoreCollectionRecordsBatch function. Exception Message:"
    write-output "$($error[0].Exception.Message)"
    break                
}
$SplunkKVStoreCollectionRecordsBatch = $SplunkKVStoreCollectionRecordsBatch.content | ConvertFrom-Json
write-output "$(get-date) - Add-SplunkKVStoreCollectionRecordsBatch returned [$($SplunkKVStoreCollectionRecordsBatch.count)] records."


# get kvstore records in specified collection in specified app
write-output "$(get-date) - Invoking Get-SplunkKVStoreCollectionRecords function."
try {
    $SplunkKVStoreCollectionRecords = Get-SplunkKVStoreCollectionRecords -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -AppName $AppName -CollectionName $CollectionName
}
catch {
    write-output "$(get-date) - Exiting after exception occured in Get-SplunkKVStoreCollectionRecords function. Exception Message:"
    write-output "$($error[0].Exception.Message)"
    break                
}
write-output "$(get-date) - Get-SplunkKVStoreCollectionRecords returned [$($SplunkKVStoreCollectionRecords.count)] records."  


# remove kvstore records in specified collection in specified app (does not return anything)
write-output "$(get-date) - Invoking Remove-SplunkKVStoreCollectionRecords function."  
$SplunkKVStoreCollectionRecords = Remove-SplunkKVStoreCollectionRecords -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -AppName $AppName -CollectionName $CollectionName


# get kvstore records in specified collection in specified app
write-output "$(get-date) - Invoking Get-SplunkKVStoreCollectionRecords function."
try {
    $SplunkKVStoreCollectionRecords = Get-SplunkKVStoreCollectionRecords -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -AppName $AppName -CollectionName $CollectionName
}
catch {
    write-output "$(get-date) - Exiting after exception occured in Get-SplunkKVStoreCollectionRecords function. Exception Message:"
    write-output "$($error[0].Exception.Message)"
    break                
}
write-output "$(get-date) - Get-SplunkKVStoreCollectionRecords returned [$($SplunkKVStoreCollectionRecords.count)] records."  


# remove kvstore collection in specified app (does not return anything)
write-output "$(get-date) - Invoking Remove-SplunkKVStoreCollection function."
try {
    $SplunkKVStoreCollection = Remove-SplunkKVStoreCollection -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -AppName $AppName -CollectionName $CollectionName
} catch {
    write-output "$(get-date) - Exiting after exception occured in Remove-SplunkKVStoreCollection function. Exception Message:"
    write-output "$($error[0].Exception.Message)"
    break       
}

# display script execution runtime summary
$timespan = New-TimeSpan -Start $script_start
write-output "$(get-date) - Script execution completed with runtime duration of [$($timespan)]."