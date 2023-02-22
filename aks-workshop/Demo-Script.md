Demo Script
===========

Show the running app already deployed to AKS
--------------------------------------------

Go to ingresses in Azure portal AKS resource view, or:

```sh
kubectl get ingress rating-web -n ratingsapp-dev

# Go to https://aksworkshop24698.australiaeast.cloudapp.azure.com
```

Start MongoDB port-forwarding:

```sh
kubectl port-forward --namespace ratingsapp-dev svc/mongodb 27017:27017 &
```

Open Mongo Compass and browse the DB and collections.

Cluster overview – Azure Portal resource views, Resource Group, Node Resource Group
-----------------------------------------------------------------------------------

Open Azure Portal in browser: https://portal.azure.com/

* Navigate to "aksworkshop" resource group.
* Show the resources
* Select AKS resource
* Run through main views/properties:
  * Node pools
  * Cluster configuration
  * Networking
* Explore Kubernetes resources blade
  * Services and ingresses
  * Deployments
    * Filter to namespace of ratings-api, drill down to pod
    * YAML configuration
    * Live Logs
  * Storage

Make a code change, build and deploy app to cluster
---------------------------------------------------

Make a change to file: `rating-web/src/App.vue`:

```css
// main css
body {
  background-color: #0071c5;
```

to

```css
// main css
body {
  background-color: #999;
```

Build the container image:

```sh
cd rating-web/
docker build -t rating-web -f Dockerfile .
```

Show the Docker Compose file: `rating-web/docker-compose`

Ensure mongodb port forwarding is not running in the background.

Run Docker Compose in the rating-web root dir:

```sh
docker-compose up
```

Open local web app: http://localhost:8081

Submit some votes.

Open local MongoDB in MongoDB Compass.

Optional: Run Playwright tests

```sh
cd test/
npx playwright test --headed
cd ..
```

Cleanup Docker Compose containers:

```sh
# CTRL+C in rating-web
docker-compose down
```

Show vscode Kubernetes extension
--------------------------------

Show VSCode Kubenretews extension:

* Select cluster
* Choose namespace
* Select rating-web pod
* Open terminal to the container

Publish changed rating-web image to ACR with new tag
----------------------------------------------------

```sh
az acr list -o table

RESOURCE_GROUP=aksworkshop
ACR_NAME=acr27749

az acr build \
    --resource-group $RESOURCE_GROUP \
    --registry $ACR_NAME \
    --image ratings-web:v2 \
    .
```

Go to Azure Portal / Container Registry / Tasks and view the build in action.

Show update Repository tags for the ratring-web image.

Deploy app to AKS with Helm Charts with new image tag to new namespace
----------------------------------------------------------------------

```sh
cd rating-web/

ACR_NAME=acr27749
NAMESPACE=ratingsapp-dev

CHART_REPOSITORY="oci://$ACR_NAME.azurecr.io/helm/rating-web"
CHART_VERSION="0.1.0"
IMAGE_REPOSITORY="${ACR_NAME}.azurecr.io/ratings-web"
IMAGE_TAG="v2"

OCI_USER_NAME="00000000-0000-0000-0000-000000000000"
OCI_PASSWORD=$(az acr login --name $ACR_NAME --expose-token --output tsv --query accessToken)

helm registry login $ACR_NAME.azurecr.io --username $OCI_USER_NAME --password $OCI_PASSWORD

helm template rating-web ${CHART_REPOSITORY} \
    --namespace ${NAMESPACE} \
    --create-namespace \
    --version ${CHART_VERSION} \
    --values ./rating-web-values.yaml \
    --set image.repository="${IMAGE_REPOSITORY}" \
    --set image.tag="${IMAGE_TAG}" \
    --set env.ratings_api_uri="${RATING_API_URI}"

# In another terminal start a watch on pods:
watch -n 2 kubectl get pods -n ratingsapp-dev

helm upgrade --install rating-web ${CHART_REPOSITORY} \
    --namespace ${NAMESPACE} \
    --create-namespace \
    --version ${CHART_VERSION} \
    --values ./rating-web-values.yaml \
    --set image.repository="${IMAGE_REPOSITORY}" \
    --set image.tag="${IMAGE_TAG}" \
    --set env.ratings_api_uri="${RATING_API_URI}"

helm ls -A
```

Show desired state and pod replicas
-----------------------------------

Whilst the watch is going in the other terminal:

* Select the rating-web pod name and kill it (see ContainerCreating for new one).
* Quickly test the app in the browser and you get a 503 error.
* Try again after a while and it works.

Show helm values file (`rating-web/values.yaml`) replicaCount, change this to 3 via `--set replicaCount=3`:

```sh
helm upgrade --install rating-web ${CHART_REPOSITORY} \
    --namespace ${NAMESPACE} \
    --create-namespace \
    --version ${CHART_VERSION} \
    --values ./rating-web-values.yaml \
    --set image.repository="${IMAGE_REPOSITORY}" \
    --set image.tag="${IMAGE_TAG}" \
    --set env.ratings_api_uri="${RATING_API_URI}" \
    --set replicaCount=3
```

See the new replicas come up in the watch terminal.

Kill one of the pods and reload the app in the browser, it should work as a healthy replica should be up.

Mention liveness and readiness probes can help and show current ones:

```sh
kubectl describe deploy/rating-web -n ratingsapp-dev
kubectl get deploy/rating-web -n ratingsapp-dev -o yaml

helm template rating-web ${CHART_REPOSITORY} \
    --namespace ${NAMESPACE} \
    --create-namespace \
    --version ${CHART_VERSION} \
    --values ./rating-web-values.yaml \
    --set image.repository="${IMAGE_REPOSITORY}" \
    --set image.tag="${IMAGE_TAG}" \
    --set env.ratings_api_uri="${RATING_API_URI}"
```

Revert back to 1 replica and the old image tag to see the original app:

```sh
IMAGE_TAG="v1"

helm upgrade --install rating-web ${CHART_REPOSITORY} \
    --namespace ${NAMESPACE} \
    --create-namespace \
    --version ${CHART_VERSION} \
    --values ./rating-web-values.yaml \
    --set image.repository="${IMAGE_REPOSITORY}" \
    --set image.tag="${IMAGE_TAG}" \
    --set env.ratings_api_uri="${RATING_API_URI}" \
    --set replicaCount=1
```

Walkthrough of components / code
--------------------------------

* Helm charts (values, templates, etc.)
  * Overriding default values file
* Dockerfiles

Container Registry
------------------

Views, repositories, builds

Security

* Vulnerabilities
* See CVE, Remediation, Affected resourcves
* Click Take action
* Select Rating Web and view vulnerabilities

Microsoft Defender
------------------

Go to Microsoft Defender in the Azure Portal.

* Security Posture
  * View Recommendations
  * Filter to Resource Group "aksworkshop"

* Security alerts
  * View AKS related alerts and recommendations

Azure Monitor (Container Insights)
----------------------------------

Go to AKS resource / Insights in the Azure Portal.

* Health, nodes, pods, live logs, metrics, recommended alerts
* Go to Contaihners, filter by namespace "ratingsapp-dev", filter to "api"
* Open Live Logs, submit a rating in the web app
* Reports
  * Workload Details
  * Data Usage
  * Persistent Volume Details
* Recommended alerts
* Logs

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

AKS Diagnose and solve problems
-------------------------------

Quick overview of this feature.
