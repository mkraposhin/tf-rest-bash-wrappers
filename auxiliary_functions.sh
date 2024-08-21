if [[ -v AUXILIARY_FUNCTIONS ]]
then
    echo "The file auxiliary_functions.sh has been already sourced"
    echo "Can not proceed"
    exit 0
fi

## @fn gobgp_toml_config()
## @brief returns a minimum GoBGP config (in TOML format) for a BGP server
function gobgp_toml_config() {
    local local_asn=$1
    local remote_asn=$2
    local local_router_ip=$3
    local remote_router_ip=$4

    local BGP_CONF=

read -r -d '' BGP_CONF <<- BGP_CONF_MARKER
[global.config]
  as = "$local_asn"
  router-id = "$local_router_ip"
[[neighbors]]
  [neighbors.config]
    neighbor-address = "$remote_router_ip"
    peer-as = "$remote_asn"
  [[neighbors.afi-safis]]
    [neighbors.afi-safis.config]
      afi-safi-name = "l2vpn-evpn"
BGP_CONF_MARKER

    echo "$BGP_CONF"
}

## @fn frr_bgp_config()
## @brief returns minimum FRR config for BGP server
function frr_bgp_config() {
    local local_asn=$1
    local remote_asn=$2
    local bgp_nei_ip=$3
    local adv_ip=$4
    if [ "$adv_ip" = "" ]
    then
        adv_ip="10.0.0.100/32"
    fi

    local BGP_CONF=

read -r -d '' BGP_CONF <<- BGP_CONF_MARKER
        log syslog informational
        router bgp $local_asn
         no bgp ebgp-requires-policy
         no bgp network import-check
         neighbor $bgp_nei_ip remote-as $remote_asn
         neighbor $bgp_nei_ip ebgp-multihop 5 ! or any other needed value
         ! when we have second controller:
         ! neighbor 10.0.0.2 remote-as 510
         ! neighbor 10.0.0.2 ebgp-multihop 5 ! or any other needed value
         address-family ipv4 unicast
          network $adv_ip
         exit-address-family
        !
BGP_CONF_MARKER

}

## @fn run_gobgpd
## @brief runs gobgpd daemon on the specified machine
function run_gobgpd() {
    local local_asn=$1 # where GoBGP is installed
    local remote_asn=$2
    local local_router_ip=$3 # where GoBGP is installed
    local remote_router_ip=$4
    gobgp_toml_config $local_asn $remote_asn \
        $local_router_ip $remote_router_ip > ./gobgpd.toml.conf

    ssh root@$local_router_ip "pkill gobgpd"
    ssh root@$local_router_ip "mkdir -p /etc/gobgp.d"
    ssh root@$local_router_ip "rm -rf /etc/gobgp.d/gobgpd.toml.conf"
    scp ./gobgpd.toml.conf root@$local_router_ip:/etc/gobgp.d/gobgpd.toml.conf
    ssh root@$local_router_ip  "gobgpd -f /etc/gobgp.d/gobgpd.toml.conf" &
}

## @fn clean_results()
## @brief cleans resuts
function clean_results(){
    echo "clean_results"
    rm -rf $RES_FOLDER
    mkdir -p $RES_FOLDER
}

## @fn ping_function()
## @brief pings a specified host from another host
function ping_function(){
    local where_addr=$1
    local from_intf=$2
    local n_pings=$3
    local ping_id=$4
    local vm_user=$5
    local vm_ip=$6
    local n_pings_ref=`expr $n_pings - 2`
    local ping_out=
    if [ "$from_intf" = "--" ]
    then
        ping_out=`ssh -i $SSH_FILE \
            $vm_user@$vm_ip "ping $where_addr -c $n_pings"`
    else
        ping_out=`ssh -i $SSH_FILE \
            $vm_user@$vm_ip "ping $where_addr%$from_intf -c $n_pings"`
    fi
    #local ping_out=`ping $where_addr%$from_intf -c $n_pings`
    local interm=`echo $ping_out | grep "$where_addr: icmp_seq=" -o`
    local n_success_pings=`echo $ping_out | grep "icmp_seq=" \
        -o | wc -l`
    # local n_success_pings=`echo $ping_out | grep "$where_addr%eth$from_intf: icmp_seq=" \
    #     -o | wc -l`

    if [ ! -d $RES_FOLDER ]
    then
        return 0
    fi

    if [ -z "$n_success_pings" ]
    then
        echo "FAILED" > $RES_FOLDER/$RES_PREFIX$ping_id
        return 0
    elif [ $n_success_pings -lt $n_pings_ref ]
    then
        echo "FAILED $n_success_pings" > $RES_FOLDER/$RES_PREFIX$ping_id
        echo "$ping_out" >> $RES_FOLDER/$RES_PREFIX$ping_id
        return 0
    fi
    echo "OK" > $RES_FOLDER/$RES_PREFIX$ping_id
}

