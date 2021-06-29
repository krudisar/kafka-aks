# --------------------------------------------------------------
#    Notification functions (text & content of a text file
# --------------------------------------------------------------

function notify_message(){
  # Post simple notification to Microsoft Teams.
  TITLE=$1
  TEXT=$2
  COLOR=\$006600
  MESSAGE=$( echo ${TEXT} | sed 's/"/\"/g' | sed "s/'/\'/g" )
  JSON="{\"title\": \"${TITLE}\", \"themeColor\": \"${COLOR}\", \"text\": \"<b><pre>${MESSAGE}</pre></b>\" }"
  curl -H "Content-Type: application/json" -d "${JSON}" ${MSTEAMS_WEBHOOK}
}

function notify_file(){
  # Post content of a text file to Microsoft Teams.
  TITLE=$1
  COLOR=\$006600
  MESSAGE=$( cat $2 | sed 's/"/\"/g' | sed "s/'/\'/g" )
  JSON="{\"title\": \"${TITLE}\", \"themeColor\": \"${COLOR}\", \"text\": \"<b><pre>${MESSAGE}</pre></b>\" }"
  curl -H "Content-Type: application/json" -d "${JSON}" ${MSTEAMS_WEBHOOK}
}

# --------------------------------------------------------------
#    install required packages
# --------------------------------------------------------------

notify_message "Kafka environment provisioning in progress ..." "Installing software dependencies and tools ..."

yum install git jq unzip -y
export PATH="/usr/local/bin:$PATH"

# --- YQ ---
wget https://github.com/mikefarah/yq/releases/download/v4.9.6/yq_linux_amd64
mv yq_linux_amd64 /usr/local/bin/yq
chmod +x /usr/local/bin/yq

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

# --- Apache Maven ---
yum -y install maven

# --------------------------------------------------------------
#    Terraform section
# --------------------------------------------------------------

notify_message "Kafka environment provisioning in progress ..." "Going to set up an AKS cluster with 4 worker nodes ..."

cd kafka-aks/terraform
/usr/local/bin/terraform init

export TF_VAR_client_id=$ARM_CLIENT_ID
export TF_VAR_client_secret=$ARM_CLIENT_SECRET
/usr/local/bin/terraform plan >> /tmp/tf.plan.log
/usr/local/bin/terraform apply -auto-approve >> /tmp/tf.apply.log

# --------------------------------------------------------------
#    get kubeconfig file content from TF output variable 
#    and save it to kubeconfig.txt file
# --------------------------------------------------------------

# !!! use -row switch to ensure the file is properly formatted !!!
terraform output -raw kube_config | tee > /tmp/kubeconfig.txt

# --------------------------------------------------------------
#    clone Confluent repo with Kafka Operator
# --------------------------------------------------------------

notify_message "Kafka environment provisioning in progress ..." "Going to clone Confluent Kafka Operator repository ..."

mkdir ../../operator 
cd ../../operator

wget https://platform-ops-bin.s3-us-west-1.amazonaws.com/operator/confluent-operator-1.5.0-for-confluent-platform-5.5.0.tar.gz
tar -xf confluent-operator-1.5.0-for-confluent-platform-5.5.0.tar.gz 

cp helm/providers/azure.yaml values.yaml

export KUBECONFIG=/tmp/kubeconfig.txt
export VALUES_FILE=./values.yaml

kubectl get nodes --kubeconfig=$KUBECONFIG >> /tmp/kubectl.get.nodes.log

# --------------------------------------------------------------
#    deploy Confluent Kafka Operator Kubernetes custom resources
# --------------------------------------------------------------
kubectl apply -f resources/crds --kubeconfig=$KUBECONFIG
kubectl apply -f resources/rbac --kubeconfig=$KUBECONFIG

# --------------------------------------------------------------
#    create 'operator' Kubernetes namespace 
# --------------------------------------------------------------
kubectl create ns operator --kubeconfig=$KUBECONFIG
export NAMESPACE=operator

# --------------------------------------------------------------
#    adjust values.yaml file based on inputs 
# --------------------------------------------------------------

notify_message "Kafka environment provisioning in progress ..." "Modifying values.yaml to deploy customized Kafka platform ..."

yq eval '.global.sasl.plain.username = env(INPUT_USER_NAME)' -i values.yaml
yq eval '.global.sasl.plain.password = env(INPUT_USER_PASSWORD)' -i values.yaml

