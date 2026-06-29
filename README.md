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

* ---

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

### Network Topology & Routing

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