## @fn curl_function()
## @brief runs curl for the given IPv6 address from
## the given virtual machine
function curl_function(){
    local where_addr=$1
    local ip_port=$2
    local from_intf=$3
    local conn_time=$4 #can be used as connection timeout --connect-timeout, --max-time
    local curl_id=$5
    local vm_user=$6
    local vm_ip=$7
    local ref_str="$8"
    if [ "$ref_str" = "" ]
    then
        ref_str="latest"
    fi
    if [ "$IDENT_FILE" = "" ]
    then
        echo "Identity file was not specified"
        return 1
    fi
    local conn_timeout=`expr ${#vms_list[@]} \* $conn_time`

    local curl_out=`ssh -i $IDENT_FILE \
        $vm_user@$vm_ip "curl --connect-timeout $conn_timeout \
        http://[$where_addr%$from_intf]:$ip_port"`

    # local interm=`echo $curl_out | grep "latest" -o`
    local n_success_res=`echo $curl_out | grep "$ref_str" \
        -o | wc -l`

    if [ ! -d $RES_FOLDER ]
    then
        return 0
    fi

    if [ -z "$n_success_res" ]
    then
        echo "FAILED" > $RES_FOLDER/$RES_PREFIX$curl_id
        return 0
    elif [ $n_success_res -lt 1 ]
    then
        echo "FAILED $n_success_res" > $RES_FOLDER/$RES_PREFIX$curl_id
        echo "$curl_out" >> $RES_FOLDER/$RES_PREFIX$curl_id
        return 0
    fi
    echo "OK" > $RES_FOLDER/$RES_PREFIX$curl_id
}


## @fn dig_function()
## @brief runs dig function to query NS
function dig_function() {
    local what="$1"
    local record_type="$2"
    local dns_ip="$3"
    local dig_id="$4"
    local vm_user=$5
    local vm_ip=$6
    local reply_ref="$7"
    if [ "$reply_ref" = "" ]
    then
        reply_ref="NOERROR"
    fi
    local dig_output=
    if [ "$record_type" = "reverse" ]
    then
        dig_output=`ssh -i $SSH_FILE \
                $vm_user@$vm_ip "dig -x "$what" @"$dns_ip""`
    else
        dig_output=`ssh -i $SSH_FILE \
                $vm_user@$vm_ip "dig -t "$record_type" "$what" @"$dns_ip""`
    fi
    local no_errors=`echo $dig_output | grep "status: $reply_ref" -o | wc -l`

    if [ ! -d $RES_FOLDER ]
    then
        return 0
    fi
    if [ "$no_errors" -eq 0 ]
    then
        echo "FAILED" > $RES_FOLDER/$RES_PREFIX$dig_id
        return 0
    else
        echo "OK" > $RES_FOLDER/$RES_PREFIX$dig_id
    fi
}

## @fn wait_and_analyze_results()
## @brief waits for results from asynchronous runs and analyze them when they are ready
function wait_and_analyze_results() {
    local n_results_exp=$1
    local n_results=0
    local results=""
    local n_successful=0
    local is_ok=""

    if [ "$n_results_exp" = "" ]
    then
        echo "Number of expected results was not specified."
        return 1
    fi

    if [ $n_results_exp -lt 1 ]
    then
        echo "Wrong Number of expected results was specified: $n_results_exp"
        return 1
    fi

    if [ ! -d $RES_FOLDER ]
    then
        echo "$RES_FOLDER result folder doesnt exist"
        return 0
    fi

    while [ $n_results -lt $n_results_exp ]
    do
        echo "Waiting for results: $n_results are ready of $n_results_exp"
        sleep 2 #//or maybe 2-3?
        if [ -z "$(ls -A $RES_FOLDER/)" ] #empty
        then
            continue
        fi
        n_results=`ls $RES_FOLDER/$RES_PREFIX* | wc -w`
    done

    results=`ls $RES_FOLDER/$RES_PREFIX*`
    for res in $results
    do
        is_ok=`cat $res | grep "OK"`
        if [ "$is_ok" = "OK" ]
        then
            echo "$res $is_ok"
            n_successful=`expr $n_successful + 1`
        else
            echo "$res FAILED"
        fi
    done

    if [ $n_successful -eq $n_results_exp ]
    then
        echo "OK"
        return 0
    fi
    echo "FAILED: $(expr $n_successful - $n_results_exp)"
}