yq eval '.global.authorization.rbac.enabled = false' -i values.yaml
yq eval '.global.authorization.simple.enabled = false' -i values.yaml

yq eval '.kafka.replicas = env(INPUT_KAFKA_NODES)' -i values.yaml
yq eval '.zookeeper.replicas = 1' -i values.yaml
yq eval '.connect.replicas = 1' -i values.yaml
yq eval '.replicator.replicas = 1' -i values.yaml
yq eval '.ksql.replicas = 1' -i values.yaml

yq eval '.kafka.loadBalancer.enabled = true' -i values.yaml
yq eval '.kafka.loadBalancer.domain = "krdemo.net"' -i values.yaml

yq eval '.controlcenter.loadBalancer.enabled = true' -i values.yaml
yq eval '.controlcenter.loadBalancer.domain = "krdemo.net"' -i values.yaml
yq eval '.controlcenter.auth.basic.enabled = false' -i values.yaml

yq eval '.controlcenter.dependencies.c3KafkaCluster.brokerCount = env(INPUT_KAFKA_NODES)' -i values.yaml
yq eval '.controlcenter.dependencies.connectCluster.enabled = false' -i values.yaml
yq eval '.controlcenter.dependencies.ksql.enabled = false' -i values.yaml
yq eval '.controlcenter.dependencies.schemaRegistry.enabled = false' -i values.yaml

# --------------------------------------------------------------
#    deploy Confluent Kafka Operator Services - one by one 
#     - operator itself
#     - Zookeeper Service
#     - Kafka Service - exposed as 'LoadBalancer' type  
#     - ControlCenter Service - exposed as 'LoadBalancer' type  
# 
# --------------------------------------------------------------

notify_message "Kafka environment provisioning in progress ..." "Installing Apache Kafka platform on AKS cluster ..."

# ---> Operator pod(s)
helm upgrade --install   operator   ./helm/confluent-operator   --values $VALUES_FILE   --namespace $NAMESPACE   --set operator.enabled=true
sleep 30

# ---> Zookeeper pod(s)
helm upgrade --install   zookeeper   ./helm/confluent-operator   --values $VALUES_FILE   --namespace $NAMESPACE   --set zookeeper.enabled=true
sleep 60

# ---> Kafka pod(s)
helm upgrade --install   kafka   ./helm/confluent-operator   --values $VALUES_FILE   --namespace $NAMESPACE   --set kafka.enabled=true
sleep 120

# ---> ControlCenter pod(s)
helm upgrade --install   controlcenter   ./helm/confluent-operator   --values $VALUES_FILE   --namespace $NAMESPACE   --set controlcenter.enabled=true
sleep 240 #(... wait for EXTERNAL-IP for LoadBalancer services)

# (check pod creation process using ...)
kubectl get pods --kubeconfig=$KUBECONFIG -n $NAMESPACE >> /tmp/kubectl.get.pods.operator.log
kubectl get svc --kubeconfig=$KUBECONFIG -n $NAMESPACE >> /tmp/kubectl.get.svc.operator.log

# --------------------------------------------------------------
#    parse external IPs and create corresponding DNS records 
# --------------------------------------------------------------

notify_message "Kafka environment provisioning in progress ..." "Getting external IP addresses of exposed Kubernetes services & preparing DNS records ..."

if [ $INPUT_KAFKA_NODES -eq 1 ]; then  
  echo "### DNS records for single node Kafka environment"; 

  export KAFKA_0_LB_IP=$(kubectl get svc kafka-0-lb --kubeconfig=$KUBECONFIG -n $NAMESPACE -o json | jq ".status.loadBalancer.ingress[0].ip" | tr -d '"')
  export KAFKA_0_LB_DNS=$(kubectl get svc kafka-0-lb --kubeconfig=$KUBECONFIG -n $NAMESPACE -o json | jq ".metadata.annotations.\"external-dns.alpha.kubernetes.io/hostname\"" | tr -d '"')

  export KAFKA_BOOTSTRAP_LB_IP=$(kubectl get svc kafka-bootstrap-lb --kubeconfig=$KUBECONFIG -n $NAMESPACE -o json | jq ".status.loadBalancer.ingress[0].ip" | tr -d '"')
  export KAFKA_BOOTSTRAP_LB_DNS=$(kubectl get svc kafka-bootstrap-lb --kubeconfig=$KUBECONFIG -n $NAMESPACE -o json | jq ".metadata.annotations.\"external-dns.alpha.kubernetes.io/hostname\"" | tr -d '"')

  export CC_BOOTSTRAP_LB_IP=$(kubectl get svc controlcenter-bootstrap-lb --kubeconfig=$KUBECONFIG -n $NAMESPACE -o json | jq ".status.loadBalancer.ingress[0].ip" | tr -d '"')
  export CC_BOOTSTRAP_LB_DNS=$(kubectl get svc controlcenter-bootstrap-lb --kubeconfig=$KUBECONFIG -n $NAMESPACE -o json | jq ".metadata.annotations.\"external-dns.alpha.kubernetes.io/hostname\"" | tr -d '"')

  echo -e $KAFKA_0_LB_IP "\t" $KAFKA_0_LB_DNS >> /tmp/DNS.TXT
  echo -e $KAFKA_BOOTSTRAP_LB_IP "\t" $KAFKA_BOOTSTRAP_LB_DNS >> /tmp/DNS.TXT
  echo -e $CC_BOOTSTRAP_LB_IP "\t" $CC_BOOTSTRAP_LB_DNS >> /tmp/DNS.TXT
