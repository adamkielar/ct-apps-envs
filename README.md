## External env
```bash
az group create --location eastus --resource-group ctapps-external-rg
az deployment group create -n app001 -g ctapps-external-rg -f ./bicep/external/main.bicep -p ./bicep/parameters/parameters.json
```

## Internal env
```bash
az group create --location eastus --resource-group ctapps-internal-rg
az deployment group create -n app001 -g ctapps-internal-rg -f ./bicep/internal/main.bicep -p ./bicep/parameters/parameters.json
```