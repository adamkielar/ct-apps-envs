param projectName string
param location string

var _resourceName = '${projectName}-internal'
var _deployment = deployment().name

// ============== //
// Route Table
// ============== //
resource routeTable 'Microsoft.Network/routeTables@2022-07-01' = {
  name: '${_resourceName}-default-rt'
  location: location
  properties: {
    disableBgpRoutePropagation: false
  }

  resource udrInternetRoute 'routes' = {
    name: 'azure-cloud-eastus'
    properties: {
      addressPrefix: 'AzureCloud.eastus'
      nextHopType: 'Internet'
    }
  }
}

// ============== //
//     NSG
// ============== //
var _securityRules = [
  {
    name: 'AllowAll80InFromVnet'
    properties: {
      protocol: 'Tcp'
      sourcePortRange: '*'
      sourceAddressPrefix: '*'
      destinationPortRange: '80'
      destinationAddressPrefix: '*'
      access: 'Allow'
      priority: 100
      direction: 'Inbound'
    }
  }
  {
    name: 'AllowAll443InFromVnet'
    properties: {
      protocol: 'Tcp'
      sourcePortRange: '*'
      sourceAddressPrefix: '*'
      destinationPortRange: '443'
      destinationAddressPrefix: '*'
      access: 'Allow'
      priority: 200
      direction: 'Inbound'
    }
  }
]

resource nsg 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: '${_resourceName}-nsg'
  location: location
  properties: {
    securityRules: _securityRules
  }
}

// ============== //
// Virtual Network
// ============== //

var vnetSubnets = {
  'snet-001-infrastructure-snet': vnet.properties.subnets[0].id
}

resource vnet 'Microsoft.Network/virtualNetworks@2021-08-01' = {
  name: '${_resourceName}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '12.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'snet-001-infrastructure-snet'
        properties: {
          addressPrefix: '12.0.0.0/23'
          networkSecurityGroup: {
            id: nsg.id
          }
          routeTable: {
            id: routeTable.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// ============== //
// Log Analytics    //
// ============== //
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${_resourceName}-la'
  location: location
}

// ============== //
// Application Insights   //
// ============== //
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${_resourceName}-ai'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    DisableIpMasking: true
    Flow_Type: any('Redfield')
    Request_Source: any('Custom')
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// ============== //
// Container App Environment
// ============== //

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2022-10-01' = {
  name: '${_resourceName}-env'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    daprAIConnectionString: applicationInsights.properties.ConnectionString
    daprAIInstrumentationKey: applicationInsights.properties.InstrumentationKey
    vnetConfiguration: {
      dockerBridgeCidr: '100.64.0.1/16'
      infrastructureSubnetId: vnetSubnets['snet-001-infrastructure-snet']
      internal: true
      platformReservedCidr: '198.18.0.0/16'
      platformReservedDnsIP: '198.18.0.10'
    }
    zoneRedundant: false
  }
}

// ============== //
// Private Link Service
// ============== //

module privateEndpointFrontDoor 'privatelink.bicep' = {
  name: '${_deployment}-pe'
  params: {
    privateLinkServiceName: '${_resourceName}-pl'
    location: location
    subnetId: vnetSubnets['snet-001-infrastructure-snet']
    containerAppsDefaultDomainName: containerAppsEnvironment.properties.defaultDomain
  }
}

// ============== //
// User Managed Identity
// ============== //
resource appIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: '${_resourceName}-id'
  location: location
}

resource containerApp 'Microsoft.App/containerApps@2022-10-01' = {
  name: '${_resourceName}-app'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appIdentity.id}': {}
    }
  }
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      ingress: {
        allowInsecure: false
        external: true
        targetPort: 80
      }
    }
    template: {
      containers: [
        {
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          name: '${_resourceName}-app'
          resources: {
            cpu: 1
            memory: '2.0Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}
