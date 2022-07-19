Some KQL queries to try
=======================

List container images deployed in the cluster:

```kql
ContainerInventory
| distinct Repository, Image, ImageTag
| where Image contains "rating"
| render table
```

List container inventory and state:

```kql
ContainerInventory
| project Computer, Name, Image, ImageTag, ContainerState, CreatedTime, StartedTime, FinishedTime
| render table
```

List Kubernetes Events:

```kql
KubeEvents
| where not(isempty(Namespace))
| sort by TimeGenerated desc
| render table
```

List Azure Diagnostic categories:

```kql
AzureDiagnostics
| distinct Category
```

API Server logs:

```kql
AzureDiagnostics
| where Category == "kube-apiserver"
| project TimeGenerated, log_s
| order by TimeGenerated
```
