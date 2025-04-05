// Parameters
@description('Azure Subscription ID')
param subscriptionId string

@description('Primary location for resources (Brazil South)')
param locationBrazil string = 'brazilsouth'

@description('Secondary location for resources (US)')
param locationUS string = 'eastus'

@description('Client name in uppercase for naming convention')
param clientNameUpper string

@description('Client name in lowercase for tags')
param clientNameLower string

@description('Environment name (dev, test, prod)')
param environment string = 'prod'

@description('Primary VM name')
param vmName string

@description('Second VM name (if creating second VM)')
param secondVMName string = ''

@description('Whether to create a second VM')
param criarSegundaVM bool = false

@description('Whether to install VPN')
param instalarVPN bool = false

@description('VM admin username')
param vmUsername string

@description('VM admin password')
@secure()
param vmPassword string

@description('VNet IP address range')
param vNetIPRange string

@description('Internal subnet IP range')
param subnetInternalIPRange string

@description('Gateway subnet IP range')
param gatewaySubnetIPRange string

// Variables
var resourceGroupVM = 'RG-${clientNameUpper}-VM'
var resourceGroupStorage = 'RG-${clientNameUpper}-Storage'
var resourceGroupNetworks = 'RG-${clientNameUpper}-Networks'
var resourceGroupBackup = 'RG-${clientNameUpper}-Backup'
var resourceGroupAutomation = 'RG-${clientNameUpper}-Automation'
var resourceGroupLogAnalytics = 'RG-${clientNameUpper}-LogAnalytics'

var vnetName = 'VNET-${clientNameUpper}-Hub-001'
var subnetInternalName = 'SNET-${clientNameUpper}-Internal-001'
var nsgName = 'NSG-${clientNameUpper}-Internal-001'
var availabilitySetName = 'AS-${vmName}'
var storageAccountName = 'st${clientNameLower}001'
var automationAccountName = 'AA-${clientNameUpper}-Automation'
var runbookName = 'START_STOP_VMs'
var logAnalyticsWorkspaceName = 'LAW-${clientNameUpper}-EASTUS-001'
var backupVaultName = 'RSV-${clientNameUpper}-Backup-BrazilSouth'

var clientTags = {
  client: clientNameLower
  environment: environment
}

// Create Resource Groups
resource rgVM 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupVM
  location: locationBrazil
  tags: union(clientTags, { technology: 'vm' })
}

resource rgStorage 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupStorage
  location: locationBrazil
  tags: union(clientTags, { technology: 'storage' })
}

resource rgNetworks 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupNetworks
  location: locationBrazil
  tags: union(clientTags, { technology: 'network' })
}

resource rgBackup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupBackup
  location: locationBrazil
  tags: union(clientTags, { technology: 'backup' })
}

resource rgAutomation 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupAutomation
  location: locationUS
  tags: union(clientTags, { technology: 'automationaccounts' })
}

resource rgLogAnalytics 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupLogAnalytics
  location: locationUS
  tags: union(clientTags, { technology: 'loganalyticsworkspace' })
}

// Create Network Security Group (NSG)
module nsg 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: 'deployNSG'
  scope: resourceGroup(rgNetworks.name)
  params: {
    name: nsgName
    location: locationBrazil
    tags: union(clientTags, { technology: 'firewall' })
    securityRules: [
      {
        name: 'Allow-RDP'
        properties: {
          description: 'Allow RDP'
          access: 'Allow'
          protocol: 'Tcp'
          direction: 'Inbound'
          priority: 1000
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
    ]
  }
}

// Create Virtual Network and Subnets
module vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: 'deployVNet'
  scope: resourceGroup(rgNetworks.name)
  params: {
    name: vnetName
    location: locationBrazil
    tags: union(clientTags, { technology: 'network' })
    addressPrefix: vNetIPRange
    subnets: [
      {
        name: subnetInternalName
        properties: {
          addressPrefix: subnetInternalIPRange
          networkSecurityGroup: {
            id: nsg.outputs.id
          }
        }
      }
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: gatewaySubnetIPRange
        }
      }
    ]
  }
}

// Create Public IP for VMs
module pipVM 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: 'deployPublicIPVM'
  scope: resourceGroup(rgNetworks.name)
  params: {
    name: 'PIP-VM-${vmName}'
    location: locationBrazil
    tags: union(clientTags, { technology: 'networking' })
    sku: {
      name: 'Standard'
    }
    properties: {
      publicIPAllocationMethod: 'Static'
    }
  }
}

// Create second VM Public IP if required
module pipSecondVM 'Microsoft.Network/publicIPAddresses@2021-05-01' = if (criarSegundaVM) {
  name: 'deployPublicIPSecondVM'
  scope: resourceGroup(rgNetworks.name)
  params: {
    name: 'PIP-VM-${secondVMName}'
    location: locationBrazil
    tags: union(clientTags, { technology: 'networking' })
    sku: {
      name: 'Standard'
    }
    properties: {
      publicIPAllocationMethod: 'Static'
    }
  }
}

