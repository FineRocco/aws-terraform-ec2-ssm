# Cloud-Native Web & Database Stack

An immutable, fully automated DevSecOps cloud infrastructure project. This repository provisions a secure, two-tier AWS network topology, deploys a containerized Python/Flask application, attaches a zero-trust encrypted PostgreSQL database, and orchestrates zero-touch, push-based CI/CD deployments via AWS Systems Manager (SSM)—all authenticated seamlessly via OpenID Connect (OIDC).

---

## The Tech Stack

This project integrates five distinct technology layers to create a highly efficient, automated security gate pipeline:

* **Infrastructure as Code (IaC):** Terraform (State managed via AWS S3 Backend)
* **Cloud Provider (AWS):** VPC, EC2, RDS PostgreSQL, ECR, S3, Secrets Manager, SSM, IAM (OIDC)
* **CI/CD Orchestration:** GitHub Actions
* **Containerization:** Docker
* **Application Layer:** Python 3.11, Flask, psycopg2-binary, Bash (Lifecycle Scripts)

---

## System Architecture

This architecture relies on a highly secure "Push-based" deployment lifecycle using AWS Systems Manager (SSM). Rather than exposing SSH ports or managing complex CodeDeploy agents with S3 artifact buckets, the CI/CD pipeline uses AWS SSM to securely tunnel execution commands directly into the EC2 instance boundary.

```text
                              [ Public Internet ]
                                     │ (HTTP :80)
                                     ▼
                            ┌───────────────────┐
                            │   AWS Internet GW │
                            └─────────┬─────────┘
                                      │
                ┌─────────────────────┴─────────────────────┐
                │                   AWS VPC                 │
                │                                           │
                │  ┌─────────────────────────────────────┐  │
                │  │ Public Subnet (DMZ)                 │  │
                │  │                                     │  │
                │  │   ┌─────────────────────────────┐   │  │ (4) SSM Run Command
                │  │   │       EC2 Web Server        │◄──┼──┼─────┐ Pushes Bash
                │  │   │   (SSM Agent / Docker)      │   │  │     │ instructions
                │  │   └───────┬─────────────┬───────┘   │  │     │ directly to EC2
                │  └───────────┼─────────────┼───────────┘  │     │
                │              │(TCP :5432)  │ (HTTPS)      │     │
                │  ┌───────────▼─────────────▼───────────┐  │     │
                │  │ Private Subnets (Multi-AZ Isolated) │  │     │
                │  │                                     │  │     │
                │  │   ┌───────────────┐ ┌───────────┐   │  │     │
                │  │   │    AWS RDS    │ │AWS Secrets│◄──┼──┼─(5) EC2 fetches DB
                │  │   │ PostgreSQL DB │ │  Manager  │   │  │     password into memory
                │  │   └───────────────┘ └───────────┘   │  │     at container runtime
                │  └─────────────────────────────────────┘  │     │
                └───────────────────────────────────────────┘     │
                                                                  │
=========================== CI/CD CONTROL PLANE ==================│========
                                                                  │
      ┌────────────────┐ (1) OIDC Auth  ┌───────────────┐         │
      │ GitHub Actions ├───────────────►│ AWS IAM Role  │         │
      └──────┬─────────┘                └───────────────┘         │
             │                                                    │
             ├─────────────────► [ AWS ECR ] (2) Push Docker Image│
             │                                                    │
             └─────────────────► [ AWS SSM ] (3) Triggers script ─┘

```

---

## Network Topology & Routing

This architecture employs a strict two-tier Virtual Private Cloud (VPC) design, separating publicly accessible compute resources from highly sensitive backend data stores.

* **Internet Gateway (IGW):** The foundational ingress/egress anchor attached to the edge of the VPC. It translates internal private IP addresses to public routable addresses, acting as the sole bridge between the AWS network and the public internet.
* **Public Subnet (DMZ):** Houses the EC2 Web Server. 
  * **Routing:** Governed by a Public Route Table that directs all outbound intern traffic (et`0.0.0.0/0`) directly to the Internet Gateway.
  * **Access:** Equipped with a public IP to serve HTTP traffic directly to external users.
