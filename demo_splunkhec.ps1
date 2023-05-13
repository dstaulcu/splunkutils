$script_start = get-date

# import module providing for various Splunk related functions
import-module -name .\splunkutils.psm1 -force

# define variables to control the count and size of sample events
$sample_record_count = 10000
$sample_event_size_bytes = 256

write-host "$(get-date) - Creating $($sample_record_count) array members with each message property having size of $($sample_event_size_bytes) bytes."

# create sample events in array
$Records = new-object System.Collections.ArrayList
for ($i=1 ; $i -le $sample_record_count; $i++) {

    # add record number prefix to message
    $message = "$($i) - "

    # add as many "*" to message to reach desired event size when formatted as json
    $message += "*" * ($sample_event_size_bytes - $message.Length - '{"message":""}'.Length)

    # add message property to dictionary
    $record = [ordered]@{
        "message" = $message
    }

    # add dictionary item to arraylist
    $Records.add($Record) | Out-Null
}

# call the function in the splunkutils module passing record/recordset for writing to hec in batch if necessary
<<<<<<< HEAD
Add-SplunkHecEvents -server "localhost" -hec_port "9088" -hec_token "ced6bfd1-d277-44dc-92c6-a68e0cb9f83a" -index "main" -source "test-source" -sourcetype "test-sourcetype" -record $Records -max_batchsize_mb 1MB
=======
Add-SplunkHecEvents -server "localhost" -hec_port "9088" -hec_token "ced6bfd1-d277-44dc-92c6-a68e0cb9f83a" -index "main" -source "test-source" -sourcetype "test-sourcetype" -record $Records -hec_event_max_batchsize_bytes $max_batchsize_mb
>>>>>>> 5022bf7457a09d6c7f20a900baa07760651d3af5

# display script execution runtime summary
$timespan = New-TimeSpan -Start $script_start
write-output "$(get-date) - Script execution completed with runtime duration of [$($timespan)]."