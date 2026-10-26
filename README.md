# File Drop on EKS

File Drop deployed on Amazon EKS (Auto Mode) with PostgreSQL on RDS, described with Terraform.

Tested end to end in the exercise account on 2026-10-25: `terraform apply`, deploy, the tests below, delete, `terraform destroy` with no resource left.

## Prerequisites

- AWS CLI v2, Terraform >= 1.11 (write-only arguments), Docker (with buildx), kubectl
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
| `cluster_endpoint_public_access_cidrs` | `["0.0.0.0/0"]`: who can reach the Kubernetes API, restrict it to your IP with `'["<ip>/32"]'` |

## 3. Build, push and deploy the application

```sh
./scripts/deploy.sh deploy v1.0.0
```

The tag is used for the image pushed to ECR and for the deployment. The script makes the cluster the current kubectl context and prints the application URL.

- **New version:** run it again with a new tag.
- **Existing tag:** the image is not rebuilt (ECR tags are immutable), so a code change needs a new tag.
- **Rollback:** deploy the previous tag.

## 4. Test

The load balancer DNS name can take a minute or two to resolve after the script ends.

```sh
URL=<url printed by deploy.sh>
curl -i $URL/readyz                    # 200 ok: database reachable, volume writable
echo hello > notes.txt
curl -F file=@notes.txt $URL/files     # returns the file id
curl $URL/files                        # lists uploaded files
curl -OJ $URL/files/<id>               # downloads notes.txt
curl -i $URL/files/unknown             # 404
```

## 5. Destroy

**`deploy.sh delete` must run before `terraform destroy`:** the load balancer is created by Auto Mode, not Terraform, and would block the VPC deletion. It also deletes the volume and the uploaded files.

```sh
./scripts/deploy.sh delete
cd infra && terraform destroy
```

## Run locally

```sh
docker compose up --build -d   # app on http://localhost:8080, same commands as above
docker compose down -v
```

## Design choices

- **EKS Auto Mode** ([infra/eks.tf](infra/eks.tf)): nodes, EBS driver and load balancer controller managed by AWS, nothing to install.
- **RDS** ([infra/rds.tf](infra/rds.tf)) rather than PostgreSQL in the cluster: managed backups and patching.
- **StatefulSet, one EBS volume, one replica** ([k8s/02-statefulset.yaml](k8s/02-statefulset.yaml)): `DATA_DIR` is a local disk and EBS is single-AZ. Downtime on rollout, no scaling.
- **Password out of the Terraform state** ([infra/rds.tf](infra/rds.tf)): ephemeral, write-only, stored in Secrets Manager, copied to a Kubernetes Secret by `deploy.sh`.
- **Terraform for AWS, kubectl for the cluster**: no `kubernetes`/`helm` provider, releases stay independent from infrastructure applies.
- **Flat YAML and a script**: one app, one environment, Helm would only template the image tag.
- **Image** ([Dockerfile](Dockerfile)): app unchanged, gunicorn with `--preload` (one `CREATE TABLE`), non-root, amd64.
- **Immutable ECR tags** ([infra/ecr.tf](infra/ecr.tf)): a tag is one image, rollback is a redeploy.
- **Local Terraform state**: single operator, no password in it.
- **Public ALB, no authentication**: required by the exercise, `inboundCIDRs` in [k8s/04-ingress.yaml](k8s/04-ingress.yaml) limits access.
- **Latest versions** (Kubernetes 1.37, PostgreSQL 18, Python 3.15): longest support window.

## Next steps

- **Monitoring and alerting.** CloudWatch alarms on PVC disk usage, ALB 5xx and latency, RDS CPU, connections and storage.
- **Log retention.** Only control plane logs are kept today: ship pod and ALB logs to a managed or self-hosted log service, with a retention period.
- **Backups and a tested restore.** One day of RDS backups, no EBS snapshot. Back up the database before the volume, then test a restore.
- **TLS and WAF on the ALB.** ACM certificate with HTTPS redirect, WAF rate and size limits.
- **Secret sync and rotation.** External Secrets Operator instead of `deploy.sh`, pod restart on change, RDS-managed rotation, a dedicated PostgreSQL user.
- **Reproducible builds.** Pin dependencies (pip constraints file) and the base image (digest).
- **High availability, application side.** Files in S3 instead of `DATA_DIR` (a migration), table creation out of startup.
- **High availability, infrastructure side.** Several replicas across AZs with a PodDisruptionBudget, RDS Multi-AZ, one NAT gateway per AZ.
- **Remote Terraform state.** S3 backend with locking.
- **CI/CD.** Image build and push on release through GitHub OIDC, with a blocking scan.
