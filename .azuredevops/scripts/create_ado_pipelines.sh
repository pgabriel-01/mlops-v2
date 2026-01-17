repo_name=$1
project_name=$2
path_to_mlops_pipelines=mlops/devops-pipelines

cd $repo_name

# Detect infrastructure pipeline path (bicep uses 'pipelines', terraform uses 'devops-pipelines')
if [ -d "infrastructure/pipelines" ]; then
    path_to_infrastructure_pipelines=infrastructure/pipelines
elif [ -d "infrastructure/devops-pipelines" ]; then
    path_to_infrastructure_pipelines=infrastructure/devops-pipelines
else
    echo "ERROR: No infrastructure pipelines folder found"
    exit 1
fi

az pipelines folder create \
    --path $repo_name \
    --project $project_name

az pipelines folder create \
    --path $repo_name/infrastructure \
    --project $project_name

az pipelines folder create \
    --path $repo_name/mlops \
    --project $project_name

mlops_pipeline_files=$(ls $path_to_mlops_pipelines)

for file in $mlops_pipeline_files
do
    az pipelines create \
        --name ${file%.*} \
        --detect true \
        --description "Automatically created pipeline for MLOps $file" \
        --repository $repo_name \
        --branch main \
        --yml-path $path_to_mlops_pipelines/$file \
        --project $project_name \
        --repository-type tfsgit \
        --skip-first-run true \
        --folder-path $repo_name/mlops
done

infra_pipeline_files=$(ls $path_to_infrastructure_pipelines)

for file in $infra_pipeline_files
do
    az pipelines create \
        --name ${file%.*} \
        --detect true \
        --description "Automatically created pipeline for infra $file" \
        --repository $repo_name \
        --branch main \
        --yml-path $path_to_infrastructure_pipelines/$file \
        --project $project_name \
        --repository-type tfsgit \
        --skip-first-run true \
        --folder-path $repo_name/infrastructure
done
