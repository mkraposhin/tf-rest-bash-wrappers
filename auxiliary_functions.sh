if [[ -v AUXILIARY_FUNCTIONS ]]
then
    echo "The file auxiliary_functions.sh has been already sourced"
    echo "Can not proceed"
    exit 0
fi

function clean_results(){
    echo "clean_results"
    rm -rf $RES_FOLDER
    mkdir -p $RES_FOLDER
}

function wait_and_analyze_results(){
    local n_results_exp=$1
    local n_results=0
    local results=""
    local n_successful=0
    local is_ok=""

    if [ ! -d $RES_FOLDER ]
    then
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

#
# Returns NH to destination IP prefix on the given compute.
# Only the first path (NH) is analyzed
# Input parameters:
# - dst_ip: the destination IP prefix
# - vrf_name: name of VRF instance
# - comp_ip: the IP of the compute server
#
function vr_state(){
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

    curl -s -o t_nhs.xml http://$comp_ip:8085/Snh_Inet4UcRouteReq?x=$vrf_id
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

function check_state_result() {
    local result=$1
    local reference=$2
    local check_res=$?
    return $check_res
}

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
        echo "results_are_ok: $@"
        return 1
    fi
    return 0
}

export AUXILIARY_FUNCTIONS=

#
#END-OF-FILE
#

