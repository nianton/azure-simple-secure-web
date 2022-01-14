param name string
param location string = resourceGroup().location
param tags object = {}

@allowed([
  'C'
  'P'
])
param skuFamily string = 'C'

@allowed([
  0
  1
  2
  3
  4
  5
  6
])
param skuCapacity int = 1

@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param skuName string = 'Standard'

resource redis 'Microsoft.Cache/redis@2020-12-01' = {
  name: name
  location: location
  properties: {
    sku: {
      capacity: skuCapacity
      family: skuFamily
      name: skuName
    }
    publicNetworkAccess: 'Disabled'
  }
  tags: tags
}

output id string = redis.id
output accessKeys object = listKeys(redis.id, redis.apiVersion)
output connectionString string = '${name}.redis.cache.windows.net,abortConnect=false,ssl=true,password=${listKeys(redis.id, redis.apiVersion).primaryKey}'
