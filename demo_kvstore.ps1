$splunk_server = "win-9iksdb1vgmj.mshome.net"
$splunk_rest_port = "8089"
$BaseUrl = "https://$($splunk_server):$($splunk_rest_port)"
$script_start = get-date

<# Toggle global verbosity Level
$VerbosePreference = 'Continue'
$VerbosePreference = 'SilentlyContinue'
#>

# import module providing for various Splunk related functions
import-module -name "C:\Apps\splunkutils\splunkutils.psm1" -Force

# gather username/password for Splunk from user
if (-not($mycred)) { $mycred = Get-Credential -Message "Enter credential for interacting with $($BaseUrl)." }

# trade username/password for session key
$SplunkSessionKey = Get-SplunkSessionKey -Credential $myCred -BaseUrl $BaseUrl

<#
# alternatively you can present a session key from user access token (credential) stored as securestring
$credfile_path = 'C:\apps\credstore\splunk_dev_token.txt'  

# check to see if the storage file for secret exists
if (-not (test-path -Path $credfile_path)) {
    # allow for storage (or reset) of secret
    if (Test-Path -path $credfile_path) { remove-item -path $credfile_path -Force }  # useful only when resetting credential interactively
    Read-Host -Prompt "Enter secret to store as secure string in $($credfile_path): " -AsSecureString | ConvertFrom-SecureString | Out-File -FilePath $credfile_path
} 

# read the secret from storage file and convert to secure string object
$secure_string = get-content -path $credfile_path | ConvertTo-SecureString

# convert the secure string to plain text
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure_string)
$SplunkSessionKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
#>

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

$Namespace = 'search'
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
    $collections = Get-SplunkKVStoreCollectionList -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -Namespace $Namespace
}
catch {
    Write-Error "$($error[0].Exception.Message)"
    break        
}

# if target collection not present in list then prepare it
if ($CollectionName -notin $collections.title) {
 
    write-output "$(get-date) - Collection [$($CollectionName)] not present in [$($Namespace)] namespace.  Preparing it."


    # add new collection  
    try {
        $SplunkKVStoreCollection = Add-SplunkKVStoreCollection -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -Namespace $Namespace -CollectionName $CollectionName
    }
    catch {
        Write-Error "$($error[0].Exception.Message)"
        break        
    }
    write-output "$(get-date) - Collection [$($CollectionName)] created in [$($Namespace)] namespace."


    # define collection schema
    try {
        $SplunkKVStoreCollectionSchema = Set-SplunkKVStoreCollectionSchema -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -Namespace $Namespace -CollectionName $CollectionName -CollectionSchema $CollectionSchema

    }
    catch {
        Write-Error "$($error[0].Exception.Message)"
        break         
    }
    write-output "$(get-date) - Collection schema set for [$($CollectionName)] in [$($Namespace)] namespace."

}
else {
    write-output "$(get-date) - Collection [$($CollectionName)] already present in [$($Namespace)] namespeace."
}


# create the transform lookup if it does not exist
write-output "$(get-date) - Invoking Get-SplunkTransformLookup function to dermine if lookup exists."
try {
    Get-SplunkTransformLookup -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -LookupName $CollectionName | Out-Null
}
catch {
    write-output "$(get-date) - Invoking Add-SplunkTransformLookup function."    
    try {
        Add-SplunkTransformLookup -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -User "nobody" -Namespace $Namespace -TransformSchema $TransformSchema | Out-Null
    }
    catch {
        Write-Error "$($error[0].Exception.Message)"
        break                 
    }
}


# add multiple kvstore records in specified collection in specified app (can also Add-SplunkKVStoreCollectionRecord for a single record)
write-output "$(get-date) - Invoking Add-SplunkKVStoreCollectionRecordsBatch function with recordset having $($records.count) entries."
try {
    Add-SplunkKVStoreCollectionRecordsBatch -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -Namespace $Namespace -CollectionName $CollectionName -Records $Records | Out-Null
}
catch {
    Write-Error "$($error[0].Exception.Message)"
    break           
}

# get kvstore records in specified collection in specified app
write-output "$(get-date) - Invoking Get-SplunkKVStoreCollectionRecords function."
try {
    $SplunkKVStoreCollectionRecords = Get-SplunkKVStoreCollectionRecords -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -Namespace $Namespace -CollectionName $CollectionName
}
catch {
    Write-Error "$($error[0].Exception.Message)"
    break           
}
write-output "$(get-date) - Get-SplunkKVStoreCollectionRecords returned [$($SplunkKVStoreCollectionRecords.count)] records."    


<#
# query specific items in collection 
# https://docs.splunk.com/Documentation/Splunk/9.0.1/RESTREF/RESTkvstore#storage.2Fcollections.2Fdata.2F.7Bcollection.7D

$Query = @{
    'id' = @{'$lte'=5} 
}
$fields = 'id,_key,name,message'
$Results = Get-SplunkKVStoreCollectionRecordsQuery -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -Namespace $Namespace -CollectionName $CollectionName -Query $Query -Fields $fields
#>



<####  OTHER OPERATIONS ####

# get collection details
$CollectionList = Get-SplunkKVStoreCollectionList -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -Namespace $Namespace
$Collection = $CollectionList | where-object {$_.title -eq $CollectionName}

<#
# list Roles which could be applied to an ACL
# (Get-SplunkAuthorizationRoles -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey).title -join ', '

# list Users which could be applied to an ACL
# (Get-SplunkAuthenticationUsers -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey).title -join ', '

$objectACL = Get-SplunkObjectACL -sessionKey $SplunkSessionKey -id $Collection.id

# set permissions.  Note built-in roles (admin, can_delete, power, splunk-system-role, user)
$objectACL = Set-SplunkObjectACL -sessionKey $SplunkSessionKey -id $Collection.id -app $Namespace -owner 'staulcd-dev' -perms_read '*' -perms_write 'admin, staulcd-dev, user'

# show general ACL info
$general_perms = ($objectACL.content.dict.key | where-object {$_.name -eq 'eai:acl'}).dict.key
write-output $general_perms

# show individual premissions
$read_perms = (((($objectACL.content.dict.key | where-object {$_.name -eq 'eai:acl'}).dict.key | Where-Object {$_.name -eq 'perms'}).dict.key | Where-Object {$_.name -eq 'read'}).list.innertext).trim()
write-output "Read Permissions: $($read_perms)"

$write_perms = (((($objectACL.content.dict.key | where-object {$_.name -eq 'eai:acl'}).dict.key | Where-Object {$_.name -eq 'perms'}).dict.key | Where-Object {$_.name -eq 'write'}).list.innertext).trim()
write-output "Write Permissions: $($write_perms)"

# List all transform lookups
Get-SplunkTransformLookups -sessionKey $SplunkSessionKey -User "nobody" -Namespace $Namespace -BaseURL $BaseUrl

# Remove kvstore records in specified collection in specified app (does not return anything)
Remove-SplunkKVStoreCollectionRecords -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -Namespace $Namespace -CollectionName $CollectionName

# Remove kvstore collection in specified app (does not return anything)
Remove-SplunkKVStoreCollection -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -Namespace $Namespace -CollectionName $CollectionName

# Remove transform lookup (does not return anything except error)
Remove-SplunkTransformLookup -BaseUrl $BaseUrl -SessionKey $SplunkSessionKey -User "nobody" -Namespace $Namespace -LookupName $CollectionName

###### END OTHER OPERATINS ####>

# display script execution runtime summary
$timespan = New-TimeSpan -Start $script_start
write-output "$(get-date) - Script execution completed with runtime duration of [$($timespan)]."