* **Private Subnets (x2):** Houses the AWS RDS PostgreSQL instance. Spans two distinct Availability Zones (`eu-west-1a`, `eu-west-1b`) to satisfy AWS physical failover mandates.

**This architecture intentionally omits a NAT Gateway.** Because AWS fully manages the underlying operating system and patching of the RDS PostgreSQL instance, the database never needs to initiate outbound internet requests. Furthermore, the EC2 instance pulling Docker images resides in the Public Subnet. Omitting the NAT Gateway eliminates a baseline cost.

### The Dual-Layer Firewall (Zero-Trust)

AWS network security is enforced at two distinct layers: the subnet boundary (stateless) and the instance boundary (stateful).

#### 1. Subnet-Level: Network Access Control Lists (NACLs)
NACLs act as the outermost perimeter fence. In this architecture, they operate in their default state (Allow All Inbound/Outbound), relying on the more granular Security Groups for filtering. However, they remain available as an incident response mechanism to instantly blacklist malicious CIDR blocks at the network edge during a DDoS attack.

#### 2. Instance-Level: Security Groups (SGs)
Security groups act as stateful, micro-segmented firewalls attached directly to the network interfaces of the resources. 
* **`web_sg` (The Front Door):** Attached to the EC2 instance. Explicitly allows Inbound `TCP 80` (HTTP) from `0.0.0.0/0`. **Strictly denies Port 22 (SSH)** to completely eliminate brute-force vector attacks.
* **`db_sg` (The Vault Door):** Attached to the RDS instance. Employs a zero-trust ingress rule that allows `TCP 5432` (PostgreSQL) *only* if the traffic originates from the `web_sg` security group. It rejects all other internal VPC traffic by default.

---

## Terraform State Management & Concurrency Control

In a production-grade CI/CD environment, infrastructure state cannot reside locally or ephemerally on a GitHub runner. It must be centralized, encrypted, and strictly protected against concurrent execution. 

### The Remote Backend Bootstrap
* **AWS S3 (State Storage):** The `terraform.tfstate` file is stored in a heavily restricted, versioned, and encrypted S3 bucket. This acts as the absolute single source of truth for the environment's configuration.
* **Amazon DynamoDB (State Locking):** To prevent race conditions—where two developers push to `main` simultaneously and trigger parallel GitHub Actions runners—a DynamoDB table is utilized for state locking. When a pipeline initiates `terraform plan` or `apply`, it requests a lock in DynamoDB. Any concurrent pipeline runs will be rejected until the lock is released, completely eliminating the risk of state corruption.

---

## Key DevSecOps & OPSEC Principles

1. **Zero-Knowledge Secret Injection:** The PostgreSQL master password is dynamically generated at high entropy via Terraform (`random_password`) and injected directly into **AWS Secrets Manager**. GitHub Actions never reads, caches, or echoes this password. During the SSM deployment phase, the EC2 instance uses its attached IAM Instance Profile to cryptographically pull the secret from the vault and parse it directly into container memory via `jq`.
2. **Keyless CI/CD Authentication:** GitHub Actions authenticates against AWS utilizing **OpenID Connect (OIDC)**. Long-lived, static `AWS_ACCESS_KEY_ID` secrets do not exist anywhere in this project's repositories or environments.
3. **Bastionless Remote Access:** Because SSH Port 22 is explicitly disabled at the Security Group level, all debugging and administrative shell access is tunneled securely through **AWS Systems Manager (SSM) Session Manager**. This completely eliminates internet-facing SSH brute-force attack vectors.
4. **Idempotent Lifecycle Rollouts:** Deployments do not require server teardowns or mutable infrastructure drift. Instead of relying on S3 artifact buckets or heavy deployment agents, GitHub Actions securely triggers an **AWS SSM Run Command**. The SSM agent natively executes the rollout instructions on the host to authenticate with ECR, pull the latest image, gracefully stop legacy containers, and spin up newly compiled containers.
---

## Automated CI/CD Lifecycle

When a developer merges code into the `main` branch, `.github/workflows/main-apply.yml` triggers a deterministic, zero-touch deployment pipeline. The lifecycle is strictly divided between GitHub Actions (Push) and the AWS CodeDeploy Agent (Pull).