// Create Availability Set
module availabilitySet 'Microsoft.Compute/availabilitySets@2021-11-01' = {
  name: 'deployAvailabilitySet'
  scope: resourceGroup(rgVM.name)
  params: {
    name: availabilitySetName
    location: locationBrazil
    tags: clientTags
    sku: {
      name: 'Aligned'
    }
    properties: {
      platformFaultDomainCount: 2
      platformUpdateDomainCount: 5
    }
  }
}

// Create second Availability Set if required
module secondAvailabilitySet 'Microsoft.Compute/availabilitySets@2021-11-01' = if (criarSegundaVM) {
  name: 'deploySecondAvailabilitySet'
  scope: resourceGroup(rgVM.name)
  params: {
    name: 'AS-${secondVMName}'
    location: locationBrazil
    tags: clientTags
    sku: {
      name: 'Aligned'
    }
    properties: {
      platformFaultDomainCount: 2
      platformUpdateDomainCount: 5
    }
  }
}

// Create Primary VM Network Interface
module nicVM 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: 'deployNICVM'
  scope: resourceGroup(rgVM.name)
  params: {
    name: '${vmName}-NIC'
    location: locationBrazil
    tags: union(clientTags, { technology: 'network' })
    properties: {
      ipConfigurations: [
        {
          name: 'ipconfig1'
          properties: {
            subnet: {
              id: '${vnet.outputs.id}/subnets/${subnetInternalName}'
            }
            privateIPAllocationMethod: 'Dynamic'
            publicIPAddress: {
              id: pipVM.outputs.id
            }
          }
        }
      ]
      networkSecurityGroup: {
        id: nsg.outputs.id
      }
    }
  }
}

// Create Second VM Network Interface if required
module nicSecondVM 'Microsoft.Network/networkInterfaces@2021-05-01' = if (criarSegundaVM) {
  name: 'deployNICSecondVM'
  scope: resourceGroup(rgVM.name)
  params: {
    name: '${secondVMName}-NIC'
    location: locationBrazil
    tags: union(clientTags, { technology: 'network' })
    properties: {
      ipConfigurations: [
        {
          name: 'ipconfig1'
          properties: {
            subnet: {
              id: '${vnet.outputs.id}/subnets/${subnetInternalName}'
            }
            privateIPAllocationMethod: 'Dynamic'
            publicIPAddress: {
              id: criarSegundaVM ? pipSecondVM.outputs.id : ''
            }
          }
        }
      ]
      networkSecurityGroup: {
        id: nsg.outputs.id
      }
    }
  }
}

// Create VM
module primaryVM 'Microsoft.Compute/virtualMachines@2021-11-01' = {
  name: 'deployPrimaryVM'
  scope: resourceGroup(rgVM.name)
  params: {
    name: vmName
    location: locationBrazil
    tags: union(clientTags, { technology: 'vm' })
    properties: {
      availabilitySet: {
        id: availabilitySet.outputs.id
      }
      hardwareProfile: {
        vmSize: 'Standard_B2ms'
      }
      storageProfile: {
        imageReference: {
          publisher: 'MicrosoftWindowsServer'
          offer: 'WindowsServer'
          sku: '2025-datacenter-azure-edition'
          version: 'latest'
        }
        osDisk: {
          name: '${vmName}-OSDisk'
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'StandardSSD_LRS'
          }
          diskSizeGB: 127
          caching: 'ReadWrite'
        }
      }
      osProfile: {
        computerName: vmName
        adminUsername: vmUsername
        adminPassword: vmPassword
        windowsConfiguration: {
          enableAutomaticUpdates: true
          provisionVMAgent: true
          patchSettings: {
            patchMode: 'AutomaticByPlatform'
            enableHotpatching: true
          }
          timeZone: 'E. South America Standard Time'
        }
      }
      networkProfile: {
        networkInterfaces: [
          {
            id: nicVM.outputs.id
          }
        ]
      }
      securityProfile: {
        securityType: 'TrustedLaunch'
        uefiSettings: {
          secureBootEnabled: true
          vTpmEnabled: true
        }
      }
      diagnosticsProfile: {
        bootDiagnostics: {
          enabled: false
        }
      }
    }
  }
}

