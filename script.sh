#!/bin/bash
# chmod +x  script.sh
# ./script.sh

# az login 
# Or 
# export CLIENT_ID=YOUR_SERVICE_PRINCIPAL_CLIENT_ID
# export CLIENT_SECRET=YOUR_SERVICE_PRINCIPAL_CLIENT_SECRET
# export TENANT_ID=YOUR_SERVICE_PRINCIPAL_TENANT_ID
# export SUBSCRIPTION=YOUR_SERVICE_PRINCIPAL_SUBSCRIPTION
#az login --service-principal -u $CLIENT_ID -p $CLIENT_SECRET --tenant $TENANT_ID
#az account set --name $SUBSCRIPTION
# Or
# use azure cloudshell
# Or ...........

echo -e "\033[41mDefining variables\033[0m"

# variables
RESOURCE_GROUP=AKS-WORLOAD-IDENTITY
LOCATION=westeurope
AKS_CLUSTER_NAME="ask-workload-identity"
LOCATION="westeurope"
SERVICE_ACCOUNT_NAMESPACE="default"
SERVICE_ACCOUNT_NAME="workload-identity-service-account"
ACR_NAME=askworkloadidentity
IMAGE_NAME=ask-workload-identity-test-image
IMAGE_TAG=latest
# user assigned identity name
UAID="workload-user-assigned-managed-identity"
# federated identity name
FICID="workload-federated-identity"

echo "install the aks-preview extension"
# install the aks-preview extension

az extension add --name aks-preview

echo "update the aks-preview extension"
# update the aks-preview extension
az extension update --name aks-preview

# Register the 'EnableWorkloadIdentityPreview' feature flag
echo "Register the 'EnableWorkloadIdentityPreview' feature flag"
az feature register --namespace "Microsoft.ContainerService" --name "EnableWorkloadIdentityPreview"

# Verify the registration status
echo "Verify the registration status"
az feature show --namespace "Microsoft.ContainerService" --name "EnableWorkloadIdentityPreview"

# Create resource group
echo "Creating resource group"
az group create -l $LOCATION -n $RESOURCE_GROUP

# Deploy an AKS cluster using the Azure CLI with OpenID Connect Issuer and managed identity.
echo "Deploy an AKS cluster using the Azure CLI with OpenID Connect Issuer and managed identity."
az aks create -g $RESOURCE_GROUP -n $AKS_CLUSTER_NAME --node-count 1 --enable-oidc-issuer --enable-workload-identity --generate-ssh-keys

### Update an existing AKS cluster using the Azure CLI with OpenID Connect Issuer and managed identity.
### az aks update -n $AKS_CLUSTER_NAME -g $RESOURCE_GROUP --enable-oidc-issuer --enable-workload-identity

#Create a managed identity and grant permissions to access the secret
echo -e "\033[41m Creating a managed identity and grant permissions to access the secret\033[0m"
az identity create --name "${UAID}" --resource-group "${RESOURCE_GROUP}" --location "${LOCATION}" --subscription "${SUBSCRIPTION}"

# To get the OIDC Issuer URL and user assigned managed identity and save it to an environmental variable

echo -e "\033[41m Getting the OIDC Issuer URL and user assigned managed identity and save it to an environmental variable \033[0m"
export USER_ASSIGNED_CLIENT_ID="$(az identity show --resource-group "${RESOURCE_GROUP}" --name "${UAID}" --query 'clientId' -otsv)"
export AKS_OIDC_ISSUER="$(az aks show -n $AKS_CLUSTER_NAME -g $RESOURCE_GROUP --query "oidcIssuerProfile.issuerUrl" -otsv)"

echo "USER_ASSIGNED_CLIENT_ID = $USER_ASSIGNED_CLIENT_ID"
echo "AKS_OIDC_ISSUER = $AKS_OIDC_ISSUER"

# Establish federated identity credential
 echo -e "\033[41m Establishing federated identity credential \033[0m"
 az identity federated-credential create --name ${FICID} --identity-name ${UAID} --resource-group ${RESOURCE_GROUP} --issuer ${AKS_OIDC_ISSUER} --subject system:serviceaccount:${SERVICE_ACCOUNT_NAMESPACE}:${SERVICE_ACCOUNT_NAME}

az aks get-credentials -g $RESOURCE_GROUP -n $AKS_CLUSTER_NAME

 # Create an azure container registry . The name must be globally unique.
echo -e "\033[41m Creating azure container registry \033[0m"
az acr create -n $ACR_NAME -g $RESOURCE_GROUP --sku basic

while [ $(az acr show --name $ACR_NAME -g $RESOURCE_GROUP --query "provisioningState" -o tsv) != "Succeeded" ]
do
  echo "Waiting for ACR $ACR_NAME to be fully provisioned..."
  sleep 5s
done

echo "ACR $ACR_NAME is now fully provisioned."

# Assign acrpull role to azure kubernetes service

 echo "Assigning acrpull role to azure kubernetes service"
 ACR_ID=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query "id" --output tsv)
 echo $ACR_ID
 MANAGED_IDENTITY_CLIENT_ID=$(az aks show --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --query "identityProfile.kubeletidentity.clientId" --output tsv)
 echo $MANAGED_IDENTITY_CLIENT_ID
 az role assignment create --assignee $MANAGED_IDENTITY_CLIENT_ID --role acrpull --scope $ACR_ID
 az aks check-acr --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --acr "$ACR_NAME.azurecr.io"

#create service account 

echo -e "\033[41m Creating service account \033[0m"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: ${USER_ASSIGNED_CLIENT_ID}
  labels:
    azure.workload.identity/use: "true"
  name: ${SERVICE_ACCOUNT_NAME}
  namespace: ${SERVICE_ACCOUNT_NAMESPACE}
EOF

# echo -e "\033[41m Checking wether service account is creates successfully \033[0m"
kubectl get ServiceAccount 
kubectl describe  ServiceAccount ${SERVICE_ACCOUNT_NAME}

# Login to azure azure container registry
 echo -e "\033[41m Login to azure azure container registry \033[0m"
 az acr login --name $ACR_NAME
 az acr login -n $ACR_NAME --expose-token

 # Building docker image
 docker build . -t "${ACR_NAME}.azurecr.io/$IMAGE_NAME:$IMAGE_TAG"

 docker push "${ACR_NAME}.azurecr.io/$IMAGE_NAME:$IMAGE_TAG"

#  kubectl  delete  -f my-powershell-pod.yml 

#  kubectl  apply  -f my-powershell-pod.yml 


echo -e "\033[41m Deploying a pod using powershell  image \033[0m"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: my-powershell-pod
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: ${SERVICE_ACCOUNT_NAME}
  containers:
  - name: my-powershell-container
    image: ${ACR_NAME}.azurecr.io/$IMAGE_NAME:$IMAGE_TAG
    command: [ "pwsh", "-command", "./my-script.ps1" ]
    
  restartPolicy: Never
EOF


# echo -e "\033[41m Checking wether my-powershell-pod is creates successfully \033[0m"
kubectl get pod my-powershell-pod 
kubectl describe  pod  my-powershell-pod

 #wait until pod is completed 
 kubectl wait --for=condition=complete --timeout=60s pod/my-powershell-pod

# get logs
 kubectl logs my-powershell-pod 