### Phase 1: Continuous Integration & Infrastructure (GitHub Actions)
1. **OIDC Authentication:** The runner securely assumes the `GitHubActionsRole` in AWS via OpenID Connect.
2. **Infrastructure IaC Gate:** Terraform initializes the remote backend (utilizing native S3 state locking, eliminating the need for legacy DynamoDB tables) and applies infrastructure changes (`-auto-approve`).
3. **Variable Extraction:** The pipeline uses `terraform output -raw` to dynamically scrape the newly generated EC2 Instance ID, RDS Endpoint, and ECR Repository URL directly from the active state file.
4. **Artifact Compilation:** The lightweight Python/Flask Docker image is built, tagged, and pushed to Amazon ECR.
5. **SSM Execution Trigger:** Instead of zipping artifacts or relying on deployment agents to pull data, GitHub Actions packages the deployment instructions and dynamic variables into a strictly formatted JSON payload, pushing the command directly to the EC2 instance via `aws ssm send-command`.

### Phase 2: Continuous Deployment & Rollout (AWS Systems Manager)
Once triggered, the SSM Agent running securely inside the EC2 DMZ executes the `AWS-RunShellScript` payload. This guarantees an idempotent, highly secure deployment lifecycle:

1. **Authentication:** Uses the EC2 IAM Instance Profile to seamlessly authenticate the local Docker daemon against AWS ECR.
2. **Artifact Retrieval:** Pulls the newly compiled application container image directly from the private ECR registry.
3. **Zero-Knowledge Extraction:** Quietly queries AWS Secrets Manager, utilizing `jq` to parse the raw JSON payload and extract the master database password directly into server memory, never writing it to a log or a local `.env` file.
4. **Idempotent Reset:** Gracefully stops and removes the legacy `flask-app` container if it exists, ensuring a clean deployment slate.
5. **Container Boot:** Spins up the new Docker container bound to port `80:80`, injecting the database credentials and endpoints securely via runtime environment variables (`-e`).
6. **Database Seeding:** Pauses for container socket binding, then natively executes `seed_db.py` inside the live container to initialize the PostgreSQL schema and seed the application data.
  
---
  
## Repository Structure

This repository strictly separates Application Code, Deployment Lifecycle Scripts, and Infrastructure as Code (IaC) to ensure a clean separation of concerns.

```text
.
├── .github/
│   └── workflows/
│       ├── main-apply.yml          # Continuous Deployment pipeline
│       └── pr-plan.yml             # CI/CD security gate: Terraform plan & PR validation
├── app/
│   ├── app.py                      # Flask web application & RDS Read route
│   ├── seed_db.py                  # Auto-seeder with cryptographic password generation
│   ├── Dockerfile                  # Python 3.11 slim container build instructions
│   └── requirements.txt            # Python dependencies (Flask, psycopg2-binary)
├── env/
│   ├── dev/
│   │   ├── main.tf                 # Root module instantiation for the Development environment
│   │   ├── provider.tf             # AWS provider declaration and region config
│   │   ├── outputs.tf              # Catches module outputs for GitHub Actions extraction
│   │   ├── backend.tf              # S3 remote state and DynamoDB locking configuration
│   │   ├── terraform.tfvars        # Environment-specific values
│   │   └── variables.tf            # Input variable definitions and expected data types
│   └── prod/
│       ├── main.tf                 # Root module instantiation for the Production environment
│       ├── provider.tf             # AWS provider declaration and region config
│       ├── outputs.tf              # Catches module outputs for GitHub Actions extraction
│       ├── backend.tf              # S3 remote state and DynamoDB locking configuration
│       ├── terraform.tfvars        # Production-grade values
│       └── variables.tf            # Input variable definitions and expected data types
├── modules/
│   └── web_database_stack/
│       ├── network.tf              # VPC, DMZ Subnets, Private Subnets, Route Tables
│       ├── main.tf                 # Core infra (EC2, RDS, ECR, Secrets)
│       ├── security.tf             # IAM Roles, Policies, Instance Profiles
│       ├── variables.tf            # Dynamic module input variables
│       └── outputs.tf              # Module attribute pitchers to pass data upstream
├── tf-boostrap-backend/
│   └── main.tf                     # OIDC Identity Provider & GitHub Actions IAM Role setup
├── .gitignore                      # Ignores local .terraform directories and .env files
└── README.md                       # Master architecture document and efficiency assessment

```

