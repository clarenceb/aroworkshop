AKS Workshop
============

This is based on the ARO workshop: https://github.com/microsoft/aroworkshop

See AKS changes in this directory: https://github.com/clarenceb/aroworkshop/aks-workshop

Since both ARO and AKS are Kubernetes, many of the steps are similar with ARO and AKS having specific integartions which are different.

(Optional) Local build and test
-------------------------------

Pre-requisites:

* Start docker desktop (or have a local docker environment available)

Build the ratings-api and ratings-web container images:

```sh
git clone https://github.com/clarenceb/rating-api
cd rating-api
docker build -t rating-api -f Dockerfile.k8s .

cd ..
git clone https://github.com/clarenceb/rating-web
cd rating-web
docker build -t rating-web -f Dockerfile .
```

Run services and local db with docker-compose:

```sh
docker-compose up -d
# Access the rating-web UI at http://localhost:8081/
```

Run the Rating API tests:

```sh
cd rating-api/
./run-tests.ps1

# Or with powershell:
powershell ./run-tests.ps1
```

Install playwright and dependencies for the UI tests:

```sh
cd .../rating-web/
npm install
npx playwright install
npx playwright install msedge
```

Run the Rating Web tests:

```sh

npx playwright test           # headless browser tests
npx playwright test --headed  # to view browser interaction
```

Teardown running containers:

```sh
docker-compose down
```

AKS cluster setup
-----------------

Create an Azure CNI-based cluster with Azure network policy enabled.

```sh
source ./workshop-env.sh

# Create resource group for all the resources
az group create \
    --name $RESOURCE_GROUP \
    --location $REGION_NAME

# Create a default network security group
az network nsg create -g $RESOURCE_GROUP -n $NSG_NAME

# Create the VNET for AKS to use with Azure CNI networking
az network vnet create \
    --resource-group $RESOURCE_GROUP \
    --location $REGION_NAME \
    --name $VNET_NAME \
    --address-prefixes $VNET_CIDR \
    --subnet-name $SUBNET_NAME \
    --subnet-prefixes $AKS_SUBNET_CIDR \
    --nsg $NSG_NAME

# Allocate a subnet for AKS nodes and pods to use
SUBNET_ID=$(az network vnet subnet show \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --name $SUBNET_NAME \
    --query id -o tsv)

# Get the latest AKS version available for our chosen region
VERSION=$(az aks get-versions \
    --location $REGION_NAME \
    --query 'orchestrators[?!isPreview] | [-1].orchestratorVersion' \
    --output tsv)

# Create the AKS cluster
az aks create \
--resource-group $RESOURCE_GROUP \
--name $AKS_CLUSTER_NAME \
--node-count $NODE_COUNT \
--location $REGION_NAME \
--kubernetes-version $VERSION \
--network-plugin azure \
--network-policy azure \
--vnet-subnet-id $SUBNET_ID \
--service-cidr $SERVICE_CIDR \
--dns-service-ip $DNS_IP \
--docker-bridge-address $DOCKER_BRIDGE_CIDR \
--enable-addons $ADD_ONS \
--enable-managed-identity \
--generate-ssh-keys

# Retrieve credentials to access the cluster control plane
az aks get-credentials \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --overwrite-existing

# Test cluster connectivity by using kubectl
kubectl get nodes
```

Create a private, highly available container registry
-----------------------------------------------------

```sh
az acr create \
    --resource-group $RESOURCE_GROUP \
    --location $REGION_NAME \
    --name $ACR_NAME \
    --sku Standard
```

Configure ACR authentication for AKS cluster
--------------------------------------------

```sh
az aks update \
    --name $AKS_CLUSTER_NAME \
    --resource-group $RESOURCE_GROUP \
    --attach-acr $ACR_NAME
```

Build the Ratings API image using an ACR build task
---------------------------------------------------

```sh
az acr build \
    --resource-group $RESOURCE_GROUP \
    --registry $ACR_NAME \
    --image ratings-api:v1 \
    https://github.com/clarenceb/rating-api
```

Build the Ratings web image using an ACR build task
---------------------------------------------------

```sh
az acr build \
    --resource-group $RESOURCE_GROUP \
    --registry $ACR_NAME \
    --image ratings-web:v1 \
    https://github.com/clarenceb/rating-web
```

Verify ACR images and tags
--------------------------

```sh
az acr repository list \
    --name $ACR_NAME \
    --output table

az acr repository show-tags -n $ACR_NAME --repository ratings-api
az acr repository show-tags -n $ACR_NAME --repository ratings-web
```

Deploy MongoDB (in-cluster)
---------------------------

```sh
helm install mongodb bitnami/mongodb \
    --namespace ratingsapp-dev \
    --set persistence.enabled=true \
    --set auth.usernames={ratingsuser}  \
    --set auth.password=ratingspassword \
    --set auth.databases={ratingsdb}  \
    --set auth.rootPassword=ratingspassword
```

