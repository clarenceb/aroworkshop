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
export NODE_COUNT=3

# Networking
export SUBNET_NAME=aks-subnet
export VNET_NAME=aks-vnet

# Addons
export ADD_ONS="monitoring"
