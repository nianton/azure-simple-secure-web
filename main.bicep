param naming object
param location string = resourceGroup().location
param tags object
param vnet object

@allowed([
  'S1'
  'S2'
  'S3'
  'P1v3'
  'P2v3'
  'P3v3'
])
param appServicePlanSkuName string = 'P1v3'

@secure()
param jumphostAdministratorPassword string

var resourceNames = {
  appServicePlan: naming.appServicePlan.name
  frontendWebApp: replace(naming.appService.name, '${naming.appService.slug}-', '${naming.appService.slug}-frontend-')
  backendWebApp: replace(naming.appService.name, '${naming.appService.slug}-', '${naming.appService.slug}-backend-')
  storageAccount: naming.storageAccount.nameUnique
  keyVault: naming.keyVault.nameUnique
  redis: naming.redisCache.name
  jumphostVirtualMachine: naming.windowsVirtualMachine.name
}

var secretNames = {
  dataStorageConnectionString: 'dataStorageConnectionString'
  redisConnectionString: 'redisConnectionString'
}

module storage 'modules/storage.module.bicep' = {
  name: 'storage-deployment'
  params: {
    location: location
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    name: resourceNames.storageAccount
    tags: tags
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2020-06-01' = {
  name: resourceNames.appServicePlan
  location: location
  tags: tags
  sku: {
    name: appServicePlanSkuName
    tier: substring(appServicePlanSkuName, 0, 1) == 'S' ? 'Standard' : 'PremiumV3'
  }
}

module frontendWebApp 'modules/webApp.module.bicep' = {
  name: 'frontendWebApp-deployment'
  params: {
    name: resourceNames.frontendWebApp
    location: location
    tags: tags
    appServicePlanId: appServicePlan.id
    subnetIdForIntegration: vnet.appServiceSnetId    
    managedIdentity: true
    appSettings: [
      {
        name: 'StorageConnection'
        value: storage.outputs.connectionString
      }
    ]
  }  
}

module backendWebApp 'modules/webApp.module.bicep' = {
  name: 'backendWebApp-deployment'
  params: {
    name: resourceNames.backendWebApp
    location: location
    tags: tags
    appServicePlanId: appServicePlan.id
    subnetIdForIntegration: vnet.appServiceSnetId
    managedIdentity: true
    appSettings: [
      {
        name: 'StorageConnection'
        value: storage.outputs.connectionString
      }
    ]
  }
}

module websitesPrivateDnsZone 'modules/privateDnsZone.module.bicep'={
  name: 'websitesPrivateDnsZone-deployment'
  params: {
    name: 'privatelink.azurewebsites.net'
    vnetIds: [
      vnet.vnetId
    ] 
  }
}

module frontendPrivateEndpoint 'modules/privateEndpoint.module.bicep' = {
  name: 'frontendPrivateEndpoint-deployment'
  params: {
    name: 'pe-${frontendWebApp.outputs.name}'
    location: location
    tags: tags    
    privateDnsZoneId: websitesPrivateDnsZone.outputs.id
    privateLinkServiceId: frontendWebApp.outputs.id
    subnetId: vnet.privateEndpointsSnetId
    subResource: 'sites'
  }  
}

module backendPrivateEndpoint 'modules/privateEndpoint.module.bicep' = {
  name: 'backendPrivateEndpoint-deployment'
  params: {
    name: 'pe-${backendWebApp.outputs.name}'
    location: location
    tags: tags
    privateDnsZoneId: websitesPrivateDnsZone.outputs.id
    privateLinkServiceId: backendWebApp.outputs.id
    subnetId: vnet.privateEndpointsSnetId
    subResource: 'sites'
  }  
}

module redis 'modules/redis.module.bicep' = {
  name: 'redis-deployments'
  params: {
    name: resourceNames.redis
    location: location
    tags: tags    
  }
}

module redisPrivateDnsZone 'modules/privateDnsZone.module.bicep'={
  name: 'redisPrivateDnsZone-deployment'
  params: {
    name: 'privatelink.redis.cache.windows.net'
    vnetIds: [
      vnet.vnetId
    ] 
  }
}

module redisPrivateEndpoint 'modules/privateEndpoint.module.bicep' = {
  name: 'redisPrivateEndpoint-deployment'
  params: {
    location: location
    name: 'pe-${resourceNames.redis}'
    tags: tags
    privateDnsZoneId: redisPrivateDnsZone.outputs.id
    privateLinkServiceId: redis.outputs.id
    subnetId: vnet.privateEndpointsSnetId
    subResource: 'redisCache'
  }  
}

module keyVault 'modules/keyvault.module.bicep' ={
  name: 'keyVault-deployment'
  params: {
    name: resourceNames.keyVault
    location: location
    skuName: 'premium'
    tags: tags
    accessPolicies: [
      {
        tenantId: frontendWebApp.outputs.identity.tenantId
        objectId: frontendWebApp.outputs.identity.principalId
        permissions: {
          secrets: [
            'get'
          ]
        }
      }
      {
        tenantId: backendWebApp.outputs.identity.tenantId
        objectId: backendWebApp.outputs.identity.principalId
        permissions: {
          secrets: [
            'get'
          ]
        }
      }
    ]
    secrets: [
      {
        name: secretNames.dataStorageConnectionString
        value: storage.outputs.connectionString
      }
      {
        name: secretNames.redisConnectionString
        value: redis.outputs.connectionString
      }
    ]
  }  
}


module keyvaultPrivateDnsZone 'modules/privateDnsZone.module.bicep'={
  name: 'keyvaultPrivateDnsZone-deployment'
  params: {
    name: 'privatelink.vaultcore.azure.net'
    vnetIds: [
      vnet.vnetId
    ] 
  }
}

module keyvaultPrivateEndpoint 'modules/privateEndpoint.module.bicep' = {
  name: 'keyvaultPrivateEndpoint-deployment'
  params: {
    location: location
    name: 'pe-${resourceNames.keyVault}'
    tags: tags
    privateDnsZoneId: keyvaultPrivateDnsZone.outputs.id
    privateLinkServiceId: keyVault.outputs.id
    subnetId: vnet.privateEndpointsSnetId
    subResource: 'vault'
  }  
}

module jumphost 'modules/vmjumpbox.module.bicep' = {
  name: 'jumphost-deployment'
  params: {
    name: resourceNames.jumphostVirtualMachine
    location: location
    tags: tags
    adminPassword: jumphostAdministratorPassword
    dnsLabelPrefix: resourceNames.jumphostVirtualMachine
    subnetId: vnet.devOpsSnetId
  }
}

output storageAccountName string = storage.outputs.name
output frontendWebApp object = frontendWebApp
output backendWebApp object = backendWebApp
output jumphost object = jumphost
