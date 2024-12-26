flow_table_dump_part=log.AllKFlowsreg
n_records=1 #any value is needed to start the extraction procedure
i_part=0
curl http://127.0.0.1:8085/Snh_KFlowReq? > $flow_table_dump_part-$i_part
n_records=`xmllint --xpath "string(//KFlowResp/flow_handle)" $flow_table_dump_part-$i_part`
while [ "$n_records" != "" ] && [ "$n_records" -gt 0 ]
do
    i_part=`expr $i_part + 1`
    curl http://127.0.0.1:8085/Snh_NextKFlowReq?flow_handle=$n_records > $flow_table_dump_part-$i_part
    n_records=`xmllint --xpath "string(//KFlowResp/flow_handle)" $flow_table_dump_part-$i_part`
done
