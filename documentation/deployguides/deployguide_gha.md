# Deployment Guide using Github Repositories Workflows

## Technical Requirements

### Source Control and DevOps
- **GitHub** as the source control repository
- **GitHub Actions** as the CI/CD orchestration tool
- [GitHub CLI](https://cli.github.com/) installed locally

### Azure Tools
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) installed locally
- One or more Azure subscriptions (separate subscriptions recommended for Dev and Prod environments)
   - **Important**: Free/Trial subscriptions may have quota limitations. Review the [Prerequisites](https://github.com/Azure/mlops-v2?tab=readme-ov-file#prerequisites) carefully before deployment.
- Azure service principal with permissions to create and manage resources

### Infrastructure as Code (Optional)
- [Terraform extension for Azure DevOps](https://marketplace.visualstudio.com/items?itemName=ms-devlabs.custom-terraform-tasks) (only if using Azure DevOps with Terraform)

### Local Development Environment
- **Shell environment**: Git Bash, [WSL](https://learn.microsoft.com/windows/wsl/install), or equivalent Unix shell

### WSL-Specific Setup (If Using Windows Subsystem for Linux)
If using WSL, complete all setup within the Unix environment:

1. **Install required tools**:
    ```bash
    sudo apt-get update
    sudo apt-get install dos2unix gh
    ```

2. **Configure GitHub CLI**:
    ```bash
    gh auth login
    ```

3. **Configure Git**:
    ```bash
    git config --global user.email "you@example.com"
    git config --global user.name "Your Name"
    ```

4. **VSCode integration** (optional):
    - Install the [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) extension
    - Connect VSCode to your WSL environment for seamless editing

> **Note**: Clone repositories and define all file paths within the WSL environment to avoid cross-platform compatibility issues.


> **Important**: Git version 2.51 or newer is required. See [upgrade instructions](https://github.com/cli/cli/blob/trunk/docs/install_linux.md#debian-ubuntu-linux-raspberry-pi-os-apt) if needed.
   

## Configure The GitHub Environment
---

1. **Replicate MLOps-V2 Template Repositories in your GitHub organization**  
   Go to https://github.com/Azure/mlops-templates/fork to fork the mlops templates repo into your Github org. This repo has reusable mlops code that can be used across multiple projects.

   ![image](./images/gh-fork.png)

   Go to https://github.com/Azure/mlops-project-template/generate to create a repository in your Github org using the mlops-project-template. This is the monorepo that you will use to pull example projects from in a later step.

   ![image](./images/gh-generate.png)

2. **Clone the mlops-v2 repository to local system**  
   On your local machine, select or create a root directory (ex: 'mlprojects') to hold your project repository as well as the mlops-v2 repository. Change to this directory.

   Clone the mlops-v2 repository to this directory. This provides the documentation and the `sparse_checkout.sh` script. This repository and folder will be used to bootstrap your projects:  
   `# git clone https://github.com/Azure/mlops-v2.git`

3. **Configure and run sparse checkout**  
   From your local project root directory, open the `/mlops-v2/sparse_checkout.sh` for editing. Edit the following variables as needed to select the infastructure management tool used by your organization, the type of Open this file in an editor and set the following variables:
   
   >**Note:**
   > When running the script through a  "vanilla" WSL, then you'll most likely get strange errors... In that case it might suffice to use dos2unix on the file
   > (in WSL) run; `dos2unix sparse_checkout.sh` (in the mlops-v2 repo folder)
   

   * **infrastructure_version** selects the tool that will be used to deploy cloud resources.
   * **project_type** selects the AI workload type for your project (classical ml, computer vision, or nlp)
   * **mlops_version** selects your preferred interaction approach with Azure Machine Learning
   * **git_folder_location** points to the root project directory to which you cloned mlops-v2 in step 3
   * **project_name** is the name (case sensitive) of your project. A  GitHub repository will be created with this name
   * **github_org_name** is your GitHub organization (or GitHub username)
   * **project_template_github_url** is the URL to the original or your generated clone of the mlops_project_template repository from step 1
   * **project_template_git_ref** is the branch, tag, or commit to fetch. Use an immutable commit SHA for repeatable validation.
   * **mlops_templates_repository** is the `owner/repository` containing reusable GitHub workflows.
   * **mlops_templates_git_ref** is the reusable workflow revision. Use the full immutable commit SHA.
   * **create_github_repository** controls whether the generated project is created and pushed to GitHub. Set it to `false` for local-only validation.
   * **orchestration** specifies the CI/CD orchestration to use
   <br><br>
   A sparse_checkout.sh example is below:  

   ```bash
      #options: terraform / bicep
      infrastructure_version=bicep

      #options: classical / cv / nlp
      project_type=classical
      
      #options: aml-cli-v2 / python-sdk-v1 / python-sdk-v2 / rai-aml-cli-v2
      mlops_version=python-sdk-v2
      
      #replace with the local root folder location where you want
      git_folder_location='/home/<username>/mlprojects'    
      
      #replace with your project name
      project_name=taxi-fare-regression   
      
      #replace with your github org name
      github_org_name=<orgname>
      
      #validated project-template source
      project_template_github_url=https://github.com/pgabriel-01/mlops-project-template

      #use an immutable commit SHA for repeatable generation
      project_template_git_ref=ff0c23a99192fd9f500dcd6666a62511c4120313

      #pin reusable workflow calls to an immutable commit
      mlops_templates_repository=pgabriel-01/mlops-templates
      mlops_templates_git_ref=be9755ccfc320fd1f2c1fb4f6b092d745d4fa6b5

      #set false to generate locally without creating or pushing a repository
      create_github_repository=true
      
      #options: github-actions / azure-devops
      orchestration=github-actions 
   ```
   Currently, the following pipelines are supported:
   - classical 

4. **Run sparse checkout**  
   The `sparse_checkout.sh` script will use ssh to authenticate to your GitHub organization. If this is not yet configured in your environment, follow the steps below or refer to the documentation at  [GitHub Key Setup](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent).
   
   > **GitHub Key Setup**
   >
   > On your local machine, create a new ssh key:  
   > `# ssh-keygen -t ed25519 -C "<your_email@example.com>"`  
   > You may press enter to all three prompts to create a new key in `/home/<username>/.ssh/id_ed25519`
   >
   > Add your SSH key to your SSH agent:  
   > `# eval "$(ssh-agent -s)" `  
   > `# ssh-add ~/.ssh/id_ed25519`
   >
   > Get your public key to add to GitHub:  
   > `# cat ~/.ssh/id_ed25519.pub`  
   > It will be a string of the format '`ssh-ed25519 ... your_email@example.com`'. Copy this string.
   >
   > [Add your SSH key to Github](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account). Under your account menu, select "Settings", then "SSH and GPG Keys". Select "New SSH key" and enter a title. Paste your public key into the key box and click "Add SSH key"

   From your root project directory (ex: mlprojects/), execute the `sparse_checkout.sh` script:  
   >  `# bash mlops-v2/sparse_checkout.sh`  

   This will run the script, using git sparse checkout to build a local copy of your project repository based on your choices configured in the script. It will then create the GitHub repository and push the project code to it.  

   Monitor the script execution for any errors. If there are errors, you can safely remove the local copy of the repository (ex: taxi_fare_regression/) as well as delete the GitHub project repository. After addressing the errors, run the script again.
   
   After the script runs successfully, the GitHub project will be initialized with your project files.

5. **Configure GitHub Actions Authentication with OIDC**

   This step creates an Azure AD application with federated credentials and GitHub secrets to allow the GitHub Action workflows to authenticate using OpenID Connect (OIDC) and create/interact with Azure Machine Learning Workspace resources.

   >**IMPORTANT**: This solution now uses OIDC workload identity federation instead of client secrets for enhanced security. No client secrets are stored or managed.

   **Step 5.1: Create Azure AD Application**

   From the command line, create an Azure AD app registration:
   > `# az ad app create --display-name <application_name>`

   This will output the application details. Copy the **appId** value.

   **Step 5.2: Create Service Principal**

   Create a service principal for the application:
   > `# az ad sp create --id <app_id_from_previous_step>`

   **Step 5.3: Assign Azure Permissions**

   The subscription-scoped Bicep deployment creates resources and role assignments.
   Assign `Contributor` plus `Role Based Access Control Administrator` to the
   service principal at the target subscription scope. Prefer this combination
   over `Owner`.

   ```bash
   subscription_scope=/subscriptions/<subscription_id>
   service_principal_object_id=$(az ad sp show --id <app_id> --query id -o tsv)

   az role assignment create \
     --assignee-object-id "$service_principal_object_id" \
     --assignee-principal-type ServicePrincipal \
     --role Contributor \
     --scope "$subscription_scope"

   az role assignment create \
     --assignee-object-id "$service_principal_object_id" \
     --assignee-principal-type ServicePrincipal \
     --role "Role Based Access Control Administrator" \
     --scope "$subscription_scope"

   # Verify only direct assignments at the requested subscription scope.
   # Some Azure CLI versions do not accept a boolean value after
   # --include-inherited, so filter the returned scope explicitly.
   az role assignment list \
     --assignee-object-id "$service_principal_object_id" \
     --scope "$subscription_scope" \
     --query "[?scope=='$subscription_scope' && (roleDefinitionName=='Contributor' || roleDefinitionName=='Role Based Access Control Administrator')].{id:id,role:roleDefinitionName,scope:scope}" \
     --output table
   ```

   **Step 5.3a: Get Service Principal Object ID**

   Get the object ID of the service principal:
   ```bash
   az ad sp show --id <app_id> --query id -o tsv
   ```
   
   **IMPORTANT**: Save this object ID value. For Bicep-based GitHub projects,
   configure it as the `AZURE_PRINCIPAL_OBJECT_ID` GitHub Environment variable.
   The Bicep deployment uses it for deterministic CI principal role assignments.

   **Step 5.4: Configure Federated Identity Credentials**

   Create a federated credential for each GitHub Environment used by the project.
   The issuer and audience must match GitHub Actions OIDC exactly.

   For the **dev** environment:
   ```bash
   az ad app federated-credential create --id <app_id> --parameters '{
     "name": "github-environment-dev",
     "issuer": "https://token.actions.githubusercontent.com",
     "subject": "repo:<github_org>/<repo_name>:environment:dev",
     "audiences": ["api://AzureADTokenExchange"],
     "description": "GitHub Actions dev environment"
   }'
   ```

   Repeat for `test` and `prod`, changing both the credential name and subject:

   ```bash
   az ad app federated-credential create --id <app_id> --parameters '{
     "name": "github-environment-test",
     "issuer": "https://token.actions.githubusercontent.com",
     "subject": "repo:<github_org>/<repo_name>:environment:test",
     "audiences": ["api://AzureADTokenExchange"],
     "description": "GitHub Actions test environment"
   }'

   az ad app federated-credential create --id <app_id> --parameters '{
     "name": "github-environment-prod",
     "issuer": "https://token.actions.githubusercontent.com",
     "subject": "repo:<github_org>/<repo_name>:environment:prod",
     "audiences": ["api://AzureADTokenExchange"],
     "description": "GitHub Actions prod environment"
   }'
   ```

   **Step 5.5: Add GitHub Environment Secrets and Variables**

   Create GitHub Environments named `dev`, `test`, and `prod`. Configure each
   environment separately so its OIDC subject and settings remain isolated.

   Add the following three environment secrets:

   1. **AZURE_CLIENT_ID**: The application (client) ID from step 5.1
   2. **AZURE_TENANT_ID**: Your Azure tenant ID (get with `az account show --query tenantId -o tsv`)
   3. **AZURE_SUBSCRIPTION_ID**: Your Azure subscription ID (get with `az account show --query id -o tsv`)

   Add the following environment variable:

   1. **AZURE_PRINCIPAL_OBJECT_ID**: The service principal object ID from Step 5.3a

   > **IMPORTANT NOTES:**
   > - Do NOT create an **AZURE_CREDENTIALS** secret (deprecated)
   > - Do NOT use the `--sdk-auth` flag (deprecated)
   > - OIDC authentication provides enhanced security with no client secrets to manage or rotate
   > - Each workflow will automatically receive short-lived tokens from GitHub
   > - Do not run a private-network deployment until an approved self-hosted
   >   runner has network and private DNS access to the target Azure resources
   > - If deploying infrastructure with Terraform, no additional ARM_* secrets are needed (OIDC is configured in the provider)

   The GitHub configuration is complete.

## Bootstrap Private Autoscaling GitHub Actions Runners

Private-network deployments require runner capacity that exists before the
generated Azure ML workflows can run. For autoscaling private runners, deploy a
dedicated private AKS cluster with GitHub Actions Runner Controller (ARC) and an
ARC runner scale set as a separately owned bootstrap layer.

The generated MLOps project does not create or update its own prerequisite AKS
cluster, ARC installation, or GitHub App. Keep that bootstrap lifecycle separate
so a failed workload deployment cannot remove the runner that is needed to
repair or delete the workload.

### Authentication boundaries

Use two independent identities:

- **ARC to GitHub**: Install a least-privilege GitHub App on only the repositories
  or organization resources that the runner scale set serves. Store its App ID,
  installation ID, and private key in the bootstrap platform's approved secret
  store and expose them to ARC through a Kubernetes Secret or an external
  secrets integration. Do not put the private key, a personal access token, or
  installation credentials in the generated repository.
- **Workflow to Azure**: Continue to use the GitHub Environment OIDC
  configuration from Step 5. ARC registration credentials do not replace
  `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, or the
  environment federated credentials.

Follow the permissions documented for the installed ARC version.
[GitHub's ARC authentication guidance](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/authenticate-to-the-api)
currently requires:

- Repository-scoped registration: repository **Administration: read and write**
  and **Metadata: read-only**.
- Organization-scoped registration: organization **Self-hosted runners: read and
  write**; repository Administration is not required solely for organization
  registration.

Prefer repository scope for a single project. Use organization scope only when
one centrally managed scale set intentionally serves multiple repositories.
GitHub's documented GitHub App flow assumes an organization-owned App. For a
repository owned by a personal account, confirm that the intended App ownership
and installation can register repository-scoped ARC runners before provisioning
AKS. If that compatibility cannot be confirmed, migrate the repository to an
approved GitHub organization and use an organization-owned App. Do not use a
long-lived personal access token as an unattended ARC credential.

Create the ARC `githubConfigSecret` reference in the same namespace as the
runner scale-set Helm release. Prefer an approved external-secret integration
over copying the private key into source-controlled Helm values.

### Optional personal-account GitHub App manifest bootstrap

[GitHub App manifests](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)
support App registration for a personal account at
`https://github.com/settings/apps/new`. This can predeclare the repository-level
ARC permissions and reduce manual configuration without introducing a personal
access token. It does not remove the requirement for the account owner to review
the registration, create the App, install it, and take custody of the generated
private key.

Run a temporary callback listener bound only to loopback, for example
`http://127.0.0.1:8787/github-app-manifest/callback`, and generate an
unguessable state value such as `openssl rand -hex 32`. Store the expected state
outside the repository. Submit a form using `POST` to
`https://github.com/settings/apps/new?state=<state>` with a `manifest` field
containing JSON shaped like:

```json
{
  "name": "<unique-arc-app-name>",
  "url": "https://github.com/actions/actions-runner-controller",
  "redirect_url": "http://127.0.0.1:8787/github-app-manifest/callback",
  "public": false,
  "request_oauth_on_install": false,
  "hook_attributes": {
    "url": "http://127.0.0.1:8787/github-app-manifest/webhook-unused",
    "active": false
  },
  "default_permissions": {
    "administration": "write",
    "metadata": "read"
  },
  "default_events": []
}
```

The callback must compare the returned `state` byte-for-byte with the stored
expected value before using the returned `code`. Reject the callback and do not
convert the code when the state is missing or different.

The code is single-use and the full three-step manifest flow must finish within
one hour. Exchange it once with
`POST /app-manifests/{code}/conversions`. The response contains the App ID and a
one-time PEM private key, along with generated client and webhook secrets that
ARC does not need. Do not print or log the response. Use a private directory
outside the checkout, a restrictive umask, and an intermediate file that is
deleted immediately:

```bash
secure_dir="$HOME/.config/arc-bootstrap/<app-name>"
mkdir -p "$secure_dir"
chmod 700 "$secure_dir"
umask 077

response_file=$(mktemp "$secure_dir/manifest-conversion.XXXXXX")
curl --fail --silent --show-error \
  --request POST \
  --header "Accept: application/vnd.github+json" \
  "https://api.github.com/app-manifests/<one-time-code>/conversions" \
  > "$response_file"

jq -e '.id and .pem' "$response_file" >/dev/null
jq -r '.pem' "$response_file" > "$secure_dir/github-app.pem"
chmod 600 "$secure_dir/github-app.pem"
jq -r '.id' "$response_file" > "$secure_dir/github-app-id"
rm -f "$response_file"
```

Do not run these commands with shell tracing enabled. The repository `.gitignore`
excludes `*.pem` as defense in depth, but the key must never be created inside a
checkout. After conversion, use the GitHub App settings page to install the
private App on the personal account and grant access only to the intended
repository. Record the installation ID without recording an installation token.
Only then transfer the App ID, installation ID, and PEM through the approved
secret-ingestion path used by the ARC bootstrap layer.

Because App creation, installation, and private-key download require an
authorized GitHub owner, stop before AKS provisioning when that owner is not
available. The owner must complete and record this continuation checklist:

1. Confirm whether the repository will remain personal-account owned or move to
   an approved organization.
2. Create or select the GitHub App under an ownership model supported for the
   chosen ARC registration scope.
3. Grant only the repository- or organization-scope permissions listed above,
   install the App only where required, and record the App ID and installation
   ID.
4. Generate the private key once and place it directly in the approved secret
   store. Do not paste it into chat, workflow logs, shell history, repository
   files, or ordinary Helm values.
5. Verify the installation can access the intended repository and approve the
   ARC `minRunners`, `maxRunners`, egress policy, and external log destination.
6. Authorize the platform operator to provision private AKS and ARC only after
   these checks are complete.

### Runner scale-set contract

- Configure the ARC runner scale-set name/label to match the generated project
  runner setting, such as `mlops-private`.
- Set an explicit `maxRunners` value to bound concurrency, Azure VM consumption,
  and unexpected cost.
- `minRunners: 0` provides zero-idle scaling but adds pod and node startup
  latency. A positive minimum reduces workflow startup time but incurs
  continuous AKS/node cost. Record the selected minimum and maximum as an
  operational decision rather than hard-coding them in reusable project assets.
- Use ephemeral runner pods and do not reuse a job workspace between workflow
  jobs.
- Apply Kubernetes resource requests/limits, node-pool maximums, and Azure quota
  checks consistently with the ARC maximum.
- Export controller, listener, runner, and `_diag` logs to an external log store;
  ephemeral runner diagnostics disappear when their pods are deleted.

### Private network, DNS, and egress prerequisites

Place ARC runner nodes in a dedicated, nondelegated subnet. Do not reuse a
subnet delegated to Azure DevOps Managed DevOps Pools or a private-endpoint
subnet. The runner and generated workload address spaces must not overlap.

Before validation or deployment, provide:

1. Bidirectional routing between the runner VNet and generated workload VNet.
   With VNet peering, both the workload-to-hub and hub-to-workload peerings must
   exist. Define which deployment owns each direction; do not have independent
   deployments create the same peering.
2. Virtual network links from the Azure ML private DNS zones to the runner VNet.
   This includes Azure ML API and notebooks, Storage blob/file/queue/table/dfs,
   Key Vault, and Azure Container Registry zones. DNS link registration must be
   disabled.
3. Controlled outbound DNS and HTTPS connectivity for the GitHub API and Actions
   service, GitHub Container Registry when used, Microsoft Entra ID, Azure
   Resource Manager and required Azure service control planes, AKS image sources,
   configured Python/package feeds, and workload container registries.
4. No public inbound management path to the runner nodes. Administer AKS through
   approved private connectivity and Azure control-plane mechanisms.

The generated Bicep pattern exposes `runner_hub_vnet_resource_id`, which is empty
by default. When set in consumer configuration, the workload deployment owns the
workload-to-hub peering and links its private DNS zones to that VNet. The
`manage_runner_hub_to_workload_peering` setting is `false` by default: the hub
owner must create the reciprocal peering separately. Set it to `true` only when
the workload deployment identity has approved write access to the hub VNet scope
and this deployment is the single owner of that peering.

Reusable factory and project-template assets must not contain tenant IDs,
subscription IDs, repository names, VNet IDs, or other live environment values.

### Bootstrap validation gate

Do not dispatch the workload infrastructure workflow until all of the following
are true:

1. GitHub reports an online runner for the repository with the configured ARC
   scale-set label.
2. A runner job can obtain a GitHub Environment OIDC token and authenticate to
   the intended Azure subscription.
3. From the runner network, Azure Resource Manager is reachable and the expected
   Azure ML, Storage, Key Vault, and ACR private names resolve through the private
   path.
4. The generated Bicep validates with deployment disabled.

## Deploy Machine Learning Project Infrastructure Using GitHub Actions

1. **Configure Azure ML Environment Parameters**

   Python SDK v2 + GitHub Actions + Bicep projects contain
   `config-infra-dev.yml`, `config-infra-test.yml`, and `config-infra-prod.yml`.
   Select the target with the workflow's `environment` input; the selected GitHub
   Environment supplies the matching OIDC identity settings. Start with `dev`.

   Other generated patterns may use branch-based environment selection. Follow
   the generated project README and workflow inputs when they differ from the
   legacy examples later in this guide.

>**Important:**
>> Note that `config-infra-prod.yml` and `config-infra-dev.yml` files use default region as **eastus** to deploy resource group and Azure ML Workspace. If you are using Free/Trial or similar learning purpose subscriptions, you must do one of the below  -
> 1. If you decide to use **eastus** region, ensure that your subscription(s) have a quota/limit of up to 64 vCPUs for **Standard DSv3 Family vCPUs**. The default compute cluster uses **STANDARD_D16S_V3** (16 vCPUs per node, up to 4 nodes = 64 vCPUs max). Visit Subscription page in Azure Portal as shown below to validate this.
        ![alt text](images/susbcriptionQuota.png)
> 2. If not, you should change it to a region where **Standard DSv3 Family vCPUs** has sufficient quota.
> 3. You can easily change the VM SKU by editing the `aml_compute_sku` parameter in your config file:
>      - `config-infra-prod.yml` or `config-infra-dev.yml` - set `aml_compute_sku: <YOUR_SKU>` (e.g., `STANDARD_D4S_V3`)
>      - This works for both Bicep and Terraform deployments
> 4. For ML pipeline compute (separate from infrastructure), you may need to edit:
>      - `mlops-templates/aml-cli-v2/mlops/devops-pipelines/deploy-model-training-pipeline.yml` - for ML pipeline compute
>      - `mlops-project-template/classical/aml-cli-v2/mlops/devops-pipelines/deploy-batch-endpoint-pipeline.yml`
>      - `mlops-project-template/classical/aml-cli-v2/mlops/azureml/deploy/online/online-deployment.yml`
>
> **Note**: The default infrastructure SKU is **STANDARD_D16S_V3** (3rd generation). ML pipelines may use different SKUs like **Standard_D4s_v5**. Adjust based on your quota and requirements.

   Edit each file to configure a namespace, postfix string, Azure location, and environment for deploying your Dev and Prod Azure ML environments. Default values and settings in the files are show below:

   > ```bash
   > namespace: mlopsv2 #Note: A namespace with many characters will cause storage account creation to fail due to storage account names having a limit of 24 characters.  
   > postfix: 0001  
   > location: eastus  
   > environment: dev  
   > enable_aml_computecluster: true  
   > enable_monitoring: false
   > aml_compute_sku: STANDARD_D16S_V3  # VM SKU for AML compute cluster
   >```
   
   The first four values are used to create globally unique names for your Azure environment and contained resources. The `aml_compute_sku` parameter allows you to customize the VM size for your AML compute cluster (default: `STANDARD_D16S_V3`). Edit these values to your liking then save, commit, push, or pr to update these files in the project repository.

2. **Configure Terraform Variables (Required for GitHub Actions Permissions)**

   In your project repository, copy the `infrastructure/terraform/terraform.tfvars.example` file and rename it to `terraform.tfvars`. Then edit the file to add the GitHub Actions service principal object ID from Step 5.3a:

   ```bash
   namespace: mlopsv2
   postfix: "0001"
   location: "eastus"
   environment: "dev"  
   enable_aml_computecluster: true
   enable_monitoring: false
   aml_compute_sku: "STANDARD_D16S_V3"  # VM SKU for AML compute cluster

   # REQUIRED: GitHub Actions service principal object ID for CI/CD permissions
   # Get this value from Step 5.3a above:
   # az ad sp show --id <app_id> --query id -o tsv
   github_actions_service_principal_id = "your-service-principal-object-id"

   # VNet and Private Endpoints Configuration
   # Set to true to enable network isolation with private endpoints
   enable_private_endpoints = false

   # VNet address space (only used if enable_private_endpoints = true)
   # Ensure the address space is large enough for your needs:
   # - Private endpoints: ~20 IPs (one per service per subnet)
   # - Compute instances/cluster nodes: 1 IP per node
   # Example: 10.0.0.0/16 provides 65,536 addresses
   vnet_address_space               = "10.0.0.0/16"
   training_subnet_address_prefix   = "10.0.0.0/24"    # For compute cluster nodes (254 hosts)
   endpoints_subnet_address_prefix  = "10.0.1.0/24"    # For private endpoints (254 hosts)
   ```

   **Configuration Guidelines**:
   - **namespace**: Short name for your project (keep it concise to avoid storage account name length limits)
   - **postfix**: Unique identifier (e.g., "0001"). If redeploying after deletion, use a different postfix to avoid Azure ML workspace soft-delete conflicts (see note below)
   - **environment**: "dev" or "prod" (should match your branch context)
   - **location**: Azure region (default: "eastus")
   - **github_actions_service_principal_id**: Service principal object ID from Step 5.3a (NOT the app ID)

   This configuration enables Terraform to automatically:
   - Grant the GitHub Actions service principal the required permissions to:
     - Register datasets in Azure ML
     - Upload data to the workspace storage account
     - Execute training pipelines that access data in the storage account
   - Configure Network Security Groups with Azure ML required rules
   - Create private DNS zones for name resolution within the VNet

   These permissions (Storage Blob Data Reader and Storage Blob Data Contributor) will be automatically assigned to the Azure ML workspace storage account during infrastructure deployment.

   **For Bicep**: Role assignments are handled differently - see the Bicep templates for specific implementation details.

   > **Best Practice**: Using OIDC (OpenID Connect) federation instead of client secrets provides better security by eliminating the need to manage and rotate secrets. The service principal authenticates using short-lived tokens issued by GitHub, which reduces the risk of credential exposure.

   > **Alternative**: If your organization doesn't allow OIDC, you can use a client secret instead. However, this requires storing and managing secrets, which increases security risks. See [GitHub's documentation on secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets) for more information.

   > **Note**: The `github_actions_service_principal_id` must be the **object ID**, not the application ID. You can retrieve it using:

   ```bash
   az ad sp show --id <APPLICATION_ID> --query id -o tsv
   ```

2.1. **(Optional) Configure Virtual Network and Private Endpoints**

   The infrastructure supports optional network isolation using Azure Virtual Networks and Private Endpoints for enhanced security. By default, this feature is disabled (`enable_private_endpoints = false`) to maintain backward compatibility and simplify initial deployments.

   **When to Enable VNet and Private Endpoints:**
   - Production environments requiring network isolation
   - Compliance requirements mandating private connectivity
   - Sensitive data workloads requiring additional security

   **To enable network isolation**, add the following to your `infrastructure/terraform/terraform.tfvars.sample`:

   ```bash
   # Enable VNet and private endpoints for network isolation
   enable_private_endpoints = true

   # Customize VNet address space if needed (optional)
   vnet_address_space               = "10.0.0.0/16"      # Default
   training_subnet_address_prefix   = "10.0.0.0/24"     # For compute (254 hosts)
   endpoints_subnet_address_prefix  = "10.0.1.0/24"     # For endpoints (254 hosts)
   ```

   **What gets deployed when enabled:**
   - Virtual Network with two subnets (training and endpoints)
   - Network Security Group with Azure ML required rules
   - Private endpoints for: ML Workspace, Storage (blob/file/dfs), Key Vault, Container Registry
   - Private DNS zones for name resolution within the VNet

   **Impact:**
   - All Azure ML resources communicate through private IPs
   - Public network access restricted on storage, Key Vault, and Container Registry
   - Deployment time increases by ~5 minutes


   > **Note**: For initial evaluation and development environments, you can leave `enable_private_endpoints = false` (default). The infrastructure will deploy with public network access, which simplifies setup and reduces costs. You can always enable private endpoints later when moving to production.

3. **Deploy Azure Machine Learning Infrastructure**  
   > Note:
   >
   > The _enable_monitoring_ flag in these files defaults to False. Enabling this flag will add additional elements to the deployment to support Azure ML monitoring based on https://github.com/microsoft/AzureML-Observability. This will include an ADX cluster and increase the deployment time and cost of the MLOps solution.
   
3. **Deploy Azure Machine Learning Infrastructure**

   In your GitHub project repository (ex: taxi-fare-regression), select **Actions**

   ![GH-actions](./images/gh-actions.png)

   This will display the pre-defined GitHub workflows associated with your project. For a classical machine learning project, the available workflows will look similar to this:

   ![GH-workflows](./images/gh-workflows.png)

   Depending on the use case, available workflows may vary. For Python SDK v2 +
   GitHub Actions + Bicep, select **Deploy infrastructure**, choose the `dev`
   environment, validate first, and only select the deployment option after
   reviewing validation output.

   ![GH-deploy-infra](./images/gh-deploy-infra.png)

   On the right side of the page, select **Run workflow**, choose the target
   environment, and monitor the workflow. Private-network environments require
   the configured self-hosted runner to be online before validation or deployment.

   ![GH-infra-pipeline](./images/gh-infra-pipeline.png)

   When the pipline has complete successfully, you can find your Azure ML Workspace and associated resources by logging in to the Azure Portal.

   Next, a model training and scoring pipelines will be deployed into the new Azure Machine Learning environment.

## Sample Training and Deployment Scenario

The solution accelerator includes code and data for a sample end-to-end machine learning pipeline which runs a linear regression to predict taxi fares in NYC. The pipeline is made up of components, each serving different functions, which can be registered with the workspace, versioned, and reused with various inputs and outputs. Sample pipelines and workflows for the Computer Vision and NLP scenarios will have different steps and deployment steps.

This training pipeline contains the following steps:

### Pipeline Components

**Prepare Data**

This component takes multiple taxi datasets (yellow and green) and merges/filters the data, and prepares the train/val and evaluation datasets.

- **Input**: Local data under `./data/` (multiple `.csv` files)
- **Output**: Single prepared dataset (`.csv`) and train/val/test datasets

**Train Model**

This component trains a Linear Regressor with the training set.

- **Input**: Training dataset
- **Output**: Trained model (pickle format)

**Evaluate Model**

This component uses the trained model to predict taxi fares on the test set.

- **Input**: ML model and test dataset
- **Output**: Performance of model and a deploy flag whether to deploy or not

This component compares the performance of the model with all previous deployed models on the new test dataset and decides whether to promote the model into production. Promoting the model into production happens by registering the model in the AML workspace.

**Register Model**

This component scores the model based on how accurate the predictions are in the test set.

- **Input**: Trained model and the deploy flag
- **Output**: Registered model in Azure Machine Learning

## Deploying the Model Training Pipeline to the Test Environment

Next, you will deploy the model training pipeline to your new Azure Machine Learning workspace. This pipeline will create a compute cluster instance, register a training environment defining the necessary Docker image and Python packages, register a training dataset, then start the training pipeline described in the previous section. When the job is complete, the trained model will be registered in the Azure ML workspace and be available for deployment.

In your GitHub project repository (ex: taxi-fare-regression), select **Actions**

![GH-actions](./images/gh-actions.png)

Select the **deploy-model-training-pipeline** from the workflows listed on the left and click **Run Workflow** to execute the model training workflow. This will take several minutes to run, depending on the compute size.

![Pipeline Run](./images/gh-training-pipeline.png)

Once completed, a successful run will register the model in the Azure Machine Learning workspace.

> **Note**: If you want to check the output of each individual step, for example to view output of a failed run, click a job output, and then click each step in the job to view any output of that step.

![Training Step](./images/gh-training-step.png)

With the trained model registered in the Azure Machine Learning workspace, you are ready to deploy the model for scoring.


## Deploying the Trained Model in Dev

This scenario includes prebuilt workflows for two approaches to deploying a trained model, batch scoring or deploying a model to an endpoint for real-time scoring. For environment-based projects, choose `dev` when dispatching either workflow to test the model in the DEV Azure ML workspace.

In your GitHub project repository (ex: taxi-fare-regression), select **Actions**  
 
   ![GH-actions](./images/gh-actions.png)

 ### Online Endpoint  
      
Select the **deploy-online-endpoint-pipeline** from the workflows listed on the left and click **Run workflow** to execute the online endpoint deployment pipeline workflow. The steps in this pipeline will create an online endpoint in your Azure Machine Learning workspace, create a deployment of your model to this endpoint, then allocate traffic to the endpoint.

   ![gh online endpoint](./images/gh-online-endpoint.png)
   
   Once completed, you will find the online endpoint deployed in the Azure ML workspace and available for testing.

 ![aml-taxi-oep](./images/aml-taxi-oep.png)

### Batch Endpoint
      
Select the **deploy-batch-endpoint-pipeline** from the workflows and click **Run workflow** to execute the batch endpoint deployment pipeline workflow. The steps in this pipeline will create a new AmlCompute cluster on which to execute batch scoring, create the batch endpoint in your Azure Machine Learning workspace, then create a deployment of your model to this endpoint.

![gh batch endpoint](./images/gh-batch-endpoint.png)

Once completed, you will find the batch endpoint deployed in the Azure ML workspace and available for testing.

![aml-taxi-bep](./images/aml-taxi-bep.png)

## Testing Deployed Endpoints

After deploying your endpoints, you can test them to validate model inference.

### Testing Online Endpoint

1. **Get endpoint details**:
   ```bash
   az ml online-endpoint show --name <endpoint-name> \
     --workspace-name <workspace-name> \
     --resource-group <resource-group> \
     --query "{ScoringUri:scoring_uri}" --output table
   ```

2. **Get authentication key**:
   ```bash
   az ml online-endpoint get-credentials --name <endpoint-name> \
     --workspace-name <workspace-name> \
     --resource-group <resource-group> \
     --query "primaryKey" --output tsv
   ```

3. **Create test request** (pandas DataFrame JSON format):
   
   The online endpoint expects input in pandas DataFrame JSON format. Create a file `test-request.json`:
   ```json
   {
     "input_data": {
       "columns": ["distance", "dropoff_latitude", "dropoff_longitude", "dropoff_taxizone_id", "dropoff_borough", "extra", "fare_amount", "improvement_surcharge", "mta_tax", "passenger_count", "payment_type", "pickup_latitude", "pickup_longitude", "pickup_taxizone_id", "pickup_borough", "rate_code_id", "store_and_fwd_flag", "tip_amount", "tolls_amount", "total_amount", "trip_type"],
       "index": [0, 1],
       "data": [
         [0.45, 40.67, -74.01, 7, "Manhattan", 0, 3.5, 0.3, 0.5, 1, 1, 40.68, -74.0, 7, "Manhattan", 1, "N", 0, 0, 4.3, 1],
         [18.51, 40.64, -73.78, 132, "Queens", 0.5, 52.0, 0.3, 0.5, 1, 1, 40.77, -73.97, 237, "Manhattan", 1, "N", 10.0, 0, 63.3, 1]
       ]
     }
   }
   ```

4. **Invoke endpoint**:
   ```bash
   curl -X POST "<scoring-uri>" \
     -H "Authorization: Bearer <authentication-key>" \
     -H "Content-Type: application/json" \
     --data @test-request.json
   ```

5. **Expected output**: JSON array of predictions (e.g., `[7.14, 47.33]`)

### Testing Batch Endpoint

1. **Upload test data to workspace**:
   ```bash
   az ml data create --name taxi-batch \
     --version 1 \
     --workspace-name <workspace-name> \
     --resource-group <resource-group> \
     --path <path-to-test-data.csv> \
     --type uri_file
   ```

2. **Invoke batch endpoint**:
   ```bash
   az ml batch-endpoint invoke --name <endpoint-name> \
     --workspace-name <workspace-name> \
     --resource-group <resource-group> \
     --input <data-path> \
     --input-type uri_file
   ```

3. **Monitor batch job**: The command will output a job ID. Use it to check status:
   ```bash
   az ml job show --name <job-id> \
     --workspace-name <workspace-name> \
     --resource-group <resource-group>
   ```

**Note**: Batch endpoint invocation requires Storage Blob Data Reader and Storage Blob Data Contributor roles on the workspace storage account. These are automatically granted to the GitHub Actions service principal if you configured `github_actions_service_principal_id` in Step 2.
   
 
## Moving to Production

Example scenarios can be trained and deployed to DEV, test, and production
environments. Environment-based projects promote by dispatching the same
workflow with the target GitHub Environment rather than deriving the Azure
environment from the branch name.

The sample training and deployment Azure ML pipelines and GitHub workflows can be used as a starting point to adapt your own modeling code and data.

## Destroying Environments

The following Terraform destroy example applies only to generated Terraform
patterns. The Python SDK v2 + GitHub Actions + Bicep pattern does not currently
generate a destroy workflow; use an explicitly reviewed Azure deletion process
for that pattern.

For private AKS + ARC deployments, treat workload cleanup and runner-platform
cleanup as separate operations:

1. Stop new workflow dispatches and allow or cancel queued and active jobs.
2. Remove Azure ML online and batch deployments/endpoints before deleting the
   workspace or workload resource group.
3. Remove workload-owned private DNS links and both directions of VNet peering
   according to the documented ownership contract.
4. Delete the workload infrastructure and verify that its resource groups and
   managed resource groups are gone.
5. Keep AKS/ARC available while other workloads still use the runner scale set.
   Only when the bootstrap platform is no longer shared or required, set the
   runner scale set minimum and maximum to zero, verify that ephemeral runners
   are gone from GitHub, uninstall the ARC scale set/controller, remove its
   GitHub App credential material, and then delete the dedicated AKS resources.
6. Revoke or uninstall the GitHub App when it no longer serves any repository.
   Removing Azure workload OIDC federated credentials is a separate identity
   cleanup decision.

When you need to tear down a Terraform development or production environment:

1. **Automatic Endpoint Cleanup**: The destroy workflow automatically deletes all Azure ML endpoints (online and batch) before destroying the infrastructure. This prevents the "Cannot delete resource while nested resources exist" error.

2. **Run the destroy workflow**:
   ```bash
   # For dev environment (run from dev branch)
   gh workflow run tf-gha-deploy-infra.yml --ref dev -f action=destroy
   
   # For prod environment (run from main branch)
   gh workflow run tf-gha-deploy-infra.yml --ref main -f action=destroy
   ```

3. **Monitor the workflow**: The destroy process takes approximately 9-12 minutes and includes:
   - Detection of workspace existence
   - Automatic deletion of all online endpoints
   - Automatic deletion of all batch endpoints
   - 2-minute wait for endpoint deletions to process (online endpoints can take 2-3 minutes)
   - Terraform infrastructure destroy
   - Automatic cleanup of Terraform state storage

4. **Verify cleanup**:
   ```bash
   # Check for remaining resource groups
   az group list --query "[?starts_with(name, 'rg-<namespace>-<postfix>')]" --output table
   ```

5. **Expected result**: All resource groups should be deleted, including:
   - `rg-<namespace>-<postfix><environment>` (main resources)
   - `rg-<namespace>-<postfix><environment>-tf` (Terraform state)
   - Managed resource groups (automatically cleaned up)

**Troubleshooting**:
- If the destroy fails with endpoint errors, the endpoints may still be deleting. Wait 60 seconds and retry the destroy workflow.
- If you manually deleted the workspace, the destroy workflow will skip endpoint deletion and proceed with cleanup.
- Old resource groups from previous deployments with different postfix values must be manually deleted if desired.

## Next Steps
---

This finishes the demo according to the architectual pattern: Azure Machine Learning Classical Machine Learning. Next you can dive into your Azure Machine Learning service in the Azure Portal and see the inference results of this example model. 

As elements of Azure Machine Learning are still in development, the following components are not part of this demo:
- Model and pipeline promotion from Dev to Prod
- Secure Workspaces
- Model Monitoring for Data/Model Drift
- Automated Retraining
- Model and Infrastructure triggers

Interim it is recommended to schedule the deployment pipeline for development for complete model retraining on a timed trigger.

For questions, please [submit an issue](https://github.com/Azure/mlops-v2/issues) or reach out to the development team at Microsoft.
