param privateLinkServiceName string
param location string
param subnetId string
param containerAppsDefaultDomainName string

var containerAppsDefaultDomainArray = split(containerAppsDefaultDomainName, '.')
var containerAppsNameIdentifier = containerAppsDefaultDomainArray[lastIndexOf(containerAppsDefaultDomainArray, location)-1]
var containerAppsManagedResourceGroup = 'MC_${containerAppsNameIdentifier}-rg_${containerAppsNameIdentifier}_${location}'

resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' existing = {
  name: split(subnetId, '/')[8]

  resource subnet 'subnets' existing = {
    name: last(split(subnetId, '/'))
  }
}

resource loadBalancer 'Microsoft.Network/loadBalancers@2021-05-01' existing = {
  name: 'kubernetes-internal'
  scope: resourceGroup(containerAppsManagedResourceGroup)
}

resource privateLinkService 'Microsoft.Network/privateLinkServices@2022-07-01' = {
  name: privateLinkServiceName
  location: location
  properties: {
    loadBalancerFrontendIpConfigurations: [
      {
        id: loadBalancer.properties.frontendIPConfigurations[0].id
      }
    ]
    ipConfigurations: [
      {
        name: 'snet-001-infrastructure-snet'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnet::subnet.id
          }
          primary: true
          privateIPAddressVersion: 'IPv4'
        }
      }
    ]
  }
}

output privateLinkServiceName string = privateLinkService.name
output privateLinkServiceId string = privateLinkService.id
