#!/usr/bin/env zsh

export GOOGLE_APPLICATION_CREDENTIALS="${HOME}/.config/gcloud/application_default_credentials.json"

COMMAND=${1-"plan"}
ENV=${2-"prod"} # dev, prod, general

echo ""
echo "########################################################################"
echo "Running terraform command - ${COMMAND} - for environment - ${ENV}"
echo "########################################################################"
echo ""

echo "Selecting Terraform Workspace - ${ENV}"
terraform workspace select -or-create ${ENV}

echo "Running terraform command - ${COMMAND}"
if [ ${COMMAND} = "init" ]; then
    # terraform ${COMMAND} -var-file=main.tfvars -var-file=secrets.tfvars -var="environment=${ENV}"
    terraform ${COMMAND} -upgrade -var-file=main.tfvars -var-file=secrets.tfvars -var="environment=${ENV}"

elif [ ${COMMAND} = "validate" ]; then
    terraform ${COMMAND}

elif [ ${COMMAND} = "plan" ]; then
    terraform ${COMMAND} -var-file=main.tfvars -var-file=secrets.tfvars -var="environment=${ENV}" -out=plans/${ENV}

elif [ ${COMMAND} = "apply" ]; then
    terraform ${COMMAND} -auto-approve plans/${ENV}

elif [ ${COMMAND} = "destroy" ]; then
    terraform ${COMMAND} -var-file=main.tfvars -var-file=secrets.tfvars -var="environment=${ENV}"

elif [ ${COMMAND} = "staterm" ]; then
    MODULE_PATH=${3}
    terraform state rm "${MODULE_PATH}"

elif [ ${COMMAND} = "statels" ]; then
    MODULE_PATH=${3}
    terraform state list

elif [ ${COMMAND} = "import" ]; then
    TO_MODULE=${3}
    FROM_AWS=${4}
    echo "terraform import "${TO_MODULE}" "${FROM_AWS}""
    terraform import -var-file=secrets.tfvars "${TO_MODULE}" "${FROM_AWS}"

else
    echo "Unsupported terraform command received - '${COMMAND}'. Must be one of (init | plan | apply | destroy)"
fi
