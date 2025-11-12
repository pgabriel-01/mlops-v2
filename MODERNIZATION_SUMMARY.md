# MLOps v2 Modernization Summary

## Overview
This document summarizes the modernization changes made to the Azure MLOps v2 Solution Accelerator to bring it up to current (November 2025) best practices and standards.

## Branch Information
- **Branch Name**: `feature/modernize-auth-and-infrastructure`
- **Status**: In Progress
- **Repositories Updated**:
  - mlops-templates
  - mlops-project-template

## ✅ Completed Changes

### 1. Authentication Modernization (CRITICAL SECURITY UPDATE)

#### What Changed
- **Migrated from Service Principal Secrets to OpenID Connect (OIDC)**
- Removed all hard-coded credentials and client secrets
- Implemented workload identity federation for GitHub Actions

#### Benefits
- ✨ **No more secrets**: OIDC eliminates the need to store and rotate credentials
- 🔒 **Enhanced security**: Federated identity credentials are more secure than client secrets
- ⏱️ **Automatic token management**: GitHub generates short-lived tokens automatically
- 🎯 **Principle of least privilege**: Fine-grained access control per workflow

#### Files Modified
**mlops-templates/.github/workflows/**:
- `register-environment.yml`
- `register-dataset.yml`
- `create-compute.yml`
- `run-pipeline.yml`
- `create-endpoint.yml`
- `create-deployment.yml`
- `allocate-traffic.yml`
- `tf-gha-install-terraform.yml`
- `read-yaml.yml`

**mlops-project-template/classical/aml-cli-v2/mlops/github-actions/**:
- `deploy-model-training-pipeline-classical.yml`

#### Before (Insecure):
```yaml
secrets:
  creds:
    required: true
    
jobs:
  my-job:
    steps:
      - uses: azure/login@v1
        with:
          creds: ${{secrets.AZURE_CREDENTIALS}}
```

#### After (Secure):
```yaml
secrets:
  AZURE_CLIENT_ID:
    required: true
  AZURE_TENANT_ID:
    required: true
  AZURE_SUBSCRIPTION_ID:
    required: true
    
jobs:
  my-job:
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

### 2. GitHub Actions Version Updates

#### What Changed
- Updated `actions/checkout` from v3 to v4
- Updated `azure/login` from v1 to v2
- Added OIDC permissions (`id-token: write`, `contents: read`)

#### Benefits
- Latest security patches
- Performance improvements
- New features and better error messages

### 3. Compute SKU Modernization

#### What Changed
- Upgraded from `Standard_DS3_v2` (3rd generation) to `Standard_D4s_v5` (5th generation)
- Prepared infrastructure for GPU SKU updates

#### Benefits
- 🚀 **Better performance**: 5th gen VMs offer 15-20% better performance
- 💰 **Cost optimization**: Better price-to-performance ratio
- ⚡ **Modern features**: Support for latest Azure features
- 🔋 **Energy efficient**: Lower power consumption

#### Before:
```yaml
size: Standard_DS3_v2  # Old 3rd generation
```

#### After:
```yaml
size: Standard_D4s_v5  # New 5th generation
```

### 4. Terraform Modernization

#### What Changed
- Updated Terraform required version from `>= 1.6.0` to `>= 1.9.0`
- Updated azurerm provider from `2.99.0` (2021) to `~> 4.11` (November 2025 - latest)
- Added OIDC authentication support (`use_oidc = true`)
- Removed `client_secret` variable (no longer needed with OIDC)
- Modernized Key Vault to use RBAC instead of deprecated access policies
- Upgraded Container Registry from Standard to Premium SKU
- Added managed identity support for ACR
- Updated Storage Account with TLS 1.2 minimum and retention policies
- Upgraded compute clusters from Standard_DS3_v2 to Standard_D4s_v5

#### Benefits
- Access to 3+ years of provider improvements
- OIDC authentication support
- Better error messages and validation
- Support for latest Azure resources and features
- RBAC-based Key Vault access (modern, more secure)
- Premium ACR for production workloads
- Enhanced storage security and compliance

#### Before:
```terraform
terraform {
  required_providers {
    azurerm = {
      version = "= 2.99.0"
    }
  }
}

provider "azurerm" {
  features {}
}
```

#### After:
```terraform
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.11"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  use_oidc = true
}
```

#### Key Vault RBAC Migration:
```terraform
# OLD: Access policies (deprecated)
access_policy {
  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = data.azurerm_client_config.current.object_id
  secret_permissions = ["Set", "Get", "Delete"]
}

# NEW: RBAC authorization
resource "azurerm_key_vault" "kv" {
  purge_protection_enabled   = true
  soft_delete_retention_days = 90
}

resource "azurerm_role_assignment" "kv_secrets_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
```

### 5. Python Dependencies Update

#### What Changed
- Upgraded Python from 3.8 to 3.11 in conda environment
- Updated all Azure SDK packages to November 2025 versions
- Updated ML/data science packages to latest stable versions
- Updated development tools (black, flake8, pytest)

#### Benefits
- 🐍 **Python 3.11**: 10-60% faster than 3.8, better error messages
- 🔒 **Security patches**: Latest versions include all security updates
- 🆕 **New features**: Access to latest Azure ML capabilities
- 🔧 **Better compatibility**: Works with latest Azure services

#### Version Updates:

| Package | Old Version | New Version | Notes |
|---------|-------------|-------------|-------|
| Python | 3.8 | 3.11 | Major performance improvement |
| azure-ai-ml | 1.1.0 | 1.21.1 | 20 versions ahead, latest SDK v2 |
| azure-identity | 1.10.0 | 1.19.0 | Enhanced OIDC support |
| azure-core | 1.26.1 | 1.32.0 | Core functionality updates |
| azure-storage-blob | 12.14.1 | 12.23.1 | Latest storage features |
| azureml-mlflow | 1.38.0/1.41.0 | 1.57.0 | Latest MLflow integration |
| mlflow | 2.3.1 | 2.18.0 | Major update with new features |
| scikit-learn | 0.24.x | 1.5.2 | Latest ML algorithms |
| pandas | 1.2.1 | 2.2.3 | Better performance |
| flask | 1.1.2 | 3.1.0 | Major version update |
| pytest | 7.1.2 | 8.3.3 | Latest testing features |
| black | 22.3.0 | 24.10.0 | Latest formatter |

### 6. Private Endpoints Implementation

#### What Changed
- Added private endpoint support to all Terraform modules
- Implemented for Storage Account (blob & file), Key Vault, Container Registry, ML Workspace
- Added `enable_private_endpoints` variable (defaults to false for backward compatibility)
- Configured network rules to deny public access when private endpoints enabled

#### Benefits
- 🔒 **Network isolation**: Services only accessible within VNet
- 🛡️ **Enhanced security**: No public internet exposure
- 📊 **Compliance**: Meets enterprise security requirements
- 🚫 **Attack surface reduction**: Eliminates public endpoints

#### Implementation:
```terraform
# Storage Account with private endpoints
resource "azurerm_private_endpoint" "st_blob_pe" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-${azurerm_storage_account.st.name}-blob"
  subnet_id           = var.private_endpoint_subnet_id
  
  private_service_connection {
    name                           = "psc-blob"
    private_connection_resource_id = azurerm_storage_account.st.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
}
```

#### Resources with Private Endpoint Support:
- ✅ Storage Account (blob subresource)
- ✅ Storage Account (file subresource)
- ✅ Key Vault (vault subresource)
- ✅ Container Registry (registry subresource)
- ✅ ML Workspace (amlworkspace subresource)

## 🚧 Work In Progress

### 7. Azure Verified Modules (AVM) Migration
**Status**: Planned
- Replace custom Terraform modules with AVM modules
- Update for ML Workspace, Storage, Key Vault, ACR, Application Insights

### 8. Managed Identity for Compute
**Status**: Planned
- Add user-assigned managed identities
- Replace service principal authentication in compute clusters

### 9. Documentation Updates
**Status**: Planned
- Update deployment guides with OIDC setup instructions
- Remove service principal secret creation steps
- Add federated credential configuration guide

## 📝 Migration Guide for Users

### Setting Up OIDC Authentication

1. **Create Microsoft Entra Application or User-Assigned Managed Identity**

**Option 1: Microsoft Entra Application (Recommended)**
```bash
# Create app registration
az ad app create --display-name "mlops-v2-github-actions"

# Get the application (client) ID
APP_ID=$(az ad app list --display-name "mlops-v2-github-actions" --query "[0].appId" -o tsv)

# Create service principal
az ad sp create --id $APP_ID

# Get the service principal object ID
SP_ID=$(az ad sp list --filter "appId eq '$APP_ID'" --query "[0].id" -o tsv)
```

**Option 2: User-Assigned Managed Identity**
```bash
# Create managed identity
az identity create --name "mlops-v2-identity" --resource-group "mlops-rg" --location "eastus"

# Get the client ID
CLIENT_ID=$(az identity show --name "mlops-v2-identity" --resource-group "mlops-rg" --query clientId -o tsv)
```

2. **Assign Azure Permissions**

```bash
# Get your subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Assign Contributor role (adjust scope as needed)
az role assignment create \
  --assignee $APP_ID \
  --role Contributor \
  --scope "/subscriptions/$SUBSCRIPTION_ID"
```

3. **Configure Federated Identity Credential**

```bash
# For GitHub Actions
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-actions-mlops",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

4. **Add GitHub Secrets**

In your GitHub repository, add these secrets:
- `AZURE_CLIENT_ID`: Application (client) ID
- `AZURE_TENANT_ID`: Directory (tenant) ID  
- `AZURE_SUBSCRIPTION_ID`: Subscription ID

**IMPORTANT**: Do NOT add `AZURE_CREDENTIALS` (old pattern)

5. **Remove Old Secrets**

Delete these secrets from your repository:
- `AZURE_CREDENTIALS` ❌
- Any service principal client secrets ❌

## 🎯 Benefits Summary

### Security Improvements
- ✅ Eliminated hard-coded secrets
- ✅ Short-lived, auto-rotating tokens
- ✅ Better audit trail
- ✅ Reduced attack surface

### Performance & Cost
- ✅ 15-20% better compute performance
- ✅ Better price-to-performance ratio
- ✅ Access to latest VM features

### Maintainability
- ✅ Up-to-date dependencies
- ✅ Latest security patches
- ✅ Better error messages
- ✅ Easier troubleshooting

### Compliance
- ✅ Aligned with Microsoft security best practices
- ✅ No secrets in code or configuration
- ✅ Enhanced auditing capabilities

## 📊 Version Matrix

| Component | Old Version | New Version | Status |
|-----------|-------------|-------------|--------|
| **GitHub Actions** | | | |
| actions/checkout | v3 | v4 | ✅ Complete |
| azure/login | v1 | v2 | ✅ Complete |
| Authentication | Service Principal | OIDC | ✅ Complete |
| **Infrastructure** | | | |
| Terraform | >= 1.6.0 | >= 1.9.0 | ✅ Complete |
| azurerm Provider | 2.99.0 (2021) | ~> 4.11 (2025) | ✅ Complete |
| Compute SKU | Standard_DS3_v2 | Standard_D4s_v5 | ✅ Complete |
| Key Vault Auth | Access Policies | RBAC | ✅ Complete |
| ACR SKU | Standard | Premium | ✅ Complete |
| Storage TLS | TLS 1.0 | TLS 1.2 | ✅ Complete |
| Network Isolation | Public Only | Private Endpoints | ✅ Complete |
| **Python/SDK** | | | |
| Python | 3.8 | 3.11 | ✅ Complete |
| azure-ai-ml | 1.1.0 | 1.21.1 | ✅ Complete |
| azure-identity | 1.10.0 | 1.19.0 | ✅ Complete |
| MLflow | 2.3.1 | 2.18.0 | ✅ Complete |
| scikit-learn | 0.24.x | 1.5.2 | ✅ Complete |
| **Future Work** | | | |
| Infrastructure | Custom Modules | AVM | 🚧 Planned |
| Compute Identity | System Assigned | User Assigned | 🚧 Planned |

## 🔄 Breaking Changes

### ⚠️ CRITICAL: Authentication Changes

**Old Setup (Deprecated)**:
```bash
# OLD - DO NOT USE
az ad sp create-for-rbac --name "my-sp" --role contributor --scopes /subscriptions/xxx --sdk-auth
```

**New Setup (Required)**:
```bash
# NEW - Use OIDC
az ad app federated-credential create ...
```

### Workflow Changes Required

All workflows that previously used:
```yaml
secrets:
  creds: ${{secrets.AZURE_CREDENTIALS}}
```

Must now use:
```yaml
secrets:
  AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
  AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
  AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

## 🔗 References

- [GitHub Actions OIDC with Azure](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect)
- [Azure Machine Learning Authentication](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-setup-authentication)
- [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/)
- [Terraform Azure Provider v4](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## 📞 Next Steps

1. Review and test the authentication changes
2. Complete AVM migration for infrastructure
3. Implement private endpoints
4. Update all documentation
5. Create migration guide for existing users
6. Test complete end-to-end deployment

## 🤝 Contributing

When making additional changes:
1. Follow the established patterns
2. Update this document
3. Test thoroughly before committing
4. Use conventional commits format

## 📅 Timeline

- **Phase 1 (Completed)**: Authentication & Actions Updates
- **Phase 2 (In Progress)**: Infrastructure Modernization
- **Phase 3 (Planned)**: Security Enhancements
- **Phase 4 (Planned)**: Documentation & Testing

---

**Last Updated**: November 12, 2025  
**Maintained By**: Azure MLOps Team
