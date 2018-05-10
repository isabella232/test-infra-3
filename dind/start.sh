#!/bin/bash

# Copyright 2017 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

wait_for_docker ()
{
  # Wait for docker.
  until docker version; do sleep 1 ;done
}

start_kubelet ()
{
  # Start the kubelet.
  mkdir -p /etc/kubernetes/manifests
  mkdir -p /etc/srv/kubernetes
  mount --make-rshared /etc/kubernetes

  # Change the kubelet to not fail with swap on.
  cat > /etc/systemd/system/kubelet.service.d/kubeadm-20.conf << EOM
[Service]
Environment="KUBELET_EXTRA_ARGS=--fail-swap-on=false"
EOM
  systemctl enable kubelet
  systemctl start kubelet
}

start_worker ()
{
  wait_for_docker
  start_kubelet

  # Load docker images
  docker load -i /kube-proxy.tar

  # Kubeadm expects kube-proxy-amd64, but bazel names it kube-proxy
  docker tag k8s.gcr.io/kube-proxy:v$(cat /kube_version) k8s.gcr.io/kube-proxy-amd64:v$(cat /kube_version)

  # Start kubeadm.
  /usr/bin/kubeadm join --token=abcdef.abcdefghijklmnop --discovery-token-unsafe-skip-ca-verification=true --ignore-preflight-errors=all 10.14.0.20:6443 2>&1
}

start_master ()
{
  wait_for_docker
  start_kubelet

  # Load the docker images
  docker load -i /kube-apiserver.tar
  docker load -i /kube-controller-manager.tar
  docker load -i /kube-proxy.tar
  docker load -i /kube-scheduler.tar
  # kubeadm expects all image names to be tagged as amd64, but bazel doesn't
  # build with that suffix yet.
  docker tag k8s.gcr.io/kube-apiserver:v$(cat /kube_version) k8s.gcr.io/kube-apiserver-amd64:v$(cat /kube_version)
  docker tag k8s.gcr.io/kube-controller-manager:v$(cat /kube_version) k8s.gcr.io/kube-controller-manager-amd64:v$(cat /kube_version)
  docker tag k8s.gcr.io/kube-proxy:v$(cat /kube_version) k8s.gcr.io/kube-proxy-amd64:v$(cat /kube_version)
  docker tag k8s.gcr.io/kube-scheduler:v$(cat /kube_version) k8s.gcr.io/kube-scheduler-amd64:v$(cat /kube_version)

  # Run kubeadm init to config a master.
  /usr/bin/kubeadm init --token=abcdef.abcdefghijklmnop --ignore-preflight-errors=all --kubernetes-version=$(cat kube_version) --service-cidr=10.80.0.0/12 --pod-network-cidr=192.168.0.0/16 --apiserver-cert-extra-sans $1 2>&1

  # We'll want to read the kube-config from outside the container, so open read
  # permissions on admin.conf.
  chmod a+r /etc/kubernetes/admin.conf

  # We need to prevent kube-config from trying to set conntrack values.
  kubectl --kubeconfig=/etc/kubernetes/admin.conf get ds -n kube-system kube-proxy -o json | jq '.spec.template.spec.containers[0].command |= .+ ["--conntrack-max-per-core=0"]' | kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f -
  # Apply a pod network.
  # Calico is an ip-over-ip overlay network. This saves us from many of the
  # difficulties from configuring an L2 network.
  kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f https://gist.githubusercontent.com/munnerz/a7bfd9126fff558f5c373d95bfc81cd4/raw/3aca70acb90954d9b55395f567be26ffa7127126/calico-dind.yaml

  # Install the metrics server, and the HPA.
  kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f /addons/metrics-server/
}

start_cluster ()
{
  wait_for_docker

  # Create a mount point for kubernetes credentials.
  mkdir -p /var/kubernetes

  # Start some workers.
  echo "Creating testnet"
  docker network create --subnet=10.14.0.0/24 testnet
  docker network ls
  echo "Creating virtual nodes"
  docker load -i /dind-node-bundle.tar
  docker run -d --privileged --net testnet --ip 10.14.0.20 -p 443:6443 -v /var/kubernetes:/etc/kubernetes -v /lib/modules:/lib/modules eu.gcr.io/jetstack-build-infra/dind-node-amd64:1.10.2 master $(hostname --ip-address)
  docker run -d --privileged --net testnet --ip 10.14.0.21 -v /lib/modules:/lib/modules eu.gcr.io/jetstack-build-infra/dind-node-amd64:1.10.2 worker
  docker run -d --privileged --net testnet --ip 10.14.0.22 -v /lib/modules:/lib/modules eu.gcr.io/jetstack-build-infra/dind-node-amd64:1.10.2 worker
  docker run -d --privileged --net testnet --ip 10.14.0.23 -v /lib/modules:/lib/modules eu.gcr.io/jetstack-build-infra/dind-node-amd64:1.10.2 worker
}

# kube-proxy attempts to write some values into sysfs for performance. But these
# values cannot be written outside of the original netns, even if the fs is rw.
# This causes kube-proxy to panic if run inside dind.
#
# Historically, --max-conntrack or --conntrack-max-per-core could be set to 0,
# and kube-proxy would skip the write (#25543). kube-proxy no longer respects
# the CLI arguments if a config file is present.
#
# Instead, we can make sysfs ro, so that kube-proxy will forego write attempts.
mount -o remount,ro /sys

# Start docker.
mount --make-rshared /lib/modules/

# Make everything rshared. This is necessary to correctly propagate arbitrary
# host mounts. Leave the other rshared commands, because we shouldn't propagate
# arbitrary host mounts.
mount --make-rshared /
/bin/dockerd-entrypoint.sh &

# Start a new process to do work.
if [[ $1 == "worker" ]] ; then
  start_worker
elif [[ $1 == "master" ]] ; then
  start_master $2
else
  start_cluster
fi

