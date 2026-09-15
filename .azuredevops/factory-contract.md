# Azure DevOps factory contract

The Azure DevOps factory selects assets from `mlops-project-template` and
registers their pipeline entrypoints. Reusable execution templates remain in
`mlops-templates`; this repository does not duplicate either implementation.

## Network modes

`networkMode: public` preserves the original generated-project behavior.

`networkMode: private` is supported with `infrastructure_version: terraform`.
The selected `mlops-project-template` repository must provide:

- `infrastructure/terraform/devops-pipelines/platform-ado-bootstrap.yml`;
- Terraform under `infrastructure/terraform/`;
- the selected workload under `<projectType>/<mlopsVersion>/`;
- `config-infra-{common,dev,test,prod}.yml` files used by the pipelines.

Private mode preserves those direct project-template paths. The platform
pipeline owns the VNet, delegated Managed DevOps Pool subnet, private DNS zones
and links, private endpoints, pool resource, and project-specific orchestration.
It should consume reusable templates from `mlops-templates`.

The factory generates `config-factory-<environment>.yml` with:

- `network_mode`;
- `deployment_environment`;
- `variable_group_name`;
- `mlops_templates_ref`;
- `platform_service_connection_name`;
- `workload_service_connection_name`;
- `managed_devops_pool_name`;
- `managed_devops_pool_alias`;
- `managed_devops_pool_resource_group`;
- `managed_devops_pool_location`;
- `managed_devops_pool_vm_sku`;
- `managed_devops_pool_image`;
- `managed_devops_pool_maximum_concurrency`;
- `platform_virtual_network_name`;
- `platform_vnet_address_prefix`;
- `managed_devops_pool_subnet_address_prefix`;
- `private_endpoint_subnet_address_prefix`;
- `terraform_state_storage_account_name`;
- `terraform_state_container_name`;
- `dev_center_project_resource_id`;
- protected references for `azure_subscription_id`,
  `cicd_principal_object_id`, and
  `devops_infrastructure_principal_object_id`.

The generated file is a non-secret factory manifest. Project-template
environment files reference protected variable groups named `mlops-dev`,
`mlops-test`, or `mlops-prod`; those groups hold
`ado_service_connection_rg`, `ado_service_connection_aml_ws`, and
`cicd_principal_object_id`. They also hold
`devops_infrastructure_principal_object_id`, which the platform template uses
for Managed DevOps Pool network permissions, and `azure_subscription_id`.
Do not store live IDs in generated files.

Every workload pipeline should expose `environment`, `agentPoolName`, and
`mlopsTemplatesRef` runtime parameters. The platform bootstrap pipeline must
use a Microsoft-hosted or otherwise pre-existing pool. Private workload
Terraform and Azure ML pipelines receive the Managed DevOps Pool through
`agentPoolName` only after platform provisioning.

## Keyless identity contract

Both service connections must use Azure Resource Manager workload identity
federation. No client secret is generated, copied, or stored by the factory.

- `platform_service_connection_name` bootstraps backend hardening, network, private
  DNS/private endpoints, and the Managed DevOps Pool.
- The protected environment variable group identifies the workload connections
  used by Terraform and Azure ML pipelines.

The identities need least-privilege access at their deployment scopes.
Bootstrap operations that create role assignments additionally require Owner,
User Access Administrator, or equivalent custom permissions.

The platform entrypoint calls
`templates/infra/platform-bootstrap.yml@mlops-templates`. The reusable template
owns `templates/infra/bicep/managed-devops-platform.bicep` and accepts:

- `environment`;
- the selected environment's Azure service connection and CI/CD principal;
- `devOpsInfrastructurePrincipalObjectId`;
- `location`, `resourceGroup`, and `virtualNetworkName`;
- `stateStorageAccountName`;
- `managedDevOpsPoolName` and `managedDevOpsPoolAlias`;
- `devCenterProjectResourceId`.

Its private defaults are VNet `10.20.0.0/16`, Managed DevOps Pool subnet
`10.20.1.0/24`, private endpoint subnet `10.20.2.0/24`, state container
`default`, VM SKU `Standard_D2ads_v5`, image `ubuntu-24.04`, and maximum
concurrency `2`.

