# Zero-Knowledge Cloud-Native Web & Database Stack

An immutable, fully automated DevSecOps cloud infrastructure project. This repository provisions a secure, two-tier AWS network topology, deploys a containerized Python/Flask application, attaches a zero-trust encrypted PostgreSQL database, and orchestrates zero-touch CI/CD deployments via AWS CodeDeploy—all authenticated seamlessly via OpenID Connect (OIDC).

---

## The Tech Stack

This project integrates five distinct technology layers to create a highly efficient, automated security gate pipeline:

* **Infrastructure as Code (IaC):** Terraform (State managed via AWS S3 Backend)
* **Cloud Provider (AWS):** VPC, EC2, RDS PostgreSQL, ECR, S3, Secrets Manager, CodeDeploy, IAM (OIDC)
* **CI/CD Orchestration:** GitHub Actions
* **Containerization:** Docker
* **Application Layer:** Python 3.11, Flask, psycopg2-binary, Bash (Lifecycle Scripts)

---

## System Architecture

This architecture relies on a "Pull-based" deployment lifecycle. Rather than pushing commands directly to a server, the CI/CD pipeline packages instructions and delegates the execution to a local CodeDeploy agent residing within the secure network boundary.

```text
                              [ Public Internet ]
                                       │ (HTTP :80)
                                       ▼
                             ┌───────────────────┐
                             │  AWS Internet GW  │
                             └─────────┬─────────┘
                                       │
                 ┌─────────────────────┴─────────────────────┐
                 │                  AWS VPC                  │
                 │                                           │
                 │  ┌─────────────────────────────────────┐  │
                 │  │ Public Subnet (DMZ)                 │  │
                 │  │                                     │  │
                 │  │   ┌─────────────────────────────┐   │  │
                 │  │   │       EC2 Web Server        │◄──┼──┐ (4) Agent 
                 │  │   │    (CodeDeploy Agent)       │   │  │     Pulls
                 │  │   └──────────────┬──────────────┘   │  │     Artifact
                 │  └──────────────────┼──────────────────┘  │       │
                 │                     │ (TCP :5432)         │       │
                 │  ┌──────────────────▼──────────────────┐  │       │
                 │  │ Private Subnets (Multi-AZ Isolated) │  │       │
                 │  │                                     │  │       │
                 │  │   ┌─────────────────────────────┐   │  │       │
                 │  │   │   AWS RDS PostgreSQL DB     │   │  │       │
                 │  │   └─────────────────────────────┘   │  │       │
                 │  └─────────────────────────────────────┘  │       │
                 └───────────────────────────────────────────┘       │
                                                                     │
  =========================== CI/CD CONTROL PLANE ===================│=========
                                                                     │
      ┌────────────────┐ (1) OIDC Auth  ┌───────────────┐            │
      │ GitHub Actions ├───────────────►│ AWS IAM Role  │            │
      └──────┬─────────┘                └───────────────┘            │
             │                                                       │
             ├─────────────────► [ AWS ECR ] (2) Push Docker Image   │
             │                                                       │
             ├─────────────────► [ AWS S3  ] (3) Upload appspec.zip ─┘
             │                                                       │
             └─────────────────► [ AWS CodeDeploy ] (Triggers EC2 Agent)

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

1. **Zero-Knowledge Secret Injection:** The PostgreSQL master password is dynamically generated at high entropy via Terraform (`random_password`) and injected directly into **AWS Secrets Manager**. GitHub Actions never reads, caches, or echoes this password. During the AWS CodeDeploy lifecycle, the local EC2 agent uses its attached IAM Instance Profile to cryptographically pull the secret from the vault and parse it directly into container memory via `jq`.
2. **Keyless CI/CD Authentication:** GitHub Actions authenticates against AWS utilizing **OpenID Connect (OIDC)**. Long-lived, static `AWS_ACCESS_KEY_ID` secrets do not exist anywhere in this project's repositories or environments.
3. **Bastionless Remote Access:** Because SSH Port 22 is explicitly disabled at the Security Group level, all debugging and administrative shell access is tunneled securely through **AWS Systems Manager (SSM) Session Manager**. This completely eliminates internet-facing SSH brute-force attack vectors.
4. **Idempotent Lifecycle Rollouts:** Deployments do not require server teardowns or mutable infrastructure drift. GitHub Actions simply drops an artifact in S3 and delegates execution to the **AWS CodeDeploy Agent**. The agent reads the `appspec.yml` file to gracefully stop legacy containers, flush orphaned images, and spin up newly compiled containers natively.

---

## Automated CI/CD Lifecycle

When a developer merges code into the `main` branch, `.github/workflows/main-apply.yml` triggers a deterministic, zero-touch deployment pipeline. The lifecycle is strictly divided between GitHub Actions (Push) and the AWS CodeDeploy Agent (Pull).

### Phase 1: Continuous Integration & Infrastructure (GitHub Actions)
1. **OIDC Authentication:** The runner securely assumes the `GitHubActionsRole` in AWS via OpenID Connect.
2. **Infrastructure IaC Gate:** Terraform initializes the remote S3 backend, acquires the DynamoDB state lock, and applies infrastructure changes (`-auto-approve`).
3. **Variable Extraction:** The pipeline uses `terraform output -raw` to dynamically scrape the newly generated ECR Repository URL, RDS Endpoint, and CodeDeploy S3 Bucket name from the infrastructure state.
4. **Artifact Compilation:** The lightweight `python:3.11-slim` Docker image is built and pushed to Amazon ECR.
5. **The Ephemeral Bridge:** GitHub Actions dynamically writes a `.env` file containing the Terraform-generated database endpoints and ECR URLs. 
6. **Artifact Packaging:** The `.env` file, Bash lifecycle scripts, and `appspec.yml` are zipped and uploaded to the S3 CodeDeploy bucket. GitHub Actions triggers the deployment and awaits a callback.

### Phase 2: Continuous Deployment & Rollout (AWS CodeDeploy)
Once triggered, the CodeDeploy Agent running securely inside the EC2 DMZ takes over execution based on the `appspec.yml` lifecycle hooks:

1. **`ApplicationStop` Hook:**
   * Executes `scripts/stop_container.sh`.
   * Gracefully stops and removes the legacy `flask-app` container if it exists, ensuring an idempotent deployment environment.
2. **`ApplicationStart` Hook:**
   * Executes `scripts/start_container.sh`.
   * **Sources Context:** Loads the dynamically generated `.env` file to locate the database and ECR endpoints.
   * **Authenticates:** Uses the EC2 IAM Instance Profile to authenticate the local Docker daemon against AWS ECR.
   * **Zero-Knowledge Extraction:** Quietly queries AWS Secrets Manager, utilizing `jq` to parse the raw JSON payload and extract the master database password without echoing it to any log files.
   * **Container Boot:** Spins up the new Docker container bound to `80:80`, injecting the database credentials via environment variables (`-e`).
   * **Database Seeding:** Pauses for container socket binding, then executes `seed_db.py` inside the live container to truncate legacy data, generate a new cryptographically secure random password, and write it to the PostgreSQL database.
  
---
  
## Repository Structure

This repository strictly separates Application Code, Deployment Lifecycle Scripts, and Infrastructure as Code (IaC) to ensure a clean separation of concerns.

```text
.
├── .github/
│   └── workflows/
│       ├── main-apply.yml          # Continuous Deployment pipeline & CodeDeploy trigger
│       └── pr-plan.yml             # CI/CD security gate: Terraform plan & PR validation
├── app/
│   ├── app.py                      # Flask web application & RDS Read route
│   ├── seed_db.py                  # Auto-seeder with cryptographic password generation
│   ├── Dockerfile                  # Python 3.11 slim container build instructions
│   └── requirements.txt            # Python dependencies (Flask, psycopg2-binary)
├── scripts/
│   ├── start_container.sh          # CodeDeploy ApplicationStart hook (Pull, Auth, Run)
│   └── stop_container.sh           # CodeDeploy ApplicationStop hook (Graceful teardown)
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
│       ├── main.tf                 # Core infra (EC2, RDS, ECR, Secrets, CodeDeploy Agent)
│       ├── security.tf             # IAM Roles, Policies, Instance Profiles
│       ├── codedeploy.tf           # CodeDeploy App, Deployment Group, Artifact S3 Bucket
│       ├── variables.tf            # Dynamic module input variables
│       └── outputs.tf              # Module attribute pitchers to pass data upstream
├── tf-boostrap-backend/
│   └── main.tf                     # OIDC Identity Provider & GitHub Actions IAM Role setup
├── appspec.yml                     # AWS CodeDeploy instruction manual and hook mapping
├── .gitignore                      # Ignores local .terraform directories and .env files
└── README.md                       # Master architecture document and efficiency assessment

```

---

## Deployment & Operations Guide

Because this architecture relies on OpenID Connect (OIDC) and remote state locking, it requires a one-time manual bootstrap to establish trust between GitHub and AWS before the automated CI/CD pipeline can take over.

### Prerequisites
* An AWS Account with administrative access.
* A GitHub Repository containing this code.
* AWS CLI and Terraform installed on your local machine.

### Phase 1: The Cloud Bootstrap (Local Execution)
Before GitHub Actions can deploy your infrastructure, it needs a legal identity (IAM Role) and a place to store its memory (Terraform State).

1. **Establish the OIDC Trust Bridge:**
   Navigate to the bootstrap directory and apply the configuration to create the GitHub Actions IAM Role:
   ```bash
   cd tf-boostrap-backend
   terraform init
   terraform apply -auto-approve
   ```
   Take note of the github_actions_role_arn output.

2. **Create the State Storage (Backend):**
    Manually create (via AWS CLI or Console) an S3 bucket to hold the Terraform state and a DynamoDB table (with partition key LockID) to handle state locking.

### Phase 2: Pipeline Configuration