## @fn vr_state()
## @brief Returns NH to destination IP prefix on the given compute.
## Only the first path (NH) is analyzed
## Input parameters:
## - dst_ip: the destination IP prefix
## - vrf_name: name of VRF instance
## - comp_ip: the IP of the compute server
function vr_state() {
    local dst_ip=$1
    local vrf_name=$2
    local comp_ip=$3

    #request for the list of vrfs:
    curl -s -o t_vrfs.xml http://$comp_ip:8085/Snh_VrfListReq
    #get a vrf id
    local vrf_id=`xmllint --xpath "string(//VrfSandeshData[name='$vrf_name']/ucindex)" t_vrfs.xml`
    # return if $vrf_id is empty
    if [ "$vrf_id" = "" ]
    then
        echo "Ev"
        return
    fi

    local dst_ip_is_v4=`is_ipv4_address $dst_ip`
    local dst_ip_is_v6=`is_ipv6_address $dst_ip`

    if [ "$dst_ip_is_v4" = "yes" ]
    then
            curl -s -o t_nhs.xml http://$comp_ip:8085/Snh_Inet4UcRouteReq?x=$vrf_id
    fi

    if [ "$dst_ip_is_v6" = "yes" ]
    then
            curl -s -o t_nhs.xml http://$comp_ip:8085/Snh_Inet6UcRouteReq?x=$vrf_id
    fi

    #echo t_nhs
    local n_nhs=`xmllint --xpath "count(//RouteUcSandeshData[src_ip='$dst_ip']/path_list/list/PathSandeshData)" t_nhs.xml`
    if [ "$n_nhs" = "" ]
    then
        echo "En"
        return
    fi
    if [ $n_nhs -gt 5 ]
    then
        echo "Ec$n_nhs"
        return
    fi
    if [ $n_nhs -eq 0 ]
    then
        echo "$comp_ip,$i_nh"
        return
    fi
    i_nh=1
    while [ $i_nh -le $n_nhs ]
    do
        local nh_type=`xmllint --xpath "string(//RouteUcSandeshData[src_ip='$dst_ip']/path_list/list/PathSandeshData[$i_nh]/nh/NhSandeshData/type)" t_nhs.xml`
        local peer_type=`xmllint --xpath "string(//RouteUcSandeshData[src_ip='$dst_ip']/path_list/list/PathSandeshData[$i_nh]/peer)" t_nhs.xml`
        if [ "$nh_type" = "interface" ]
        then
            echo "$comp_ip,$i_nh: I $peer_type"
            #return
        elif [ "$nh_type" = "tunnel" ]
        then
            echo "$comp_ip,$i_nh: T $peer_type"
            #return
        elif [ "$nh_type" = "vrf" ]
        then
            echo "$comp_ip,$i_nh: V $peer_type"
        elif [[ "$nh_type" =~ .*"ECMP Composite".* ]] #[ "$nh_type" = "Composite" ]
        then
            local n_paths=`xmllint --xpath "count(//RouteUcSandeshData[src_ip='$dst_ip']/path_list/list/PathSandeshData[$i_nh]/nh/NhSandeshData/mc_list/list/McastData)" t_nhs.xml`
            local n_null_paths=`xmllint --xpath "count(//RouteUcSandeshData[src_ip='$dst_ip']/path_list/list/PathSandeshData[$i_nh]/nh/NhSandeshData/mc_list/list/McastData[type='NULL'])" t_nhs.xml`
            local n_paths=`expr $n_paths - $n_null_paths`
            echo "$comp_ip,$i_nh: C$n_paths""N$n_null_paths $peer_type"
            #return
        fi
        i_nh=`expr $i_nh + 1`
    done
    #echo "Eo"
}

## @fn check_state_result()
## @brief compares given results with reference
function check_state_result() {
    local result=$1
    local reference=$2
    grep -q "$reference" <<< "$result"
    local check_res=$?
    return $check_res
}

## @fn wait_for_condition
## @brief the function waits for a successful execution of a function or a
## command. The function or a command should return 0 in case of success and
## 1 in case of failure.
function wait_for_condition() {
    local sleep_time="$2"
    if [ "$sleep_time" = "" ]
    then
        sleep_time=0.1 #100ms
    fi
    $1 #execute the provided command
    local cond_res=$?
    while [ $cond_res -ne 0 ]
    do
        sleep $sleep_time
        $1 #execute the provided command
        cond_res=$?
    done
}