The contract was validated against `mlops-templates` commit
`6078751d4690ddd6802fc275fa7e2917fddc0578`, which normalizes and validates
Terraform boolean parameters before planning and uses `TerraformInstaller@1`
to avoid the retired Node 10 task runtime. Its
`resolve-terraform-version.yml` template resolves `latest`, exact `x.y.z`,
and wildcard `x.y.x` requests to an available Terraform release; installer
display names avoid unresolved runtime macros without changing resolver or
task inputs. Generic online and batch deployment operations first inspect the
existing deployment, then update or create it so reruns are idempotent. Its
documentation uses `1.16.x`. The factory defaults to `refs/heads/main` for the
current smooth path; set `mlopsTemplatesRef` to a commit SHA when
reproducibility is preferred.

The full private Classical/AML CLI v2/Terraform generation path was validated
against `mlops-project-template` commit
`182d3f8e335dbb46d28c6adc9d304b2b5136f1f8`, including the live-proven
Data Explorer `Standard_E2ads_v5` capacity, Key Vault RBAC propagation
dependency, and identity-authenticated AML system datastores. The latter uses
`Microsoft.MachineLearningServices/workspaces@2025-06-01` through azapi
v2.12.0 to conditionally set both system datastore identity authentication
and managed-network `AllowInternetOutbound`, avoiding a ForceNew AzureRM
workspace block. Private mode then invokes `provisionManagedNetwork` with
Spark provisioning disabled after the workspace update, private endpoint,
and a contract-tracked 120-second RBAC propagation barrier. Both the AML
user-assigned identity and workspace system-assigned identity receive Azure
AI Enterprise Network Connection Approver on storage, Key Vault, and
container registry, plus Reader on the container registry. The barrier tracks
all eight assignments and the sorted target-resource contract rather than a
resource-group role. Compute waits for the update, endpoint, and provisioning
action. Its Azure DevOps Terraform pipelines request the latest stable
Terraform CLI release in the 1.16 line with `terraform_version: 1.16.x`.
Compute remains off the user subnet with node public IPs disabled. The online
pipeline selects a managed-VNet deployment definition without the unsupported
`egress_public_network_access` property for private environments; the direct
public DEV definition may retain enabled public egress.
Online deployments use `Standard_D2ds_v5`, and Azure DevOps batch deployments
reuse `azureml:cpu-cluster` rather than creating a separate compute.
Training and model-registration MLflow environments include
`azureml-ai-monitoring==1.0.0` immediately after `mlflow==2.22.4` so generated
scoring scripts can import Azure ML monitoring support.

The hardened state storage account has public network access disabled, shared
key access disabled, and default OAuth authentication enabled. The state
container is created through the Azure management plane before Terraform uses
Azure AD data-plane authentication.

## Pipeline registration and execution order

For private mode, `platform-ado-bootstrap.yml` is registered first as
`00-<environment>-platform-bootstrap`. Other Terraform infrastructure
entrypoints use a `10-` prefix, and workload entrypoints use a `20-` prefix.
Public mode retains the original unprefixed pipeline names and does not
register the private platform bootstrap. Registration order does not
automatically run or authorize a pipeline.

`config-factory-<environment>.yml` is a non-secret generation record for
operators and downstream tooling; it is not a substitute for the protected
variable group. Project-template entrypoints select `config-infra-<environment>.yml`
through their runtime `environment` parameter and receive pool/template
settings through `agentPoolName` and `mlopsTemplatesRef`.

Run and validate the pipelines in this order:

1. Create or select the WIF identities and authorize both service connections.
2. Bootstrap and harden the Terraform backend with Azure AD data-plane access
   and shared-key access disabled.
3. Deploy the VNet, delegated Managed DevOps Pool subnet, private DNS zones and
   links, and private endpoints.
4. Deploy and authorize the Managed DevOps Pool; confirm an agent can resolve
   and reach the private endpoints.
5. Run the `10-` workload Terraform pipeline from the Managed DevOps Pool.
6. Run the `20-` Azure Machine Learning registration, training, and endpoint pipelines
   from the Managed DevOps Pool.

Managed DevOps Pool and VNet regions must match. The delegated subnet is
exclusive to `Microsoft.DevOpsInfrastructure/pools`, must have sufficient
addresses for maximum agents, and should not overlap the service-reserved
`172.17.0.0/16` range.

After pipeline registration, explicitly authorize the generated pipelines to
use the Managed DevOps Pool. The `DevOpsInfrastructure` enterprise application
(`31687f79-5e43-4c1e-8c63-d9f4bff5cf8b`) needs Reader and Network Contributor
on the VNet; resolve and store its service-principal object ID in the protected
environment variable group.
