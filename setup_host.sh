# --------------------------------------------------------------
#    install required packages
# --------------------------------------------------------------

yum install git yq jq unzip -y
export PATH="/usr/local/bin:$PATH"


# --- KUBECTL ---
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
yum install -y kubectl


# --- HELM ---
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod +x get_helm.sh
./get_helm.sh


# --- TERRAFORM ---
VERSION=1.0.0
wget https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_linux_amd64.zip
unzip terraform_${VERSION}_linux_amd64.zip -d /usr/local/bin/


# --- Azure CLI ---
rpm --import https://packages.microsoft.com/keys/microsoft.asc
sh -c 'echo -e "[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/azure-cli.repo'
yum install azure-cli -y
#
az login --service-principal -u $ARM_CLIENT_ID -p $ARM_CLIENT_SECRET --tenant $ARM_TENANT_ID


# --------------------------------------------------------------
#    Terraform section
# --------------------------------------------------------------

cd kafka-aks/terraform
/usr/local/bin/terraform init

export TF_VAR_client_id=$ARM_CLIENT_ID
export TF_VAR_client_secret=$ARM_CLIENT_SECRET
/usr/local/bin/terraform plan >> /tmp/tf.plan.log

# --------------------------------------------------------------
#    clone Confluent repo with Kafka Operator
# --------------------------------------------------------------

mkdir operator
cd operator

# !!! - for demo purposes - clone to yor own GitHub account and modify the values.yaml file

wget https://platform-ops-bin.s3-us-west-1.amazonaws.com/operator/confluent-operator-1.5.0-for-confluent-platform-5.5.0.tar.gz
tar -xf confluent-operator-1.5.0-for-confluent-platform-5.5.0.tar.gz 

cp helm/providers/azure.yaml values.yaml

#export KUBECONFIG=../kubeconfig.txt
export VALUES_FILE=./values.yaml