// Create Second VM if required
module secondVM 'Microsoft.Compute/virtualMachines@2021-11-01' = if (criarSegundaVM) {
  name: 'deploySecondVM'
  scope: resourceGroup(rgVM.name)
  params: {
    name: secondVMName
    location: locationBrazil
    tags: union(clientTags, { technology: 'vm' })
    properties: {
      availabilitySet: {
        id: criarSegundaVM ? secondAvailabilitySet.outputs.id : ''
      }
      hardwareProfile: {
        vmSize: 'Standard_B2ms'
      }
      storageProfile: {
        imageReference: {
          publisher: 'MicrosoftWindowsServer'
          offer: 'WindowsServer'
          sku: '2025-datacenter-azure-edition'
          version: 'latest'
        }
        osDisk: {
          name: '${secondVMName}-OSDisk'
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'StandardSSD_LRS'
          }
          diskSizeGB: 127
          caching: 'ReadWrite'
        }
      }
      osProfile: {
        computerName: secondVMName
        adminUsername: vmUsername
        adminPassword: vmPassword
        windowsConfiguration: {
          enableAutomaticUpdates: true
          provisionVMAgent: true
          patchSettings: {
            patchMode: 'AutomaticByPlatform'
            enableHotpatching: true
          }
          timeZone: 'E. South America Standard Time'
        }
      }
      networkProfile: {
        networkInterfaces: [
          {
            id: criarSegundaVM ? nicSecondVM.outputs.id : ''
          }
        ]
      }
      securityProfile: {
        securityType: 'TrustedLaunch'
        uefiSettings: {
          secureBootEnabled: true
          vTpmEnabled: true
        }
      }
      diagnosticsProfile: {
        bootDiagnostics: {
          enabled: false
        }
      }
    }
  }
}

// Create Storage Account
module storageAccount 'Microsoft.Storage/storageAccounts@2021-08-01' = {
  name: 'deployStorageAccount'
  scope: resourceGroup(rgStorage.name)
  params: {
    name: storageAccountName
    location: locationBrazil
    tags: union(clientTags, { technology: 'storage' })
    sku: {
      name: 'Standard_LRS'
    }
    kind: 'StorageV2'
    properties: {
      accessTier: 'Hot'
    }
  }
}

// Create Recovery Services Vault (Backup)
module backupVault 'Microsoft.RecoveryServices/vaults@2022-01-01' = {
  name: 'deployBackupVault'
  scope: resourceGroup(rgBackup.name)
  params: {
    name: backupVaultName
    location: locationBrazil
    tags: union(clientTags, { technology: 'backup' })
    sku: {
      name: 'RS0'
      tier: 'Standard'
    }
    properties: {}
  }
}

// Create Automation Account
module automationAccount 'Microsoft.Automation/automationAccounts@2021-06-22' = {
  name: 'deployAutomationAccount'
  scope: resourceGroup(rgAutomation.name)
  params: {
    name: automationAccountName
    location: locationUS
    tags: union(clientTags, { technology: 'automation' })
    sku: {
      name: 'Basic'
    }
  }
}

// Create Runbook
module runbook 'Microsoft.Automation/automationAccounts/runbooks@2021-06-22' = {
  name: runbookName
  parent: automationAccount
  params: {
    location: locationUS
    properties: {
      runbookType: 'PowerShell'
      logVerbose: true
      logProgress: true
      description: 'Runbook to start and stop VMs'
      publishContentLink: {
        uri: ''  // Will be populated during publishing through Azure Portal
      }
    }
  }
}

// Create Log Analytics Workspace
module logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: 'deployLogAnalyticsWorkspace'
  scope: resourceGroup(rgLogAnalytics.name)
  params: {
    name: logAnalyticsWorkspaceName
    location: locationUS
    tags: union(clientTags, { technology: 'loganalyticsworkspace' })
    sku: {
      name: 'PerGB2018'
    }
    properties: {
      retentionInDays: 30
      features: {
        enableLogAccessUsingOnlyResourcePermissions: true
      }
      workspaceCapping: {
        dailyQuotaGb: -1
      }
    }
  }
}

// Create VPN Gateway if required
module vpnPublicIP 'Microsoft.Network/publicIPAddresses@2021-05-01' = if (instalarVPN) {
  name: 'deployVPNPublicIP'
  scope: resourceGroup(rgNetworks.name)
  params: {
    name: '${clientNameUpper}-PIP-S2S-PRIMARY'
    location: locationBrazil
    tags: union(clientTags, { technology: 'vpn' })
    sku: {
      name: 'Standard'
    }
    properties: {
      publicIPAllocationMethod: 'Static'
    }
  }
}

module vpnGateway 'Microsoft.Network/virtualNetworkGateways@2021-05-01' = if (instalarVPN) {
  name: 'deployVPNGateway'
  scope: resourceGroup(rgNetworks.name)
  params: {
    name: 'VNG-${clientNameUpper}'
    location: locationBrazil
    tags: union(clientTags, { technology: 'vpn' })
    properties: {
      enableBgp: false
      activeActive: false
      ipConfigurations: [
        {
          name: 'gwipconfig1'
          properties: {
            subnet: {
              id: '${vnet.outputs.id}/subnets/GatewaySubnet'
            }
            publicIPAddress: {
              id: instalarVPN ? vpnPublicIP.outputs.id : ''
            }
          }
        }
      ]
      sku: {
        name: 'VpnGw1'
        tier: 'VpnGw1'
      }
      gatewayType: 'Vpn'
      vpnType: 'RouteBased'
    }
  }
}

// Output important resource information
output vnetId string = vnet.outputs.id
output primaryVMId string = primaryVM.outputs.id
output primaryVMName string = vmName
output primaryVMPublicIP string = pipVM.outputs.ipAddress
output resourceGroupVMName string = rgVM.name
output resourceGroupNetworksName string = rgNetworks.name
