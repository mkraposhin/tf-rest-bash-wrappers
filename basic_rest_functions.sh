#!/usr/bin/bash

## @file
## @brief A set of functions to talk to the TF Agent REST server
## @author Matvey Kraposhin

if [[ -v BASIC_REST_FUNCTIONS ]]
then
    echo "The file basic_rest_functions.sh has been already sourced"
    echo "Can not proceed"
    exit 0
fi

#
# Constants and a configuration
#

## @brief Ordered list of digits for hexadecimal numerical system
declare -a HEX_DIGITS=("0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "A" "B" "C" "D" "E" "F")

## @brief Ordered list of capital latin letters
declare -a LAT_LETTERS=(A B C D E F G H I J K L M N O P Q R S T U V U W X Y Z)

## @brief Contains name of log file
declare CURL_LOG=log

if [[ ! -v CONTROLLER_SETTINGS ]]
then
    echo "Settings for controller (controller_settings.sh) were not found"
    echo "Can not proceed"
    exit 0
fi
REST_ADDRESS="http://$CONTROLLER_HOST:$CONTROLLER_PORT"
RES_FOLDER="/tmp/$USER-run-results"
RES_PREFIX="test_result_"

## @fn random_hex_digit()
## @brief Returns a random hex digit
function random_hex_digit(){
    local digit_pos=`expr \( $RANDOM  \) / 2048`
    echo ${HEX_DIGITS[$digit_pos]}
}


## @fn random_dec_digit()
## @brief Returns a random decimal digit
function random_dec_digit(){
    local digit_pos=`expr \( $RANDOM  \) / 2048`
    while [ $digit_pos -gt 9 ]
    do
        digit_pos=`expr \( $RANDOM  \) / 2048`
    done
    echo ${HEX_DIGITS[$digit_pos]}
}

## @fn random_dec_digit_max()
## @brief Returns a random decimal digit in the range [0,max)
function random_dec_digit_max(){
    local max=$1
    local digit_pos=`expr \( $RANDOM  \) / 2048`
    while [ $digit_pos -ge $max ]
    do
        digit_pos=`expr \( $RANDOM  \) / 2048`
    done
    echo ${HEX_DIGITS[$digit_pos]}
}

## @fn random_letter()
## @brief Returns a random capital latin letter
function random_letter(){
    local letter_pos=`expr \( $RANDOM  \) / 1260`
    echo ${LAT_LETTERS[$letter_pos]}
}

## @fn random_string()
## @brief Returns a string with the given length of random letters
function random_string(){
    local string_len=$1
    if [ "$string_len" = "" ]
    then
        echo ""
        return 1
    fi
    local i=0
    str=""
    while [ $i -lt $string_len ]
    do
        str="$str"`random_letter`
        i=`expr $i + 1`
    done
    echo "$str"
}

## @fn execute_rest_request()
## @brief Executes REST request
function execute_rest_request(){
    local req_type="$1"
    local req_str="$2"
    local req_url="$3"

    if [ "$req_str" = "" ]
    then
        curl -s -X "$req_type"\
             -H "X-Auth-Token: $OS_TOKEN"\
             -H "Content-Type: application/json; charset=UTF-8"\
             "$req_url"
    else
        curl -s -X "$req_type"\
             -H "X-Auth-Token: $OS_TOKEN"\
             -H "Content-Type: application/json; charset=UTF-8"\
             --data " $req_str " "$req_url"
    fi
}

## @fn execute_put_request()
## @brief Executes PUT REST request
function execute_put_request(){
    local req_str="$1"
    local req_url="$2"
    execute_rest_request "PUT" "$req_str" "$req_url"
}

## @fn execute_post_request()
## @brief Executes POST REST request (creation of a new object)
function execute_post_request(){
    local req_str="$1"
    local req_url="$2"
    execute_rest_request "POST" "$req_str" "$req_url"
}

## @fn execute_get_request()
## @brief Executes GET REST request
function execute_get_request(){
    local req_url="$1"
    execute_rest_request "GET" "" "$req_url"
}

## @fn execute_delete_request()
## @brief Executes DELETE REST request
function execute_delete_request(){
    local req_url=$1
    execute_rest_request "DELETE" "" "$req_url"
}

## @fn name_to_fqname()
## @brief Returns fqname for a given network name
function name_to_fqname(){
    local fqname="[\"default-domain\", \"admin\", \"$1\"]"
    echo "$fqname"
}

## @fn prefix_to_ip()
## @brief Returns IP part of a prefix
function prefix_to_ip(){
    local prefix_str=$1
    local slash_pos=`expr index "$prefix_str" /`
    slash_pos=`expr $slash_pos - 1`
    echo ${prefix_str:0:$slash_pos}
}

## @fn fqname_json_to_csv()
## @brief Returns fqname in the CSV format
function fqname_json_to_csv() {
    local fqname="$1"
    local csv_fqname=`echo "$fqname" | sed 's/ //g'` # remove spaces
    csv_fqname=`echo "$csv_fqname" | sed 's/"//g'` # remove \" characters
    csv_fqname=`echo "$csv_fqname" | sed 's/,/:/g'` # replace "," w/ ":"

    csv_fqname=${csv_fqname::-1} #remove last ]
    csv_fqname=${csv_fqname:1} #remove first [
    echo "$csv_fqname"
}

## @fn fqname_to_uuid()
## @brief Returns the UUID of an object with a given fqname
function fqname_to_uuid(){
    local fqname="$1"
    local type="$2"
    local REQ_STR

read -r -d '' REQ_STR <<- REQ_MARKER
{
    "fq_name": $fqname,
    "type": "$type"
}
REQ_MARKER

    local REQ_URL="$REST_ADDRESS/fqname-to-id"
    local UUID_JSON=`execute_post_request "$REQ_STR" "$REQ_URL"`
    grep -q "uuid" <<< "$UUID_JSON"
    local has_uuid=$?
    local UUID_STR=""
    if [ $has_uuid -eq 0 ]
    then
        UUID_STR=`jq -c -r '.uuid' <<< "$UUID_JSON"`
    fi
    echo $UUID_STR
}

## @fn make_ipam_subnet_str()
## @brief Creates a JSON representation for subnet object
function make_ipam_subnet_str(){
    local prefix=$1
    local prefix_len=$2
    iss="{\"subnet\": {\"ip_prefix\": \"$prefix\",\"ip_prefix_len\": $prefix_len},"
    iss=$iss"\"dns_server_address\": \"$prefix""2\","
    iss=$iss" \"enable_dhcp\": true, \"default_gateway\": \"$prefix""1\","
    iss=$iss" \"addr_from_start\": true}"
    echo "$iss"
}

## @fn make_random_ipam_subnet_prefix_ipv4()
## @brief Creates random IPv4 subnet prefix of a given length
function make_random_ipam_subnet_prefix_ipv4(){
    local subnet_prefix=
    subnet_prefix=$subnet_prefix"`random_dec_digit_max 3`"
    subnet_prefix=$subnet_prefix"`random_dec_digit_max 6`"
    subnet_prefix=$subnet_prefix"`random_dec_digit_max 6`"

    subnet_prefix="$1""$subnet_prefix"
    echo "$subnet_prefix"
}

## @fn make_random_ipam_subnet_prefix_ipv6()
## @brief Creates random IPv6 subnet prefix of a given length
function make_random_ipam_subnet_prefix_ipv6(){
    subnet_prefix=$subnet_prefix"`random_hex_digit`"
    subnet_prefix=$subnet_prefix"`random_hex_digit`"
    subnet_prefix=$subnet_prefix"`random_hex_digit`"
    subnet_prefix=$subnet_prefix"::"
    echo "$subnet_prefix"
}

## @fn make_random_ipam_subnet_ipv6()
## @brief Creates JSON description of IPv6 subnet of length 16
function make_random_ipam_subnet_ipv6(){
    local ipam_subnet_prefix=`make_random_ipam_subnet_prefix_ipv6`
    local prefix_len=16
    local ipam_subnet_str=`make_ipam_subnet_str $ipam_subnet_prefix $prefix_len`
    echo "$ipam_subnet_str"
}

## @fn make_random_ipam_subnet_ipv4()
## @brief Creates random ipam subnet prefix. Input: prepending part (e.g. 10., 10.1., etc) 
function make_random_ipam_subnet_ipv4(){
    local prefix_prep=$1
    local prefix=`make_random_ipam_subnet_prefix_ipv4 $prefix_prep`
    local ipam_subnet_str=
    local n_dots=`echo "$prefix_prep" | grep -o "\." | wc -l` #search for dots
    if [ "$prefix_prep" = "" ] && [ $n_dots -eq 0 ]
    then
        prefix="$prefix"".0.0.0"
        ipam_subnet_str=`make_ipam_subnet_str $prefix 8`
    elif [ $n_dots -eq 1 ]
    then
        prefix="$prefix"".0.0"
        ipam_subnet_str=`make_ipam_subnet_str $prefix 16`
    elif [ $n_dots -eq 2 ]
    then
        prefix="$prefix"".0"
        ipam_subnet_str=`make_ipam_subnet_str $prefix 24`
    else
        ipam_subnet_str=""
    fi
    echo $ipam_subnet_str    
}

## @fn make_ipam_subnet()
## @brief Creates the JSON description for a subnet with the given prefix length 16
function make_ipam_subnet(){
    local ipam_subnet_prefix=$1
    local prefix_len=16
    local ipam_subnet_str=`make_ipam_subnet_str $ipam_subnet_prefix $prefix_len`
    echo "$ipam_subnet_str"
}

## @fn make_random_ipam_subnets_ipv6()
## @brief Creates several ipv6 subnets
function make_random_ipam_subnets_ipv6(){
    local n_subnets=$1
    local i=0
    local subnets_str=""
    while [ $i -lt $n_subnets ]
    do
        if [ $i -gt 0 ]
        then
            subnets_str=$subnets_str", "`make_random_ipam_subnet_ipv6`
        else
            subnets_str=`make_random_ipam_subnet_ipv6`
        fi
        i=`expr $i + 1`
    done
    echo "$subnets_str"
}

## @fn make_random_ipam_subnets_ipv4()
## @brief Creates several ipv4 subnets
## With a given constant prepended network part
## Input: number of subnets, prepended part
function make_random_ipam_subnets_ipv4(){
    local n_subnets=$1
    local prepend_part=$2
    local i=0
    local subnets_str=""
    while [ $i -lt $n_subnets ]
    do
        if [ $i -gt 0 ]
        then
            subnets_str=$subnets_str", "`make_random_ipam_subnet_ipv4\
                $prepend_part`
        else
            subnets_str=`make_random_ipam_subnet_ipv4 $prepend_part`
        fi
        i=`expr $i + 1`
    done
    echo "$subnets_str"
}

## @fn make_ip_instance_name()
## @brief Makes a name for an ip intance
## INPUT: the prefix (string) and optionally, length of the random part
## in a new name
function make_ip_instance_name(){
    local prefix="$1"
    local random_len="$2"
    local stop="no"
    local ipi_name=""
    local fq_name="\"[$ipi_name]\""
    local obj_uuid=""
    local i=0;

    while [ "$stop" != "yes" ]
    do
        if [ "$random_len" != "" ]
        then
            ipi_name="$prefix""_"`random_string $random_len`
        else
            ipi_name="$prefix""_$i"
        fi
        fq_name="[\"$ipi_name\"]"
        obj_uuid=`fqname_to_uuid "$fq_name" "instance-ip"`
        if [ -n $obj_uuid ]
        then
            stop="yes"
        fi
        i=`expr $i + 1`
    done
    echo $ipi_name
}

## @fn add_reference()
## @brief Creates a reference between two objects
function add_reference() {
    local from_uuid="$1"
    local from_type="$2"
    local to_uuid="$3"
    local to_type="$4"
    local REQ_STR=

    read -r -d '' REQ_STR <<- REQ_MARKER
{
    "operation": "ADD",
    "uuid": "$from_uuid",
    "type": "$from_type",
    "ref-uuid": "$to_uuid",
    "ref-type": "$to_type",
    "attr": {"sequence": {"major": 0, "minor": 0}}
}
REQ_MARKER

    local REQ_URL="$REST_ADDRESS/ref-update"
    execute_post_request "$REQ_STR" "$REQ_URL" >> $CURL_LOG
}

## @fn del_reference()
## @brief Removes the reference between two objects
function del_reference() {
    local from_uuid="$1"
    local from_type="$2"
    local to_uuid="$3"
    local to_type="$4"
    local REQ_STR=

    read -r -d '' REQ_STR <<- REQ_MARKER
{
    "operation": "DELETE",
    "uuid": "$from_uuid",
    "type": "$from_type",
    "ref-uuid": "$to_uuid",
    "ref-type": "$to_type",
    "attr": {"sequence": {"major": 0, "minor": 0}}
}
REQ_MARKER

    local REQ_URL="$REST_ADDRESS/ref-update"
    execute_post_request "$REQ_STR" "$REQ_URL" >> $CURL_LOG
}


## @fn delete_entity()
## @brief Deletes an entity (object)
## INPUT: an uuid of an entity and type of an entity
function delete_entity(){
    local entity_uuid="$1"
    local type="$2"
    local REQ_URL=
    local REQ_STR=$REST_ADDRESS/"$type"/"$entity_uuid"

    execute_delete_request $REQ_STR
}

## @fn network_ipam_subnets()
## @brief Extracts UUIDS of IPAM subnets of a given virtual network
## INPUT: fqname of a virtual network
function network_ipam_subnets(){
    local nw_name=$1
    local nw_fqname=`name_to_fqname $nw_name`
    local nw_uuid=`fqname_to_uuid "$nw_fqname" virtual-network`
    local REQ_URL="$REST_ADDRESS/virtual-network/$nw_uuid"

    if [ "$nw_uuid" = "" ]
    then
        echo "network_ipam_subnets: Network $nw_fqname not found"
    fi

    local CURL_RES=`execute_get_request $REQ_URL`
    
    local VNW_DICT=`jq -c -r '.["virtual-network"]' <<< "$CURL_RES"`
    local IPAM_REFS_DICT=`jq -c -r '.["network_ipam_refs"]' <<< "$VNW_DICT"`
    local IPAMS_DICT=`jq -c -r '.[0].attr.ipam_subnets' <<< "$IPAM_REFS_DICT"`
    local N_SUBNETS=`jq -c -r '. | length' <<< "$IPAMS_DICT"`

    local i_subnet=0
    local IPAM_UUIDS=""
    while [ $i_subnet -lt $N_SUBNETS ]
    do
        subnet=`jq -c -r ".[$i_subnet].subnet.ip_prefix" <<< "$IPAMS_DICT"`
        subnet_uuid=`jq -c -r ".[$i_subnet].subnet_uuid" <<< "$IPAMS_DICT"`
        IPAM_UUIDS=$IPAM_UUIDS" $subnet_uuid"
        i_subnet=`expr $i_subnet + 1`
    done
    
    echo $IPAM_UUIDS
}

## @fn network_set_ipams()
## @brief Sets an IPAM for the network
function network_set_ipams() {
    local nw_name="$1"
    local new_ipam_prefixes="$2"
    
    local nw_fqname=`name_to_fqname "$nw_name"`
    local nw_uuid=`fqname_to_uuid "$nw_fqname" virtual-network`
    if [ "$nw_uuid" = "" ]
    then
        echo "network_set_ipams: Cant find $nw_fqname"
        return 1
    fi

    for subnet in $new_ipam_prefixes
    do
        local subnet_prefix_len=${subnet#*"/"}
        local slash_pos=$(( ${#subnet} - ${#subnet_prefix_len} - 1 ))
        local subnet_prefix="${subnet:0:$slash_pos}"
        ipam_subnets="$ipam_subnets "`make_ipam_subnet_str $subnet_prefix $subnet_prefix_len`","
    done
    ipam_subnets=${ipam_subnets::-1} #remove last ","

    read -r -d '' REQ_STR <<- REQ_MARKER
    {
        "virtual-network":
        {
            "network_ipam_refs":
            [{
                "to": ["default-domain", "default-project", "default-network-ipam"],
                "attr" : {"ipam_subnets":[$ipam_subnets]}
            }]
        }
    }
REQ_MARKER

    local REQ_URL="$REST_ADDRESS/virtual-network/$nw_uuid"
    REQ_STR=`echo $REQ_STR`

    execute_put_request "$REQ_STR" "$REQ_URL" >> $CURL_LOG
}

## @fn create_network()
## @brief Creates a new network
## INPUT: name of network, number of subnets per
## network, version of the IP protocol
function create_network(){
    local nw_name=$1
    local n_ipam_subnets=$2
    local ip_version=$3
    local ipam_subnets=
    
    grep -q "\." <<< "$2"
    local has_v4_subnets=$?
    grep -q ":" <<< "$2"
    local has_v6_subnets=$?
    if [ $has_v4_subnets -eq 0 ] || [ $has_v6_subnets -eq 0 ]
    then
        for subnet in $2
        do
            local subnet_prefix_len=${subnet#*"/"}
            local slash_pos=$(( ${#subnet} - ${#subnet_prefix_len} - 1 ))
            local subnet_prefix="${subnet:0:$slash_pos}"
            ipam_subnets="$ipam_subnets "`make_ipam_subnet_str $subnet_prefix $subnet_prefix_len`","
        done
        ipam_subnets=${ipam_subnets::-1} #remove last ","
    else
        if [ "$ip_version" = "ipv4" ]
        then
            ipam_subnets=`make_random_ipam_subnets_ipv4 $n_ipam_subnets "10.0."`
        else
            ipam_subnets=`make_random_ipam_subnets_ipv6 $n_ipam_subnets`
        fi
    fi

    local vn_fqname=`name_to_fqname $nw_name`
    read -r -d '' REQ_STR <<- REQ_MARKER
    {
        "virtual-network":
        {
            "parent_type": "project",
            "fq_name": $vn_fqname,
            "network_ipam_refs":
            [{
                "to": ["default-domain", "default-project", "default-network-ipam"],
                "attr" : {"ipam_subnets":[$ipam_subnets]}
            }]
        }
    }
REQ_MARKER

    local REQ_URL="$REST_ADDRESS/virtual-networks"
    REQ_STR=`echo $REQ_STR`
    execute_post_request "$REQ_STR" "$REQ_URL" >> $CURL_LOG
}

## @fn create_instance_ip()
## @brief Creates an IP Instance
## Input: name, virtual-network fqname, subnet_uuid, ip address(optionally)
function create_instance_ip(){
    local REQ_STR
    local ipi_name="$1"
    local nw_name="$2"
    local subnet_uuid="$3"
    local ip_addr="$4"

    if [ "$ipi_name" = "" ] || [ "$nw_name" = "" ] || [ "$subnet_uuid" = "" ]
    then
        echo "ipi_name=$ipi_name, nw_name=$nw_name, subnet_uuid=$subnet_uuid"
        return 1;
    fi

    
    local ip_instance_addr=""
    local nw_fqname=`name_to_fqname "$nw_name"`
    if [ "$ip_addr" != "" ]
    then
        ip_instance_addr=", \"instance_ip_address\": \"$ip_addr\""
    fi

    read -r -d '' REQ_STR <<- REQ_MARKER
    {
        "instance-ip": {
            "parent_type": "config-root",
            "fq_name": ["$ipi_name"],
            "virtual_network_refs" : [{"to" : $nw_fqname}],
            "subnet_uuid" : "$subnet_uuid",
            "instance_ip_mode": "active-active"
            $ip_instance_addr
        }
    }
REQ_MARKER

    local REQ_URL="$REST_ADDRESS/instance-ips"
    execute_post_request "$REQ_STR" "$REQ_URL" >> $CURL_LOG
}

## @fn create_instance_ip_ifnp()
## @brief Creates a new instance ip if an object with the given name
## is not found
function create_instance_ip_ifnp() {
    local ipi_name="$1"
    local nw_name="$2"
    local subnet_uuid="$3"
    local ip_addr="$4"

    local t_ipi_fqname="[\"$ipi_name\"]"
    local t_ipi_uuid=`fqname_to_uuid "$t_ipi_fqname" "instance-ip"`
    if [ "$t_ipi_uuid" = "" ]
    then
        create_instance_ip "$ipi_name" "$nw_name" "$subnet_uuid" "$ip_addr"
    fi
}

## @fn create_floating_ip()
## @brief Creates a floating ip object
## @input: fip name, parent ipi name, fip ip address, fip direction
function create_floating_ip(){
    local REQ_STR
    local fip_name=$1
    local ipi_name=$2
    local fip_addr=$3
    local fip_dir=$4 #optional

    if ["$fip_dir" = ""]
    then
        fip_dir="both"
    fi

    local fip_fqname="[\"$ipi_name\",\"$fip_name\"]"
    local ipi_fqname="[\"$ipi_name\"]"

    ipi_uuid=`fqname_to_uuid "$ipi_fqname" "instance-ip"`
    if [ "$ipi_uuid" = "" ]
    then
        return 1
    fi

    read -r -d '' REQ_STR <<- REQ_MARKER
    {
        "floating-ip": {
            "parent_type": "instance-ip",
            "parent_uuid" : "$ipi_uuid",
            "fq_name": $fip_fqname,
            "project_refs": [{"to": ["default-domain","admin"]}],
            "floating_ip_address": "$fip_addr",
            "floating_ip_traffic_direction": "$fip_dir"
        }
    }
REQ_MARKER

    local REQ_URL="$REST_ADDRESS/floating-ips"
    execute_post_request "$REQ_STR" "$REQ_URL" >> $CURL_LOG
}


## @fn create_intf_route_table()
## @brief Creates new interface routes table
function create_intf_route_table() {
    local REQ_STR
    local irt_name=$1
    local irt_cidr=$2
    # local fip_name=$1
    # local ipi_name=$2
    local irt_fqname=`name_to_fqname "$irt_name"` # 


    # local fip_fqname="[\"$ipi_name\",\"$fip_name\"]"
    # local ipi_fqname="[\"$ipi_name\"]"

    # ipi_uuid=`fqname_to_uuid "$ipi_fqname" "instance-ip"`
    # if [ "$ipi_uuid" = "" ]
    # then
    #     return 0
    # fi

    read -r -d '' REQ_STR <<- REQ_MARKER
    {
        "interface-route-table": {
            "parent_type": "project",
            "fq_name": $irt_fqname,
            "interface_route_table_routes": { "route": [{"prefix": "$irt_cidr"}] }
        }
    }
REQ_MARKER

    local REQ_URL="$REST_ADDRESS/interface-route-tables"
    execute_post_request "$REQ_STR" "$REQ_URL" >> $CURL_LOG
}

## @fn create_vm_interface()
## @brief Creates a virtual machine interface
## Input: name, virtual-network name
function create_vm_interface(){
    local REQ_STR
    local vmi_name="$1"
    local nw_name="$2"
    local aux_args="$3"

    if [ "$vmi_name" = "" ] || [ "$nw_name" = "" ]
    then
        return 1;
    fi
    if [ -n "$aux_args" ]
    then
        aux_args=","$aux_args
    fi
    local nw_fqname=`name_to_fqname "$nw_name"`
    local vmi_fqname=`name_to_fqname "$vmi_name"`
read -r -d '' REQ_STR <<- REQ_MARKER
{
    "virtual-machine-interface": {
        "parent_type": "project",
        "fq_name": $vmi_fqname,
        "virtual_network_refs" : [{"to" : $nw_fqname}]
        $aux_args
    }
}
REQ_MARKER

    local REQ_URL="$REST_ADDRESS/virtual-machine-interfaces"
    execute_post_request "$REQ_STR" "$REQ_URL" >> $CURL_LOG
}

## @fn create_vm_interface_ifnp()
## @brief Create vm interface if it is not present
function create_vm_interface_ifnp() {
    local vmi_name="$1"
    local nw_name="$2"
    local aux_args="$3"
    local t_vmi_fqname=`name_to_fqname "$vmi_name" "virtual-machine-interface"`
    local t_vmi_uuid=`fqname_to_uuid "$t_vmi_fqname" "virtual-machine-interface"`
    if [ "$t_vmi_uuid" = "" ]
    then
        create_vm_interface "$vmi_name" "$nw_name" "$aux_args"
    fi
}

## @fn create_bgpaas()
## @brief Create BPG-as-a-Service
function create_bgpaas(){
    local REQ_STR
    local bgpaas_name="$1"
    local remote_as="$2"
    local local_as="$3"

    if [ "$bgpaas_name" = "" ]
    then
        return 1;
    fi
    
    local bgpaas_fqname=`name_to_fqname "$bgpaas_name"`
read -r -d '' REQ_STR <<- REQ_MARKER
{
    "bgp-as-a-service": {
        "parent_type": "project",
        "fq_name": $bgpaas_fqname,
        "autonomous_system": "$remote_as",
        "bgpaas_shared": false,
        "bgpaas_session_attributes" : {
           "local_autonomous_system": "$local_as",
            "as_override": false,
            "loop_count": 0,
            "address_families":  {
                "family":  ["inet","inet6"]
            },
            "route_origin_override" : {
                "origin": "IGP",
                "origin_override": false
            },
            "admin_down": false,
            "hold_time": 0,
            "family_attributes":  [{
                "prefix_limit":  {
                    "idle_timeout": 0,
                    "maximum": 0
                },
                "address_family": "inet"
            },
            {
                "prefix_limit":  {
                    "idle_timeout": 0,
                    "maximum": 0
                },
                "address_family": "inet6"
            }]
        }
    }
}
REQ_MARKER
#        "virtual_machine_interface_refs " : [{"to" : $vmi_name}]
    local REQ_URL="$REST_ADDRESS/bgp-as-a-services"
    execute_post_request "$REQ_STR" "$REQ_URL" >> $CURL_LOG
}

## @fn create_logical_router()
## @brief Creates a new logical router
function create_logical_router(){
    local REQ_STR
    local lr_name="$1"

    if [ "$lr_name" = "" ]
    then
        return 1;
    fi
    
    local lr_fqname=`name_to_fqname "$lr_name"`

    read -r -d '' REQ_STR <<- REQ_MARKER
    {
            "logical-router": {
            "parent_type": "project",
            "fq_name": $lr_fqname,
            "logical-router-gateway-external": false,
            "logical_router_type" : "vxlan-routing"
        }
    }
REQ_MARKER

    local REQ_URL="$REST_ADDRESS/logical-routers"
    REQ_STR=`echo $REQ_STR`
    execute_post_request "$REQ_STR" "$REQ_URL" >> $CURL_LOG
}

#
#
#
function set_vni_for_logical_route() {
    local lr_name="$1"
    local vni="$2"
    local lr_fqname=`name_to_fqname "$lr_name"`
    local lr_uuid=`fqname_to_uuid "$lr_fqname" "logical-router"`

    local REQ_STR=
    read -r -d '' REQ_STR <<- REQ_MARKER
    {
            "logical-router": {
                "vxlan_network_identifier" : "$vni"
        }
    }
REQ_MARKER
    
    if [ "$lr_uuid" = "" ]
    then
        echo "set_vni_for_logical_route: $lr_fqname not found"
        return 1
    fi
    local REQ_URL="$REST_ADDRESS/logical-router/$lr_uuid"

    REQ_STR=`echo $REQ_STR`
    execute_put_request "$REQ_STR" "$REQ_URL" >> $CURL_LOG
}

function set_rt_for_logical_router() {
    local lr_name="$1"
    local rts="$2"
    local lr_fqname=`name_to_fqname "$lr_name"`
    local lr_uuid=`fqname_to_uuid "$lr_fqname" "logical-router"`

    RT_STR=
    for rt in $rts
    do
        RT_STR="$RT_STR\"target:$rt\","
    done
    RT_STR=${RT_STR::-1} #remove last ","

    local REQ_STR=
    read -r -d '' REQ_STR <<- REQ_MARKER
    {
            "logical-router": {
                "configured_route_target_list" : {
                    "route_target" : [$RT_STR]
            }
        }
    }
REQ_MARKER
    
    if [ "$lr_uuid" = "" ]
    then
        return 1
    fi
    
    local REQ_URL="$REST_ADDRESS/logical-router/$lr_uuid"
    REQ_STR=`echo $REQ_STR`
    execute_put_request "$REQ_STR" "$REQ_URL" >> $CURL_LOG
}


#
# Link iip with vmi
# Input: ipi fq name, vmi fq name
function link_iip_with_vmi(){
    local ipi_name="$1"
    local vmi_name="$2"
    local ipi_fqname="[\"$ipi_name\"]"
    local vmi_fqname=`name_to_fqname $vmi_name`

    local ipi_uuid=`fqname_to_uuid "$ipi_fqname" "instance-ip"`
    local vmi_uuid=`fqname_to_uuid "$vmi_fqname" "virtual-machine-interface"`

    if [ "$ipi_uuid" = "" ] || [ "$vmi_uuid" = "" ]
    then
        echo "link_iip_with_vmi: No $ipi_fqname or $vmi_fqname"
        return 1
    fi

    read -r -d '' REQ_STR <<- REQ_MARKER
    {
        "instance-ip": {
            "virtual_machine_interface_refs" : [{"to" : $vmi_fqname}]
        }
    }
REQ_MARKER

    local REQ_URL="$REST_ADDRESS/instance-ip/$ipi_uuid"
    REQ_STR=`echo $REQ_STR`
    execute_put_request "$REQ_STR" "$REQ_URL" >> $CURL_LOG
}

function link_iip_with_vmis(){
    local ipi_name="$1"
    local vmis="$2"
    local ipi_fqname="[\"$ipi_name\"]"
    local ipi_uuid=`fqname_to_uuid "$ipi_fqname" "instance-ip"`

    if [ "$ipi_uuid" = "" ]
    then
        echo "link_iip_with_vmis: No $ipi_fqname"
        return 1
    fi
    
    local vmi_fqname=
    local vmi_uuid=
    local vmi_refs=
    for vmi in $vmis
    do
        vmi_fqname=`name_to_fqname $vmi`
        vmi_uuid=`fqname_to_uuid "$vmi_fqname" "virtual-machine-interface"`
        if [ "$vmi_uuid" = "" ]
        then
            echo "link_iip_with_vmis:No $vmi_fqname"
            return 1
        fi
        vmi_refs=$vmi_refs"{\"to\" : $vmi_fqname},"
    done
    vmi_refs=${vmi_refs::-1} #remove last ","

    read -r -d '' REQ_STR <<- REQ_MARKER
    {
        "instance-ip": {
            "virtual_machine_interface_refs" : [$vmi_refs]
        }
    }
REQ_MARKER

    local REQ_URL="$REST_ADDRESS/instance-ip/$ipi_uuid"
    REQ_STR=`echo $REQ_STR`
    execute_put_request "$REQ_STR" "$REQ_URL" >> $CURL_LOG
}

#
#
# Add allowed pair
function link_vmi_with_aap(){
    local vmi_name=$1
    local new_ip=$2
    local pref_len=$3
    local address_mode=$4

    if [ "$address_mode" != "active-standby" ]
    then
        address_mode="active-active"
    fi

    local vmi_fqname=`name_to_fqname $vmi_name`

    local vmi_uuid=`fqname_to_uuid "$vmi_fqname" "virtual-machine-interface"`
    if [ "$vmi_uuid" = "" ]
    then
        echo "link_vmi_with_aap: No $vmi_fqname"
        return 1
    fi

    read -r -d '' REQ_STR <<- REQ_MARKER
    {
        "virtual-machine-interface": {
            "virtual_machine_interface_allowed_address_pairs" : {
                "allowed_address_pair" : [
                    {"address_mode" : "$address_mode",
                     "ip" : {"ip_prefix" : "$new_ip", "ip_prefix_len" : "$pref_len"}}
                ]
            }
        }
    }
REQ_MARKER

    local REQ_URL="$REST_ADDRESS/virtual-machine-interface/$vmi_uuid"
    REQ_STR=`echo $REQ_STR`
    execute_put_request  "$REQ_STR" "$REQ_URL" >> $CURL_LOG
}

#
#
# link the fip with the vmi
function link_fip_with_vmi(){
    local ipi_name=$1
    local fip_name=$2
    local vmi_name=$3

    local fip_fqname="[\"$ipi_name\",\"$fip_name\"]"
    local fip_uuid=`fqname_to_uuid "$fip_fqname" "floating-ip"`
    local vmi_fqname="name_to_fqname $vmi_name"

    if [ "$fip_uuid" = "" ]
    then
        echo "link_fip_with_vmi: No $fip_fqname"
        return 1
    fi

    read -r -d '' REQ_STR <<- REQ_MARKER
    {
        "floating-ip": {
            "virtual_machine_interface_refs" : [
                {"to": $vmi_fqname}
            ]
        }
    }
REQ_MARKER

    local REQ_URL="$REST_ADDRESS/floating-ip/$fip_uuid"
    REQ_STR=`echo $REQ_STR`
    execute_put_request "$REQ_STR" "$REQ_URL" >> $CURL_LOG
}

#
#
# link fip with bgpaas
function link_fip_with_vmis(){
    local ipi_name=$1
    local fip_name=$2
    local vmis=$3

    local fip_fqname="[\"$ipi_name\",\"$fip_name\"]"
    local fip_uuid=`fqname_to_uuid "$fip_fqname" "floating-ip"`

    if [ "$fip_uuid" = "" ]
    then
        echo "link_fip_with_vmis: No $fip_fqname"
        return 1
    fi

    local vmi_fqname=
    local vmi_uuid=
    local vmi_refs=
    for vmi in $vmis
    do
        vmi_fqname=`name_to_fqname $vmi`
        vmi_uuid=`fqname_to_uuid "$vmi_fqname" "virtual-machine-interface"`
        if [ "$vmi_uuid" = "" ]
        then
            echo "link_fip_with_vmis: No $vmi_fqname"
            return 1
        fi
        vmi_refs=$vmi_refs"{\"to\" : $vmi_fqname},"
    done
    vmi_refs=${vmi_refs::-1} #remove last ","

    read -r -d '' REQ_STR <<- REQ_MARKER
    {
        "floating-ip": {
            "virtual_machine_interface_refs" : [
                $vmi_refs
            ]
        }
    }
REQ_MARKER

    local REQ_URL="$REST_ADDRESS/floating-ip/$fip_uuid"
    REQ_STR=`echo $REQ_STR`
    execute_put_request "$REQ_STR" "$REQ_URL" >> $CURL_LOG
}

#
#
# link bgpaas with several vmi
function link_bgpaas_with_vmis(){
    local bgpaas_name=$1
    local vmis="$2"

    local bgpaas_fqname=`name_to_fqname $bgpaas_name`
    local bgpaas_uuid=`fqname_to_uuid "$bgpaas_fqname" "bgp-as-a-service"`

    if [ "$bgpaas_uuid" = "" ]
    then
        echo "link_bgpaas_with_vmis: No $bgpaas_fqname"
        return 1
    fi

    local vmi_fqname=
    local vmi_uuid=
    local vmi_refs=
    for vmi in $vmis
    do
        vmi_fqname=`name_to_fqname $vmi`
        vmi_uuid=`fqname_to_uuid "$vmi_fqname" "virtual-machine-interface"`
        if [ "$vmi_uuid" = "" ]
        then
            echo "link_bgpaas_with_vmis: No $vmi_fqname"
            return 1
        fi
        vmi_refs=$vmi_refs"{\"to\" : $vmi_fqname},"
    done
    vmi_refs=${vmi_refs::-1} #remove last ","

    read -r -d '' REQ_STR <<- REQ_MARKER
    {
        "bgp-as-a-service": {
            "virtual_machine_interface_refs" : [
                $vmi_refs
            ]
        }
    }
REQ_MARKER

    local REQ_URL="$REST_ADDRESS/bgp-as-a-service/$bgpaas_uuid"
    REQ_STR=`echo $REQ_STR`
    execute_put_request "$REQ_STR" "$REQ_URL" >> $CURL_LOG
}

function link_irt_with_vmi(){
    local vmi_name="$1"
    local irts="$2"

    local vmi_fqname=`name_to_fqname "$vmi_name"`
    local vmi_uuid=`fqname_to_uuid "$vmi_fqname" "virtual-machine-interface"`

    if [ "$vmi_uuid" = "" ]
    then
        echo "link_irt_with_vmi: No $vmi_fqname"
        return 1
    fi

    local irt_fqname=
    local irt_uuid=
    local irt_refs=
    for irt in $irts
    do
        irt_fqname=`name_to_fqname "$irt"`
        irt_uuid=`fqname_to_uuid "$irt_fqname" "interface-route-table"`
        if [ "$irt_uuid" = "" ]
        then
            echo "link_irt_with_vmi: No $irt_fqname"
            return 1
        fi
        irt_refs=$irt_refs"{\"to\" : $irt_fqname},"
    done
    irt_refs=${irt_refs::-1} #remove last ","


    read -r -d '' REQ_STR <<- REQ_MARKER
    {
        "virtual-machine-interface": {
            "interface_route_table_refs" : [
                $irt_refs
            ]
        }
    }
REQ_MARKER

    local REQ_URL="$REST_ADDRESS/virtual-machine-interface/$vmi_uuid"
    REQ_STR=`echo $REQ_STR`
    execute_put_request "$REQ_STR" "$REQ_URL" >> $CURL_LOG
}

#
#
# link LR with virtual networks
function link_lr_with_vns(){
    local lr_name=$1
    local vns="$2"
    local lr_fqname=`name_to_fqname "$lr_name"`

    local lr_uuid=`fqname_to_uuid "$lr_fqname" "logical-router"`

    if [ "$lr_uuid" = "" ]
    then
        echo "link_lr_with_vns: No $lr_fqname, uuid = $lr_uuid"
        return 1
    fi

    local net_refs=""
    local vn_fqname=""
    local i_vn=0
    for vn in $vns
    do
        vn_fqname=`name_to_fqname "$vn"`
        local t_vmi_name="vmi-lr-""$lr_name"-"$vn"
        local lr_link="\"virtual_machine_interface_device_owner\":\"network:router_interface\""
        lr_link=$lr_link",\"logical_router_back_refs\":[{\"to\":[$lr_fqname]}]"
        create_vm_interface_ifnp "$t_vmi_name" "$vn" "$lr_link"
        local t_vmi_fqname=`name_to_fqname $t_vmi_name`
        local t_vmi_uuid=`fqname_to_uuid "$t_vmi_fqname" "virtual-machine-interface"`
        local t_ipi_name="ipi-lr-""$lr_name"-"$vn"

        nw_ipams=`network_ipam_subnets "$vn"`
        ipams_arr=($nw_ipams)
        if [ ${#ipams_arr[@]} -lt 1 ] # at least 1 subnet should present
        then
             return 1
        fi
        local t_subnet_uuid="${nw_ipams[0]}"

        create_instance_ip_ifnp "$t_ipi_name" "$vn" "$t_subnet_uuid"

        link_iip_with_vmi "$t_ipi_name" "$t_vmi_name"
        add_reference "$lr_uuid" "logical-router" "$t_vmi_uuid" "virtual-machine-interface"
        #add_reference "$lr_uuid" "logical-router" "$vn_fqname" "virtual-network"

        #local vmi_ref="\"to\" : $t_vmi_fqname, \"attr\" : null, \"uuid\" : \"$t_vmi_uuid\""
        #echo $vmi_ref
        #local vn_ref="\"virtual_network_refs\" : [{\"to\" : $vn_fqname }]"
        #echo "$vmi_ref"
        #echo "$vn_ref"

        #net_refs=$net_refs"{\"to\" : $t_vmi_fqname, "attr":"null","virtual_network_refs" : [{\"to\" : $vn_fqname }]},"
        #net_refs=$net_refs"{"virtual_network_refs" : [{\"to\" : $vn_fqname }]},"
        #net_refs=$net_refs"{$vn_ref},"
        #net_refs=$net_refs"{$vmi_ref},"
    done
}

function get_lr_vn_name() {
    local lr_name="$1"
    local lr_fqname=`name_to_fqname "$lr_name"`
    local lr_uuid=`fqname_to_uuid "$lr_fqname" "logical-router"`
    if [ "$lr_uuid" = "" ]
    then
        echo "get_lr_vn_name: Cant find logical router $lr_fqname"
        return 1
    fi
    local lr_vn_name="__contrail_lr_internal_vn_$lr_uuid""__"
    echo $lr_vn_name
    return 0
}

function get_lr_vrf_name() {
    local lr_name="$1"
    local lr_vn_name=`get_lr_vn_name "$lr_name"`
    local rval=$?
    if [ $rval -eq 0 ]
    then
        local lr_vrf_name="$lr_vn_name,$lr_vn_name"
        echo "$lr_vrf_name"
        return 0
    fi
    echo "get_lr_vrf_name: unknown_lr_name"
    return 1
}

function delete_floating_ips(){
    local iip_fips="$1"

    local iip_name=
    local fip_name=
    local fip_pos=
    local fip_fqname=
    local fip_uuid=
    for iip_fip in $iip_fips
    do

        fip_name=${iip_fip#*","}
        fip_pos=$(( ${#iip_fip} - ${#fip_name} - 1 ))
        iip_name="${iip_fip:0:$fip_pos}"

        fip_fqname="[\"$iip_name\", \"$fip_name\"]"
        echo "Deleting $fip_fqname" >> $CURL_LOG
        fip_uuid=`fqname_to_uuid "$fip_fqname" "floating-ip"`
        if [ "$fip_uuid" != "" ]
        then
            delete_entity "$fip_uuid" "floating-ip"
        fi
    done
}

function delete_instance_ips(){
    local ipis=$1
    for ipi in $ipis
    do
        local ipi_fqname="[\"$ipi\"]"
        echo "Deleting $ipi_fqname" >> $CURL_LOG
        local ipi_uuid=`fqname_to_uuid "$ipi_fqname" "instance-ip"`
        if [ "$ipi_uuid" != "" ]
        then
            delete_entity "$ipi_uuid" "instance-ip"
        fi
    done
}

function delete_vm_interfaces(){
    local vmis=$1
    for vmi in $vmis
    do
        local vmi_fqname=`name_to_fqname $vmi`
        echo "Deleting $vmi_fqname" >> $CURL_LOG
        local vmi_uuid=`fqname_to_uuid "$vmi_fqname" "virtual-machine-interface"`
        if [ "$vmi_uuid" != "" ]
        then
            delete_entity "$vmi_uuid" "virtual-machine-interface"
        fi
    done
}

function delete_bgpaases(){
    local bgps=$1
    for bgpaas in $bgps
    do
        local bgpaas_fqname=`name_to_fqname $bgpaas`
        echo "Deleting $bgpaas_fqname" >> $CURL_LOG
        local bgpaas_uuid=`fqname_to_uuid "$bgpaas_fqname" "bgp-as-a-service"`
        if [ "$bgpaas_uuid" != "" ]
        then
            delete_entity "$bgpaas_uuid" "bgp-as-a-service"
        fi
    done
}

function delete_networks(){
    local networks="$1"
    for nw in $networks
    do
        echo "Deleting nw $nw" >> $CURL_LOG
        nw_fqname=`name_to_fqname $nw`
        nw_uuid=`fqname_to_uuid "$nw_fqname" "virtual-network"`
        delete_entity "$nw_uuid" "virtual-network"
    done
}

function prefix_delete_vm_interfaces(){
    local vm_prefix=$1
#this deletes all vmi's with a given prefix
    local myvmis=`curl $REST_ADDRESS/virtual-machine-interfaces\
        | python3 -m json.tool | grep $vm_prefix`
    local vmis_stripped=""
    for vmi in $myvmis
    do
        local tmp=${vmi#*\"}
        local v=${tmp%\"*}
        vmis_stripped="$v $vmis_stripped"
    done
    delete_vm_interfaces "$vmis_stripped"
}

function prefix_delete_ip_instances(){
#this deletes all ipi's with a given prefix
    local ipi_prefix=$1
    local myipis=`curl $REST_ADDRESS/instance-ips\
        | python3 -m json.tool | grep $ipi_prefix`
    local ipis_stripped=""
    for ipi in $myipis
    do
        local tmp=${ipi#*\"}
        local i=${tmp%\"*}
        ipis_stripped="$i $ipis_stripped"
    done
    delete_instance_ips "$ipis_stripped"
}

function delete_logical_router() {
    local lr_name="$1"
    local nw_names="$2"
    local lr_fqname=`name_to_fqname $lr_name`
    local lr_uuid=`fqname_to_uuid "$lr_fqname" "logical-router"`

    for nw_name in $nw_names
    do
        local vmi_lrname="vmi-lr-""$lr_name"-"$nw_name"
        local ipi_lrname="ipi-lr-""$lr_name"-"$nw_name"
        local vmi_fqname=`name_to_fqname $vmi_lrname`
        local ipi_fqname=`name_to_fqname $ipi_lrname`
        local vmi_uuid=`fqname_to_uuid "$vmi_fqname" "virtual-machine-interface"`
        local ipi_uuid=`fqname_to_uuid "$ipi_fqname" "instance-ip"`

        if [ "$ipi_uuid" != "" ] && [ "$vmi_uuid" != "" ]
        then
            del_reference "$ipi_uuid" "instance-ip" "$vmi_uuid" "virtual-machine-interface"
        fi
        if [ "$lr_uuid" != "" ] && [ "$vmi_uuid" != "" ]
        then
            del_reference "$lr_uuid" "logical-router" "$vmi_uuid" "virtual-machine-interface"
        fi
        
        delete_instance_ips "$ipi_lrname"
        delete_vm_interfaces "$vmi_lrname"
    done

    delete_entity "$lr_uuid" "logical-router"
}

function delete_intf_route_table() {
    local irt_name="$1"
    local irt_fqname=`name_to_fqname "$irt_name"`
    local irt_uuid=`fqname_to_uuid "$irt_fqname" "interface-route-table"`
    if [ "$irt_uuid" != "" ]
    then
        delete_entity "$irt_uuid" "interface-route-table"
    fi
}

## @brief A guard variable to prevent recursive execution of basic_rest_functions.sh
export BASIC_REST_FUNCTIONS=

#
#END-OF-FILE
#

