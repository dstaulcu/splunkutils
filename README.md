# splunkutils

[splunkutils.psm1](https://github.com/dstaulcu/splunkutils/blob/main/splunkutils.psm1/) - a powershell module to simplify interaction with Splunk resources via REST.

# example apps leveraging splunkutils

[demo_search.ps1](https://github.com/dstaulcu/splunkutils/blob/main/demo_search.ps1/) - Demonstrates use of splunkutils to orchestrate processing of splunk search jobs.

[demo_kvstore.ps1](https://github.com/dstaulcu/splunkutils/blob/main/demo_kvstore.ps1/) - Demonstrates use of splunkutils to facilitate splunk kv store and transform lookup operations.

[demo_splunkbase.ps1](https://github.com/dstaulcu/splunkutils/blob/main/demo_splunkbase.ps1/) - Demonstrates use of splunkutils to facilitate authentication to Splunkbase and download the catalog (listing) of apps.

[demo_fieldsummaries.ps1](https://github.com/dstaulcu/splunkutils/blob/main/demo_fieldsummaries.ps1/) - Demonstrates use of splunkutils to export fieldsummaries unique to each combination of index, source, and sourcetype within a specified namespace 
(app) and applicable to specifed users.

[demo_splunkhec.ps1](https://github.com/dstaulcu/splunkutils/blob/main/demo_splunkhec.ps1/) - Demonstrates use of Add-SplunkHecEvents function in splunkutils to spool arraylist members as json events into Splunk in specified batch sizes via Splunk HEC.
