#!/bin/bash

if [ -f .random-seed ]; then
    seed=$(echo $(cat .random-seed))
else
    seed=$RANDOM
    echo $seed > .random-seed
fi

echo "Random seed: $seed"

export RESOURCE_GROUP=aksworkshop
export REGION_NAME=australiaeast

# ACR registry
export ACR_NAME=acr$seed

# AKS cluster
export AKS_CLUSTER_NAME=aksworkshop-$seed
export NODE_COUNT=2

# Networking
export SUBNET_NAME=aks-subnet
export VNET_NAME=aks-vnet
export VNET_CIDR="10.0.0.0/8"
export AKS_SUBNET_CIDR="10.240.0.0/16"
export SERVICE_CIDR="10.2.0.0/24"
export DNS_IP="10.2.0.10"
export DOCKER_BRIDGE_CIDR="172.17.0.1/16"
export NSG_NAME="$VNET_NAME-$SUBNET_NAME-nsg-$REGION_NAME"

# Addons
export ADD_ONS="monitoring"
