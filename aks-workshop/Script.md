Demo script
===========

Here are a suggestion list of topics to discuss as part of the application walkthrough:

* Application walkthrough - show the actual deployed app in action
* Examine Azure resources in Azure portal
* Kubernetes object view in Azure Portal
* Review Infrastructure as Code
    * Bicep files
* Review application code
    * Dockerfile
* Local Docker
    * Build image
    * Run image
    * Docker Compose
    * KIND
* Review Kubernetes manifests
    * Deployments
    * Config
    * Secrets
    * Ingress
* Ingress controller
* Cert-manager
    * Issuer
    * Certificate
* Kubernetes
    * Deployments
    * Pods - replicas, lifecycle (delete a pod, scale pods)
    * Services
    * Ingress
    * Probes
    * kubectl apply (make a change)
    * kubectl ns, pods, deployments, etc.
* Kubernetes CLI (kubectl)
* Kubernetes UI (Azure Portal, Lens - 3pp)
* CI/CD - Bicep, Image, Deploy
* Monitoring, logging, and alerting

Extensions
----------

* AKS Enterprise Landing Zones
* GitOps
* Cluster Security
  * Azure Policy
  * Network Policy
  * OSM
  * Security Contexts
  * Egress Lockdown (via UDR to Azure Firewall)
* Upgrades
* Backup
* DR
* ASO v2 - Cosmos Mongo API

Docker 101
----------

```sh
dotnet new webapp -f net6.0 -n demo --no-https
cd demo
dotnet run
```

Create Dockerfile:

```Dockerfile
# https://hub.docker.com/_/microsoft-dotnet
FROM mcr.microsoft.com/dotnet/sdk:6.0 AS build
WORKDIR /source

# copy csproj and restore as distinct layers
COPY *.sln .
COPY aspnetapp/*.csproj ./aspnetapp/
RUN dotnet restore

# copy everything else and build app
COPY aspnetapp/. ./aspnetapp/
WORKDIR /source/aspnetapp
RUN dotnet publish -c release -o /app --no-restore

# final stage/image
FROM mcr.microsoft.com/dotnet/aspnet:6.0
WORKDIR /app
COPY --from=build /app ./
ENTRYPOINT ["dotnet", "aspnetapp.dll"]
```

Build, inspect, history, run, tag, push image:

```sh
docker build -t image:tag
docker inspect image:tag
docker history --no-trunc image:tag
docker run --rm -p 5000:5000 --name myapp image:tag
docker ps
docker images
docker exec -ti myapp -- /bin/sh
docker tag registry/image:tag
docker login
docker push push registry/image:tag
docker prune
```

or

```sh
az acr build \
    --resource-group $RESOURCE_GROUP \
    --registry $ACR_NAME \
    --image image:tag .
```

Kube 101
--------

In VSCode (hint: use Kubernetes plugin and type `kind: deployment` select the template to autofill)

* Create a deployment
  * Scale, kill replicas (check status)
* Create a service
  * Type LB
* Install [ingress controller](https://docs.microsoft.com/en-us/azure/aks/ingress-basic?tabs=azure-cli#basic-configuration)

```sh
NAMESPACE=ingress-basic

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

DNS_NAME="mydemoapp$RANDOM"

helm install ingress-nginx ingress-nginx/ingress-nginx --create-namespace --namespace $NAMESPACE \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-dns-label-name"=$DNS_NAME.$REGION_NAME.cloudapp.azure.com
```

* Update service to type ClusterIP
* Create an ingress
* Kube apply
* ConfigMap

  * Read ENV var in the app code:

```c#
// Index.cshtml.cs
public void OnGet()
{
    ViewData["Message"] = Environment.GetEnvironmentVariable("MESSAGE") ?? "Hello World!";
}

// Index.cshtml
<h1 class="display-4">@ViewData["Message"]</h1>
```