## @fn is_process_nonexistent
## @brief the function determines whether the process is not running. Returns
## 0 if there are no processes with the specified name and 1 otherwise.
function is_process_nonexistent() {
    local proc_name=$1
    n_processes=`pgrep $proc_name | wc -l`
    if [ $n_processes -ne 0 ]
    then
        #echo "There are $n_processes copies of $proc_name have been left in the memory" 1>&2
        return 1
    fi
    #echo "No processes $proc_name have been left in the memory" 1>&2
    return 0
}

## @fn results_are_ok
## @brief the function checks whether all the specified results (return codes)
## contain correct values. Returns 0 if there are no non-zero return codes and
## 1 otherwise.
function results_are_ok() {
    local all_ok=0
    for res in "$@"
    do
        if [ $res -ne 0 ]
        then
            all_ok=1
            break
        fi
    done
    if [ $all_ok -ne 0 ]
    then
        echo "FAILED: $@"
        return 1
    fi
    return 0
}

## @fn aggregate_over_list
## @brief Aggregates (summates) value of the specified list
function aggregate_over_list() {
    local xml_file=$1
    local list_path=$2
    local item_name=$3
    local value_name=$4

    if [ "$xml_file" = "" ]
    then
        echo "The XML file was not specified"
        return 1
    fi

    if [ "$list_path" = "" ]
    then
        echo "The list path was not specified"
        return 1
    fi

    if [ "$value_name" = "" ]
    then
        echo "The value name was not specified"
        return 1
    fi

    local list_size=`xmllint --xpath "string($list_path/@size)" $xml_file`
    if [ "$list_size" = "" ]
    then
        list_size=0
    fi

    local i_elem=1
    local aggr_value=0
    local curr_value=0
    local value_path=
    while [ $i_elem -le $list_size ]
    do
        value_path="$list_path/$item_name[$i_elem]/$value_name"
        curr_value=`xmllint --xpath "string($value_path)" $xml_file`
        aggr_value=$(($curr_value + $aggr_value))
        i_elem=$(($i_elem + 1))
    done

    echo $aggr_value
}

## @fn query_task_stats
## @brief Gathers task stats for a given OpenSDN module
function query_task_stats() {
    local module_ip=$1
    local module_port=$2

    if [ "$module_ip" = "" ]
    then
        echo "The IP to query was not specified"
        return 1
    fi

    if [ "$module_port" = "" ]
    then
        echo "The port to query was not specified"
        return 1
    fi

    curl -s -o t_task_state.xml http://$module_ip:$module_port/Snh_SandeshTaskSummaryRequest?
    #local n_tasks=`xmllint --xpath "string(//task_group_list[name='$vrf_name']/ucindex)" t_vrfs.xml`

    local n_tasks=`xmllint --xpath "string(//task_group_list/list/@size)" t_task_state.xml`
    if [ "$n_tasks" = "" ]
    then
        n_tasks=0
    fi

    local i_task=1 # indices are 1-based
    local tasks_created=
    local tasks_completed=
    local tasks_running=
    local waitq_size=
    local deferq_size=
    echo "i task tasks_created tasks_completed tasks_running waitq_size deferq_size"
    while [ $i_task -le $n_tasks ]
    do
        local task_name=`xmllint --xpath "string(//task_group_list/list/SandeshTaskGroup[$i_task]/name)" t_task_state.xml`
        tasks_created=`\
            aggregate_over_list \
            t_task_state.xml \
            "//task_group_list/list/SandeshTaskGroup[$i_task]/task_entry_list/list" \
            "SandeshTaskEntry" \
            "tasks_created"`

        tasks_completed=`\
            aggregate_over_list \
            t_task_state.xml \
            "//task_group_list/list/SandeshTaskGroup[$i_task]/task_entry_list/list" \
            "SandeshTaskEntry" \
            "total_tasks_completed"`

        tasks_running=`\
            aggregate_over_list \
            t_task_state.xml \
            "//task_group_list/list/SandeshTaskGroup[$i_task]/task_entry_list/list" \
            "SandeshTaskEntry" \
            "tasks_running"`

        waitq_size=`\
            aggregate_over_list \
            t_task_state.xml \
            "//task_group_list/list/SandeshTaskGroup[$i_task]/task_entry_list/list" \
            "SandeshTaskEntry" \
            "waitq_size"`

        deferq_size=`\
            aggregate_over_list \
            t_task_state.xml \
            "//task_group_list/list/SandeshTaskGroup[$i_task]/task_entry_list/list" \
            "SandeshTaskEntry" \
            "deferq_size"`

        echo "$i_task $task_name $tasks_created $tasks_completed $tasks_running $waitq_size $deferq_size"
        i_task=$(($i_task + 1))
    done
}

export AUXILIARY_FUNCTIONS=

#
#END-OF-FILE
#




