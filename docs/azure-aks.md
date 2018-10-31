# Creating a Kubernetes Cluster: Azure AKS

## Prerequisites

* An Azure account
* Azure CLI installed
* helm (optional)

## Login

Before running the script, you have to login using `az login`

## Script

```
$ ./azure-aks.sh up -e
```

## Troubleshooting

### ServicePrincipalNotFound

Delete the following file:

```
$ rm -rf ~/.azure/aksServicePrincipal.json
```