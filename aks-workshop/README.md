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

# Create the AKS cluster
az aks create \
--resource-group $RESOURCE_GROUP \
--name $AKS_CLUSTER_NAME \
--node-count $NODE_COUNT \
--location $REGION_NAME \
--network-plugin azure \
--network-policy azure \
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
    --create-namespace \
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
helm get manifest rating-web -n ${NAMESPACE}
```

Install Ingress Controller
--------------------------

```sh
NGINX_CHART_VERSION=4.1.3

helm upgrade --install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace $NAMESPACE \
  --create-namespace \
  --version $NGINX_CHART_VERSION \
  --set controller.nodeSelector."kubernetes\.io/os"=linux \
  --set controller.admissionWebhooks.patch.nodeSelector."kubernetes\.io/os"=linux \
  --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \
  --set controller.replicaCount=2 \
  --set controller.nodeSelector."kubernetes\.io/os"=linux \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-dns-label-name"=$DNS_LABEL

EXTERNAL_IP=$(kubectl --namespace ingress-basic get services nginx-ingress-ingress-nginx-controller -o jsonpath="{.status.loadBalancer.ingress[0].ip}")

# Get the resource-id of the public ip
PUBLICIPID=$(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$EXTERNAL_IP')].[id]" --output tsv)

# Display the FQDN
INGRESS_FQDN=$(az network public-ip show --ids $PUBLICIPID --query "[dnsSettings.fqdn]" --output tsv)

echo "NGINX Ingress - DNS FQDN (External IP): $INGRESS_FQDN ($EXTERNAL_IP)"
```

Deploy Rating api and web with an ingress resources:

```sh
NAMESPACE=ratingsapp-dev
RATING_API_URI="http://rating-api:8080"
MONGODB_USER=ratingsuser
MONGODB_PASSWORD=ratingspassword
MONGODB_URI="mongodb://${MONGODB_USER}:${MONGODB_PASSWORD}@mongodb.${NAMESPACE}.svc.cluster.local:27017/ratingsdb"

CHART_REPOSITORY="oci://$ACR_NAME.azurecr.io/helm/rating-api"
CHART_VERSION="0.1.0"
IMAGE_REPOSITORY="${ACR_NAME}.azurecr.io/ratings-api"
IMAGE_TAG="v1"

helm upgrade --install rating-api ${CHART_REPOSITORY} \
    --namespace ${NAMESPACE} \
    --create-namespace \
    --version ${CHART_VERSION} \
    --set image.repository="${IMAGE_REPOSITORY}" \
    --set image.tag="${IMAGE_TAG}" \
    --set env.database_uri="${MONGODB_URI}" \
    --set ingress.enabled=true \
    --set "ingress.hosts[0].host=$INGRESS_FQDN,ingress.hosts[0].paths[0].pathType=Prefix,ingress.hosts[0].paths[0].path=/api" \
    --set ingress.className=nginx

CHART_REPOSITORY="oci://$ACR_NAME.azurecr.io/helm/rating-web"
CHART_VERSION="0.1.0"
IMAGE_REPOSITORY="${ACR_NAME}.azurecr.io/ratings-web"
IMAGE_TAG="v1"

helm upgrade --install rating-web ${CHART_REPOSITORY} \
    --namespace ${NAMESPACE} \
    --create-namespace \
    --version ${CHART_VERSION} \
    --set image.repository="${IMAGE_REPOSITORY}" \
    --set image.tag="${IMAGE_TAG}" \
    --set env.ratings_api_uri="${RATING_API_URI}" \
    --set ingress.enabled=true \
    --set "ingress.hosts[0].host=$INGRESS_FQDN,ingress.hosts[0].paths[0].pathType=Prefix,ingress.hosts[0].paths[0].path=/" \
    --set ingress.className=nginx
```

Access the ratings web site at: `http://$INGRESS_FQDN`

Configure TLS on Ingress
------------------------

Install Cert-Manager:

```sh
kubectl label namespace ingress-basic cert-manager.io/disable-validation=true

# See: https://artifacthub.io/packages/helm/cert-manager/cert-manager
CERT_MANAGER_TAG="v1.8.2"

helm install cert-manager jetstack/cert-manager \
  --namespace ingress-basic \
  --version $CERT_MANAGER_TAG \
  --set installCRDs=true \
  --set nodeSelector."kubernetes\.io/os"=linux
```

Create the CA cluster issuer:

```sh
export EMAIL_ADDRESS="<your-email-address>"
envsubst < ./ca-issuer.yaml | kubectl apply -n ingress-basic -f -

kubectl get ClusterIssuer -A
kubectl describe ClusterIssuer letsencrypt -n ingress-basic
```

Install/Update Ratings API to use Lets Encrypt TLS certificate:

```sh
NAMESPACE=ratingsapp-dev
RATING_API_URI="http://rating-api:8080"
MONGODB_USER=ratingsuser
MONGODB_PASSWORD=ratingspassword
MONGODB_URI="mongodb://${MONGODB_USER}:${MONGODB_PASSWORD}@mongodb.${NAMESPACE}.svc.cluster.local:27017/ratingsdb"

CHART_REPOSITORY="oci://$ACR_NAME.azurecr.io/helm/rating-api"
CHART_VERSION="0.1.0"
IMAGE_REPOSITORY="${ACR_NAME}.azurecr.io/ratings-api"
IMAGE_TAG="v1"

cat << EOF > rating-api-values.yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
  hosts:
    - host: $INGRESS_FQDN
      paths:
        - path: /api
          pathType: Prefix
  tls:
    - secretName: rating-api-tls
      hosts:
        - $INGRESS_FQDN
EOF

helm upgrade --install rating-api ${CHART_REPOSITORY} \
    --namespace ${NAMESPACE} \
    --create-namespace \
    --version ${CHART_VERSION} \
    --values ./rating-api-values.yaml \
    --set image.repository="${IMAGE_REPOSITORY}" \
    --set image.tag="${IMAGE_TAG}" \
    --set env.database_uri="${MONGODB_URI}"

kubectl describe ClusterIssuer letsencrypt -n ingress-basic

cat << EOF > rating-web-values.yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
  hosts:
    - host: $INGRESS_FQDN
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: rating-api-tls
      hosts:
        - $INGRESS_FQDN
EOF

CHART_REPOSITORY="oci://$ACR_NAME.azurecr.io/helm/rating-web"
CHART_VERSION="0.1.0"
IMAGE_REPOSITORY="${ACR_NAME}.azurecr.io/ratings-web"
IMAGE_TAG="v1"

helm upgrade --install rating-web ${CHART_REPOSITORY} \
    --namespace ${NAMESPACE} \
    --create-namespace \
    --version ${CHART_VERSION} \
    --values ./rating-web-values.yaml \
    --set image.repository="${IMAGE_REPOSITORY}" \
    --set image.tag="${IMAGE_TAG}" \
    --set env.ratings_api_uri="${RATING_API_URI}"
```

Azure Monitor
-------------

Ensure Monitoring addon is enabled in AKS.

Enter a few votes in the Ratings Web app.

Investigate "Insights" blade:

* Cluster
* Reports
* Nodes
* Controllers
* Containers
  * Live Logs / Events (for Ratings API)
* Recommended Alerts

Open the KQL query editor in the "Logs" blade of the AKS resource and try some queries.

Investigate some app logs where votes were placed:

```kql
ContainerLog
| where LogEntry contains "Saving rating"
```

See average rating per fruit:

```kql
ContainerLog
| where LogEntry contains "Saving rating"
| parse LogEntry with * "itemRated: [ " itemCode " ]" * "rating: " rating " }" *
| extend fruit=
    replace_string(
        replace_string(
            replace_string(
                replace_string(itemCode, '62d4e1eee463c40010474b70', 'Banana'),
            '62d4e1eee463c40010474b71', 'Coconut'),
        '62d4e1eee463c40010474b72', 'Oranges'),
    '62d4e1eee463c40010474b73', 'Pineapple')
| project fruit, rating
| summarize AvgRating=avg(toint(rating)) by fruit
```

Choose "Chart" to see a visualisation of the average votes.

Note: Your item ids will be different.  Run a Mongo query to find your ids, like so:

```sh
kubectl port-forward --namespace ratingsapp-dev svc/mongodb 27017:27017 &
mongosh --host 127.0.0.1 --authenticationDatabase admin -u root -p $MONGODB_ROOT_PASSWORD

use ratingsdb
db.items.find()
quit

kill %1
```

See number of votes submitted over time:

```sh
ContainerLog
| where LogEntry contains "Saving rating"
| summarize NumberOfVotes=count()/4 by bin(TimeGenerated, 15m)
| render areachart
```

Some cluster-level logs:

See deleted objects (e.g. delete some pods):

```kql
AzureDiagnostics
| where Category == 'kube-audit'
| extend log=parse_json(log_s)
| where log.verb == 'delete'
| where log.objectRef.resource == 'pods'
| project requestURI=log.requestURI, user=log.user.username, verb=log.verb
| limit 100
```

Kube event failures:

```kql
KubeEvents
| where TimeGenerated > ago(24h)
| where Reason in ("Failed")
| summarize count() by Reason, bin(TimeGenerated, 5m)
| render areachart
```

Pod failures (e.g. ImagePullBackOff):

```kql
KubeEvents
| where TimeGenerated > ago(24h)
| where Reason in ("Failed")
| where ObjectKind == "Pod"
| project TimeGenerated, ObjectKind, Name, Namespace, Message
```

Try some other KQL queries in [kql-container-insights.md](./kql-container-insights.md)

References
----------

* https://docs.microsoft.com/en-us/learn/modules/aks-workshop/