---

## Challenges & Architectural Pivots

Building a fully automated DevSecOps pipeline from scratch presented several real-world cloud engineering challenges. Documenting these roadblocks highlights the resilience and adaptability of the final architecture.

### 1. AWS Free Tier & The CodeDeploy Restriction
* **The Blocker:** During the final stages of the CI/CD pipeline rollout, Terraform successfully built the infrastructure, but the pipeline crashed with a `SubscriptionRequiredException` when attempting to provision AWS CodeDeploy.
* **The Cause:** Newly created AWS Free Tier accounts (and academic sandbox environments) often place hard restrictions on peripheral deployment services like CodeDeploy until the account undergoes background verification to prevent abuse. 
* **The Pivot (SSM Run Command):** Rather than wait for account verification, the architecture was pivoted from a "Pull" deployment model (CodeDeploy + S3 Artifacts) to a strictly secure "Push" model using **AWS Systems Manager (SSM)**. This completely eliminated the need for S3 artifact storage and CodeDeploy agents. Instead, GitHub Actions uses the OIDC bridge to trigger an SSM Run Command, injecting the zero-knowledge database credentials and booting the Docker container natively. This resulted in a lighter, faster, and equally secure deployment that operates perfectly within Free Tier constraints.

---

## Deployment & Operations Guide

Because this architecture relies on OpenID Connect (OIDC) and remote state locking, it requires a one-time manual bootstrap to establish trust between GitHub and AWS before the automated CI/CD pipeline can take over.

### Prerequisites
* An AWS Account with administrative access.
* A GitHub Repository containing this code.
* AWS CLI and Terraform installed on your local machine.
* Run `aws configure` locally with a temporary Access Key to authorize your terminal for the initial bootstrap.

### Phase 1: The Cloud Bootstrap (Local Execution)
Before GitHub Actions can deploy your infrastructure, it needs a legal identity (IAM Role) and a place to store its memory (Terraform State).

1. **Configure the OIDC Trust Policy:**
   Before applying the bootstrap, you must update the OIDC Trust Policy to point to your specific GitHub repository so AWS knows who to trust. 
   > Open `tf-boostrap-backend/main.tf`, locate the `Condition` block inside the IAM Role, and change the placeholder to your exact GitHub username and repository name:
   > `"token.actions.githubusercontent.com:sub" = "repo:<YOUR_GITHUB_USERNAME>/<YOUR_REPOSITORY_NAME>:*"`

2. **Establish the OIDC Trust Bridge:**
   Navigate to the bootstrap directory and apply the configuration to create the GitHub Actions IAM Role, the S3 Bucket with versioning enabled and DynamoDB with state locking:
   ```bash
   cd tf-boostrap-backend
   terraform init
   terraform apply -auto-approve
   ```
   Take note of the github_actions_role_arn output.

### Phase 2: Pipeline Alignment
Because OIDC relies on AWS-side trust policies rather than hidden keys, no GitHub Secrets are needed. You simply need to align your configuration files:

1. **GitHub Actions YAML:** Open .github/workflows/main-apply.yml and .github/workflows/pr-plan.yml. Update the role-to-assume parameter with the IAM Role ARN generated in Phase 1.

2. Backend Configuration: Update env/dev/backend.tf and env/prod/backend.tf to point to the exact S3 bucket and DynamoDB table you created in Phase 1.

### Phase 3: Verify the Application:

Once CodeDeploy finishes, extract the public IP of your EC2 instance from the Terraform outputs or the AWS Console. Visit it in your browser (http://<EC2_PUBLIC_IP>) to see your zero-knowledge database secret retrieved live!

---

## Teardown Protocol

1. Purge the ECR Image Registry:

  ```bash
  aws ecr batch-delete-image --repository-name dev-flask-app --image-ids imageTag=latest --region eu-west-1
  ```

2. Destroy the Infrastructure:

  ```bash
  cd env/dev
  terraform init
  terraform destroy -auto-approve
  ```

  ```bash
  cd tf-bootstrap-backend
  terraform destroy -auto-approve
  ```
   
  