MongoDB; can be accessed on the following DNS name(s) and ports from within your cluster:

```sh
mongodb.ratingsapp-dev.svc.cluster.local
```

To get the root password run:

```sh
export MONGODB_ROOT_PASSWORD=$(kubectl get secret --namespace ratingsapp-dev mongodb -o jsonpath="{.data.mongodb-root-password}" | base64 -d)
```

To get the password for "ratingsuser" run:

```sh
export MONGODB_PASSWORD=$(kubectl get secret --namespace ratingsapp-dev mongodb -o jsonpath="{.data.mongodb-passwords}" | base64 -d | awk -F',' '{print $1}')
```

To connect to your database, create a MongoDB; client container:

```sh
kubectl run --namespace ratingsapp-dev mongodb-client --rm --tty -i --restart='Never' --env="MONGODB_ROOT_PASSWORD=$MONGODB_ROOT_PASSWORD" --image docker.io/bitnami/mongodb:5.0.9-debian-11-r3 --command -- bash
```

Then, run the following command:

```sh
mongosh admin --host "mongodb" --authenticationDatabase admin -u root -p $MONGODB_ROOT_PASSWORD

show dbs
exit
```

To connect to your database from outside the cluster execute the following commands:

```sh
kubectl port-forward --namespace ratingsapp-dev svc/mongodb 27017:27017 &
mongosh --host 127.0.0.1 --authenticationDatabase admin -u root -p $MONGODB_ROOT_PASSWORD
```

To connect to the ratings DB:

```sh
mongosh --host 127.0.0.1/ratingsdb --authenticationDatabase admin -u ratingsuser -p $MONGODB_PASSWORD

show dbs
exit
```

To install `mongosh` see: https://www.mongodb.com/docs/mongodb-shell/install/

Download a MongoDB archive with pre-loaded data from: https://github.com/clarenceb/rating-api/raw/master/data.tar.gz

Install the mongo database tools: https://www.mongodb.com/docs/database-tools/installation/installation-linux/

