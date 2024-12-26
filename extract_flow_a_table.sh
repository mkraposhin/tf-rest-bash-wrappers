flow_table_dump_part=log.AllFlowsreg
n_flow_key=any #any value is needed to start the extraction procedure
stop_flow_key="0-0-0-0-0-0.0.0.0-0.0.0.0"
i_part=0
curl http://127.0.0.1:8085/Snh_FetchAllFlowRecords? > $flow_table_dump_part-$i_part
n_flow_key=`xmllint --xpath "string(//FlowRecordsResp/flow_key)" $flow_table_dump_part-$i_part`
while [ "$n_flow_key" != "" ] && [ "$n_flow_key" != "$stop_flow_key" ]
do
    i_part=`expr $i_part + 1`
    curl http://127.0.0.1:8085/Snh_NextFlowRecordsSet?flow_key=$n_flow_key > $flow_table_dump_part-$i_part
    n_flow_key=`xmllint --xpath "string(//FlowRecordsResp/flow_key)" $flow_table_dump_part-$i_part`
done
echo $n_flow_key
