# File Drop on EKS

File Drop deployed on Amazon EKS (Auto Mode) with PostgreSQL on RDS, described with Terraform.

## Prerequisites

- AWS CLI v2, Terraform >= 1.11, Docker (with buildx), kubectl
- Credentials for the target AWS account

## 1. Select the AWS account

If several profiles exist on the machine, select the right one for the whole session, then check the account:

```sh
export AWS_PROFILE=<profile>
aws sts get-caller-identity
```

## 2. Create the infrastructure

```sh
cd infra
terraform init
terraform apply      # about 15 minutes
cd ..
```

Variables, all optional (`-var name=value`):

| Variable | Default |
|---|---|
| `name` | `filedrop` |
| `region` | `eu-west-3` |
| `vpc_cidr` | `10.0.0.0/16` |
| `cluster_endpoint_public_access_cidrs` | `["0.0.0.0/0"]` |

## 3. Build, push and deploy the application

```sh
./scripts/deploy.sh deploy v1.0.0
```

The tag is used for the image pushed to ECR and for the deployment. It prints the application URL.

## 4. Test

```sh
echo hello > notes.txt
curl -F file=@notes.txt http://<url>/files    # returns the file id
curl http://<url>/files                       # lists uploaded files
curl -OJ http://<url>/files/<id>              # downloads notes.txt
```

## 5. Destroy

```sh
./scripts/deploy.sh delete
cd infra && terraform destroy
```

## Run locally

```sh
docker compose up --build -d   # app on http://localhost:8080, same commands as above
docker compose down -v
```

## Next steps

- **Monitoring and alerting.** Nothing is monitored today. Alert (CloudWatch alarms, SNS) on PVC disk usage (a full volume blocks every upload), ALB 5xx and latency, RDS CPU, connections and free storage. The app exposes no metrics, so this relies on ALB, Kubernetes and RDS metrics.
- **Pod logs in CloudWatch.** Only the EKS control plane logs reach CloudWatch today; application logs are lost with the pod. Add the `amazon-cloudwatch-observability` add-on (EKS module `addons`, Pod Identity role), with log groups created by Terraform so they have a retention period and are removed by `terraform destroy`.
- **Backups and a tested restore.** RDS keeps one day of backups and the EBS volume has no snapshot. Back up the database before the volume: files are written before their row and never deleted, so every restored row has its file. Then test a restore.
- **TLS and WAF on the ALB.** The app is served over plain HTTP and uploads are public. Add an ACM certificate with HTTPS redirect, and WAF for rate and request size limits (network protection, not authentication).
- **Secret sync and rotation.** Replace the copy made by `deploy.sh` with External Secrets Operator, enable RDS-managed password rotation, and give the app its own PostgreSQL user instead of the master one.
- **High availability, application side.** Several replicas need shared file storage: store files in S3 instead of `DATA_DIR`, and move table creation out of startup so replicas do not race on it.
- **High availability, infrastructure side.** S3 bucket with Pod Identity access, several replicas spread across AZs with a PodDisruptionBudget, RDS Multi-AZ, one NAT gateway per AZ.
- **Remote Terraform state.** S3 backend with locking, needed as soon as two people apply.
- **CI/CD.** Build and push the image on each release through GitHub OIDC, with a blocking image scan, instead of `deploy.sh` from a workstation.