You can also install [MongoDB Compass](https://www.mongodb.com/products/compass) for a desktop UI app to connect to Mongo DB instances.

Check MongoDB persistent storage is in place:

```sh
kubectl get pvc,pv -n ratingsapp-dev
```

Test app deployment from local Helm charts
------------------------------------------

Create the Kubernetes namespace for the dev environment of the application:

```sh
kubectl create namespace ratingsapp-dev
kubectl get namespace
```

The Helm chart for Ratings API is located in the `rating-api` git repo: https://github.com/clarenceb/rating-api/tree/master/rating-api

Ratings API:

```sh
cd rating-api/

NAMESPACE=ratingsapp-dev
IMAGE_REPOSITORY="${ACR_NAME}.azurecr.io/ratings-api"
MONGODB_USER=ratingsuser
MONGODB_PASSWORD=ratingspassword
MONGODB_URI="mongodb://${MONGODB_USER}:${MONGODB_PASSWORD}@mongodb.${NAMESPACE}.svc.cluster.local:27017/ratingsdb"

# Render a preview of the Helm chart as YAML
helm template rating-api ./rating-api \
    --namespace ${NAMESPACE} \
    --set image.repository="${IMAGE_REPOSITORY}" \
    --set env.database_uri="${MONGODB_URI}"

# Install the Helm chart
helm upgrade --install rating-api ./rating-api \
    --namespace ${NAMESPACE} \
    --set image.repository="${IMAGE_REPOSITORY}" \
    --set env.database_uri="${MONGODB_URI}"

helm ls -n ratingsapp-dev
kubectl get all -n ratingsapp-dev

# Check ratings api logs to see it populated data correctly
kubectl logs -n ratingsapp-dev $(kubectl get pod -n ratingsapp-dev -l app.kubernetes.io/name=rating-api -o name)

# Port-forward to the Ratings API to test it is working
kubectl port-forward -n ratingsapp-dev svc/rating-api 8080:8080

# Test one of the ratings api endpoints
curl http://localhost:8080/api/items

# Run the integration tests against the deployed version
./test/run-tests.ps1
```

The Helm chart for Ratings Web is located in the `rating-web` git repo: https://github.com/clarenceb/rating-web/tree/master/rating-web

Ratings Web:

```sh
cd rating-web/

NAMESPACE=ratingsapp-dev
IMAGE_REPOSITORY="${ACR_NAME}.azurecr.io/ratings-web"
RATING_API_URI="http://rating-api:8080"

# Render a preview of the Helm chart as YAML
helm template rating-web ./rating-web \
    --namespace ${NAMESPACE} \
    --set image.repository="${IMAGE_REPOSITORY}" \
    --set env.ratings_api_uri="${RATING_API_URI}"

# Install the Helm chart
helm upgrade --install rating-web ./rating-web \
    --namespace ${NAMESPACE} \
    --set image.repository="${IMAGE_REPOSITORY}" \
    --set env.ratings_api_uri="${RATING_API_URI}"

helm ls -n ratingsapp-dev
kubectl get all -n ratingsapp-dev

# Check ratings api logs to see it populated data correctly
kubectl logs -n ratingsapp-dev $(kubectl get pod -n ratingsapp-dev -l app.kubernetes.io/name=rating-web -o name)

# Port-forward to the Ratings Web to test it is working
kubectl port-forward -n ratingsapp-dev svc/rating-web 8081:8080

# Test one of the ratings web home page
curl http://localhost:8081/

# Open browser to http://localhost:8081/

# Run the integration tests against the deployed version
# (see: https://github.com/clarenceb/rating-web/blob/master/test/README.md for how to set up env to run tests)
cd test/
npx playwright test
npx playwright test --headed   # Or via launching a browser
```

Store Helm charts as artifacts in ACR
-------------------------------------

Package and store Ratings API helm chart in ACR:

```sh
cd rating-api/
helm package rating-api

# See other ways to authenicate: https://docs.microsoft.com/en-us/azure/container-registry/container-registry-helm-repos#authenticate-with-the-registry
USER_NAME="00000000-0000-0000-0000-000000000000"
PASSWORD=$(az acr login --name $ACR_NAME --expose-token --output tsv --query accessToken)

helm registry login $ACR_NAME.azurecr.io --username $USER_NAME --password $PASSWORD
helm push rating-api-0.1.0.tgz oci://$ACR_NAME.azurecr.io/helm
az acr repository show --name $ACR_NAME --repository helm/rating-api
az acr manifest list-metadata --registry $ACR_NAME --name helm/rating-api
```

Package and store Ratings Web helm chart in ACR:

```sh
cd rating-web/
helm package rating-web

# See other ways to authenicate: https://docs.microsoft.com/en-us/azure/container-registry/container-registry-helm-repos#authenticate-with-the-registry
USER_NAME="00000000-0000-0000-0000-000000000000"
PASSWORD=$(az acr login --name $ACR_NAME --expose-token --output tsv --query accessToken)

helm registry login $ACR_NAME.azurecr.io --username $USER_NAME --password $PASSWORD
helm push rating-web-0.1.0.tgz oci://$ACR_NAME.azurecr.io/helm
az acr repository show --name $ACR_NAME --repository helm/rating-web
az acr manifest list-metadata --registry $ACR_NAME --name helm/rating-web
```

Deploy from Helm charts stored in ACR
-------------------------------------

```sh
CHART_REPOSITORY="oci://$ACR_NAME.azurecr.io/helm/rating-api"
CHART_VERSION="0.1.0"
IMAGE_REPOSITORY="${ACR_NAME}.azurecr.io/ratings-api"
IMAGE_TAG="v1"

# Render a preview of the Helm chart as YAML
helm template rating-api ${CHART_REPOSITORY} \
    --namespace ${NAMESPACE} \
    --version ${CHART_VERSION} \
    --set image.repository="${IMAGE_REPOSITORY}" \
    --set image.tag="${IMAGE_TAG}" \
    --set env.database_uri="${MONGODB_URI}"

# Install the Helm chart
helm upgrade --install rating-api ${CHART_REPOSITORY} \
    --namespace ${NAMESPACE} \
    --version ${CHART_VERSION} \
    --set image.repository="${IMAGE_REPOSITORY}" \
    --set image.tag="${IMAGE_TAG}" \
    --set env.database_uri="${MONGODB_URI}"

helm ls --namespace ${NAMESPACE}
helm get manifest rating-api -n ${NAMESPACE}

CHART_REPOSITORY="oci://$ACR_NAME.azurecr.io/helm/rating-web"
CHART_VERSION="0.1.0"
IMAGE_REPOSITORY="${ACR_NAME}.azurecr.io/ratings-web"
IMAGE_TAG="v1"

# Render a preview of the Helm chart as YAML
helm template rating-web ${CHART_REPOSITORY} \
    --namespace ${NAMESPACE} \
    --version ${CHART_VERSION} \
    --set image.repository="${IMAGE_REPOSITORY}" \
    --set image.tag="${IMAGE_TAG}" \
    --set env.ratings_api_uri="${RATING_API_URI}"

# Install the Helm chart
helm upgrade --install rating-web ${CHART_REPOSITORY} \
    --namespace ${NAMESPACE} \
    --version ${CHART_VERSION} \
    --set image.repository="${IMAGE_REPOSITORY}" \
    --set image.tag="${IMAGE_TAG}" \
    --set env.ratings_api_uri="${RATING_API_URI}"

helm ls --namespace ${NAMESPACE}
helm get manifest rating-api -n ${NAMESPACE}
```

References
----------

* https://docs.microsoft.com/en-us/learn/modules/aks-workshop/
