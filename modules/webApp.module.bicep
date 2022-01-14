param name string
param location string = resourceGroup().location
param tags object = {}
param appSettings array = []
param appServicePlanId string

@description('Whether to create a managed identity for the web app -defaults to \'false\'')
param managedIdentity bool = false

@description('The subnet Id to integrate the web app with -optional')
param subnetIdForIntegration string = ''

@description('The Git repository url to deploy the application from -optional')
param appDeployRepoUrl string = ''

@description('The Git repository branch to deploy the application from -optional')
param appDeployBranch string = ''

var webAppInsName = 'appins-${name}'
var createSourceControl = !empty(appDeployRepoUrl)
var createNetworkConfig = !empty(subnetIdForIntegration)

var networkConfigAppSettings = createNetworkConfig ? [
  {
    name: 'WEBSITE_VNET_ROUTE_ALL'
    value: '1'
  }
  { 
    name: 'WEBSITE_DNS_SERVER'
    value: '168.63.129.16'
  }
] : []

module webAppIns './appInsights.module.bicep' = {
  name: webAppInsName
  params: {
    name: webAppInsName
    location: location
    tags: tags
    project: name
  }
}

resource webApp 'Microsoft.Web/sites@2020-06-01' = {
  name: name
  location: location  
  identity: {
    type: managedIdentity ? 'SystemAssigned' : 'None'
  }
  properties: {
    serverFarmId: appServicePlanId
    siteConfig: {
      appSettings: concat([
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~10'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: webAppIns.outputs.instrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: 'InstrumentationKey=${webAppIns.outputs.instrumentationKey}'
        }
      ], networkConfigAppSettings, appSettings)
    }
    httpsOnly: true
  }
  tags: union({
    'hidden-related:${appServicePlanId}': 'Resource'
  }, tags)
}

resource networkConfig 'Microsoft.Web/sites/networkConfig@2020-06-01' = if (createNetworkConfig) {
  name: '${webApp.name}/VirtualNetwork'
  properties: {
    subnetResourceId: subnetIdForIntegration
  }
}

resource appSourceControl 'Microsoft.Web/sites/sourcecontrols@2020-06-01' = if (createSourceControl) {
  name: '${webApp.name}/web'
  properties: {
    branch: appDeployBranch
    repoUrl: appDeployRepoUrl
    isManualIntegration: true
  }
}

output id string = webApp.id
output name string = webApp.name
output appServicePlanId string = appServicePlanId
output identity object = managedIdentity ? {
  tenantId: webApp.identity.tenantId
  principalId: webApp.identity.principalId
  type: webApp.identity.type
} : {}
output applicationInsights object = webAppIns
output siteHostName string = webApp.properties.defaultHostName