fi

if [ $INPUT_KAFKA_NODES -eq 2 ]; then  
  echo "### DNS records for double node Kafka environment"; 

  export KAFKA_0_LB_IP=$(kubectl get svc kafka-0-lb --kubeconfig=$KUBECONFIG -n $NAMESPACE -o json | jq ".status.loadBalancer.ingress[0].ip" | tr -d '"')
  export KAFKA_0_LB_DNS=$(kubectl get svc kafka-0-lb --kubeconfig=$KUBECONFIG -n $NAMESPACE -o json | jq ".metadata.annotations.\"external-dns.alpha.kubernetes.io/hostname\"" | tr -d '"')

  export KAFKA_1_LB_IP=$(kubectl get svc kafka-1-lb --kubeconfig=$KUBECONFIG -n $NAMESPACE -o json | jq ".status.loadBalancer.ingress[0].ip" | tr -d '"')
  export KAFKA_1_LB_DNS=$(kubectl get svc kafka-1-lb --kubeconfig=$KUBECONFIG -n $NAMESPACE -o json | jq ".metadata.annotations.\"external-dns.alpha.kubernetes.io/hostname\"" | tr -d '"')

  export KAFKA_BOOTSTRAP_LB_IP=$(kubectl get svc kafka-bootstrap-lb --kubeconfig=$KUBECONFIG -n $NAMESPACE -o json | jq ".status.loadBalancer.ingress[0].ip" | tr -d '"')
  export KAFKA_BOOTSTRAP_LB_DNS=$(kubectl get svc kafka-bootstrap-lb --kubeconfig=$KUBECONFIG -n $NAMESPACE -o json | jq ".metadata.annotations.\"external-dns.alpha.kubernetes.io/hostname\"" | tr -d '"')

  export CC_BOOTSTRAP_LB_IP=$(kubectl get svc controlcenter-bootstrap-lb --kubeconfig=$KUBECONFIG -n $NAMESPACE -o json | jq ".status.loadBalancer.ingress[0].ip" | tr -d '"')
  export CC_BOOTSTRAP_LB_DNS=$(kubectl get svc controlcenter-bootstrap-lb --kubeconfig=$KUBECONFIG -n $NAMESPACE -o json | jq ".metadata.annotations.\"external-dns.alpha.kubernetes.io/hostname\"" | tr -d '"')

  echo -e $KAFKA_0_LB_IP "\t" $KAFKA_0_LB_DNS >> /tmp/DNS.TXT
  echo -e $KAFKA_1_LB_IP "\t" $KAFKA_1_LB_DNS >> /tmp/DNS.TXT
  echo -e $KAFKA_BOOTSTRAP_LB_IP "\t" $KAFKA_BOOTSTRAP_LB_DNS >> /tmp/DNS.TXT
  echo -e $CC_BOOTSTRAP_LB_IP "\t" $CC_BOOTSTRAP_LB_DNS >> /tmp/DNS.TXT
fi


# --------------------------------------------------------------
#    Final notifications 
# --------------------------------------------------------------

notify_message "The provisioning process completed !!!" "Kafka environment provisioning finished. Please see DNS records below ..."
#
notify_file "Add these DNS records into your DNS zone or hosts file to access your Kafka environment ..." "/tmp/DNS.TXT"

# DONE!
