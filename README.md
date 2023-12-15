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

