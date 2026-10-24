#!/usr/bin/env bash
# Deploy File Drop on the cluster created by infra/, or remove it.
#
#   ./scripts/deploy.sh deploy v1.0.0   # builds and pushes the image as v1.0.0, then deploys it
#   ./scripts/deploy.sh delete          # run before terraform destroy
#
# Needs terraform, aws, docker and kubectl, and the Terraform state of infra/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAMESPACE=filedrop

tf_output() {
  terraform -chdir="$ROOT/infra" output -raw "$1"
}

use_cluster() {
  # Adds the cluster to ~/.kube/config and makes it the current kubectl context.
  aws eks update-kubeconfig --region "$(tf_output region)" --name "$(tf_output cluster_name)" >/dev/null
}

push_image() {
  local tag="$1" image="$2"
  # ECR tags are immutable: an existing tag is deployed as is, never rebuilt.
  if aws ecr describe-images --region "$(tf_output region)" \
    --repository-name "$(tf_output ecr_repository_name)" --image-ids "imageTag=$tag" >/dev/null 2>&1; then
    echo "Image $tag already in ECR, skipping the build."
    return
  fi
  aws ecr get-login-password --region "$(tf_output region)" |
    docker login --username AWS --password-stdin "${image%%/*}"
  # Nodes are amd64: build for that platform even from an arm64 machine.
  docker buildx build --platform linux/amd64 --tag "$image" --push "$ROOT"
}

sync_database_secret() {
  # Copies DATABASE_URL from Secrets Manager into the Kubernetes Secret the pod reads.
  # The value only travels through pipes: never a command-line argument or a file.
  # tr removes the newline the AWS CLI appends, which would end up in the URL.
  # "create --dry-run | apply" makes the command work whether the Secret exists or not.
  aws secretsmanager get-secret-value --region "$(tf_output region)" \
    --secret-id "$(tf_output database_url_secret_arn)" --query SecretString --output text |
    tr -d '\n' |
    kubectl create secret generic filedrop-db --namespace "$NAMESPACE" \
      --from-file=DATABASE_URL=/dev/stdin --dry-run=client --output yaml |
    kubectl apply -f -
}

apply_manifests() {
  local image="$1"
  # The image reference is the only account-specific value in the manifests.
  sed "s|IMAGE_PLACEHOLDER|$image|" "$ROOT"/k8s/*.yaml | kubectl apply -f -
}

wait_for_load_balancer() {
  local hostname
  for _ in $(seq 60); do
    hostname="$(kubectl get ingress filedrop --namespace "$NAMESPACE" \
      --output jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
    if [[ -n "$hostname" ]]; then
      echo "$hostname"
      return
    fi
    sleep 5
  done
  echo "The load balancer has no hostname after 5 minutes." >&2
  exit 1
}

deploy() {
  local tag="$1"
  local image
  image="$(tf_output ecr_repository_url):$tag"

  push_image "$tag" "$image"
  use_cluster
  kubectl apply -f "$ROOT/k8s/00-namespace.yaml" # the Secret needs its namespace
  sync_database_secret
  apply_manifests "$image"
  kubectl rollout status statefulset/filedrop --namespace "$NAMESPACE" --timeout=10m
  echo "Waiting for the load balancer..."
  echo "File Drop: http://$(wait_for_load_balancer)"
}

delete() {
  use_cluster
  # The ALB belongs to Auto Mode, not Terraform: delete the Ingress first so Auto Mode
  # removes it, otherwise terraform destroy cannot delete the VPC.
  kubectl delete ingress filedrop --namespace "$NAMESPACE" --ignore-not-found --wait
  # Also deletes the PersistentVolumeClaim, hence the EBS volume (reclaimPolicy: Delete).
  kubectl delete namespace "$NAMESPACE" --ignore-not-found --wait
  kubectl delete ingressclass alb --ignore-not-found
  kubectl delete ingressclassparams alb --ignore-not-found
  kubectl delete storageclass ebs-gp3 --ignore-not-found
}

usage() {
  echo "usage: $0 deploy <image-tag> | delete" >&2
  exit 1
}

case "${1:-}" in
  deploy)
    [[ -n "${2:-}" ]] || usage
    deploy "$2"
    ;;
  delete) delete ;;
  *) usage ;;
esac
