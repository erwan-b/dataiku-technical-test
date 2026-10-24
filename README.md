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

- **Pod logs in CloudWatch.** Only the EKS control plane logs reach CloudWatch today; application logs are lost with the pod. Add the `amazon-cloudwatch-observability` add-on (EKS module `addons`, Pod Identity role), with log groups created by Terraform so they have a retention period and are removed by `terraform destroy`.
