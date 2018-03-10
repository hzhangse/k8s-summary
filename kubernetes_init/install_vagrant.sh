#!/bin/bash

# KUBE_REPO_PREFIX=registry.cn-hangzhou.aliyuncs.com/google-containers
# KUBE_HYPERKUBE_IMAGE=registry.cn-hangzhou.aliyuncs.com/google-containers/hyperkube-amd64:v1.7.0
# KUBE_DISCOVERY_IMAGE=registry.cn-hangzhou.aliyuncs.com/google-containers/kube-discovery-amd64:1.0
# KUBE_ETCD_IMAGE=registry.cn-hangzhou.aliyuncs.com/google-containers/etcd-amd64:3.0.17

# KUBE_REPO_PREFIX=$KUBE_REPO_PREFIX KUBE_HYPERKUBE_IMAGE=$KUBE_HYPERKUBE_IMAGE KUBE_DISCOVERY_IMAGE=$KUBE_DISCOVERY_IMAGE kubeadm init --ignore-preflight-errors=all --pod-network-cidr="10.244.0.0/16"

set -x

USER=vagrant # 用户
GROUP=vagrant # 组
FLANELADDR=https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml
KUBECONF=/home/vagrant/k8s-master/kubernetes_init/kubeadm.conf # 文件地址, 改成你需要的路径
REGMIRROR=https://hn7abopz.mirror.aliyuncs.com # docker registry mirror 地址

# you can get the following values from `kubeadm init` output
# these are needed when creating node
MASTERTOKEN=d8ff99.db26b6b33002396d
MASTERIP=192.169.0.8
MASTERPORT=6443
MASTERHASH=4e98b28476b7e5671dc8db45217829a8d8c6f66802ee20124edc6d8c3f028ff9

install_docker() {
  apt-get update
  apt-get install -y apt-transport-https ca-certificates curl software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository \
    "deb [arch=amd64] https://mirrors.ustc.edu.cn/docker-ce/linux/$(. /etc/os-release; echo "$ID") \
    $(lsb_release -cs) \
    stable"
  apt-get update && apt-get install -y docker-ce=$(apt-cache madison docker-ce | grep 17.09 | head -1 | awk '{print $3}')
sudo mkdir -p /etc/docker
mkdir -p /data/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["$REGMIRROR"],
  "graph": "/data/docker"
}
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker
}

add_user_to_docker_group() {
  groupadd docker
  gpasswd -a $USER docker # ubuntu is the user name
}

install_kube_commands() {
  cat kube_apt_key.gpg | apt-key add -
  echo "deb [arch=amd64] https://mirrors.ustc.edu.cn/kubernetes/apt kubernetes-$(lsb_release -cs) main" >> /etc/apt/sources.list
  apt-get update && apt-get install -y kubelet kubeadm kubectl
}

restart_kubelet() {
  sed -i "s,ExecStart=$,Environment=\"KUBELET_EXTRA_ARGS=--pod-infra-container-image=registry.cn-hangzhou.aliyuncs.com/google_containers/pause-amd64:3.1\"\nExecStart=,g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
  systemctl daemon-reload
  systemctl restart kubelet
}

enable_kubectl() {
  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config
}

# for now, better to download from original registry
apply_flannel() {
  kubectl apply -f $FLANELADDR
}

case "$1" in
  "pre")
    install_docker
    add_user_to_docker_group
    install_kube_commands
    ;;
  "kubernetes-master")
    sysctl net.bridge.bridge-nf-call-iptables=1
    restart_kubelet
    kubeadm init --config $KUBECONF 
    ;;
  "restart-master")
    sysctl net.bridge.bridge-nf-call-iptables=1
    restart_kubelet
    ;;
  "kubernetes-node")
    sysctl net.bridge.bridge-nf-call-iptables=1
    restart_kubelet
    kubeadm join --token $MASTERTOKEN $MASTERIP:$MASTERPORT --discovery-token-ca-cert-hash sha256:$MASTERHASH
    ;;
  "post")
    if [[ $EUID -ne 0 ]]; then
      echo "do not run as root"
      exit
    fi
    enable_kubectl
    apply_flannel
    ;;
  *)
    echo "huh ????"
    ;;
esac
