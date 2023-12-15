# TF REST bash wrappers
A set of bash scripts wrapping REST commands for Tungsten Fabric

## Purpose of the repository

This repository provides bash functions to configure Tungsten Fabric (TF)
virtual networks and other entities. The REST API used in TF is very diverse
and requires a lot of input. Therefore, the more concise tool to manipulate
a TF configuation is needed.

## Examples of usage

### Creation and deleteion of a virtual network

First we create a network **nw1** with 1 subnet aaaa::/32:

    create_network "nw1" "aaaa::/32"

This network can be deleted with:

    delete_networks "nw1"

### Creation and deletion of several virtual networks

First we create networka **nwa** and **nwb** with subnets aaaa::/32
bbbb::/32:

    create_network "nwa" "aaaa::/32"
    create_network "nwb" "bbbb::/32"

These networks can be then deleted with the command:

    delete_networks "nwa,nwb"

### Creation and deletion of a virtual port (virtual machine interface) with IP address

As the first step, we create virtual network **nw1** and obtain it's
subnet UUID:

    create_network "nw1" "1111::/32"
    local nw_subnet_uuid=`network_ipam_subnets "nw1"`

Then we create a virtual machine interface **vmi1** in virtual network **nw1**:

    create_vm_interface "vmi1" "nw1"

Finally, we create in instance ip **iip1** with IPv6 address "1111::11" (
from 1111::/32 subnet of **nw1** network) and associate it with **vmi1**:

    create_instance_ip "iip1" "nw1" "$nw_subnet_uuid" "1111::11"
    link_iip_with_vmi "iip1" "vmi1"

The created entities should be deleted in the reversed order:
    
    delete_instance_ips "iip1"
    delete_vm_interfaces "vmi1"
    delete_networks "nw1"

