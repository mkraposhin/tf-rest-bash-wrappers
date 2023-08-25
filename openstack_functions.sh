#!/usr/bin/bash

#
# Check that this script is not loaded second time
if [[ -v OPENSTACK_FUNCTIONS ]]
then
    echo "The file openstack_functions has been already sourced"
    echo "Can not proceed"
    exit 0
fi

#
# Get OpenStack credentials
if [ ! -f ./admin-openrc.sh ]
then
    echo "Can not find ./admin-openrc.sh"
    echo "Can not proceed"
    exit 0
fi
source ./admin-openrc.sh

#
# Constants and a configuration
#
vms_list=()
if [[ -v vms0 ]]
then
    vms_list=("${vms0[@]}")
fi
ports_list=()
if [[ -v ports0 ]]
then
    ports_list=("${ports0[@]}")
fi

##
## @val_in_array determines whether a given string value is
## stored in any element of the given array
function val_in_array(){
    local all_args=("$@")
    local val=$1
    local arr=("${all_args[@]:1}")
    for a in ${arr[@]}
    do
        if [ "$a" = "$val" ]
        then
            echo "yes"
            return
        fi
    done
    echo "no"
}

##
## @plus_port connects a TF's VMI (virtual machine interface) to the
## given OpenStack's VM (virtual machine)
function plus_port(){
    args=("$@")
    q=0
    for port in ${args[@]}
    do
        if [ `val_in_array $port ${ports_list[@]}` = "yes" ];
        then
            openstack server add port ${vms_list[$q]} $port
        fi
        q=`expr $q + 1`
    done
}

##
## @minus port disconnects a TF's VMI (virtual machine interface) to the
## given OpenStack's VM (virtual machine)
function minus_port(){
    local args=("$@")
    local q=0
    for port in ${args[@]}
    do
        if [ `val_in_array $port ${ports_list[@]}` = "yes" ];
        then
            openstack server remove port ${vms_list[$q]} $port
        fi
        q=`expr $q + 1`
    done
}

export OPENSTACK_FUNCTIONS=
#
#END-OF-FILE
#
