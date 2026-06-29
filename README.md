# Zero-Knowledge Cloud-Native Web & Database Stack

An immutable, fully automated DevSecOps cloud infrastructure project. This repository provisions a secure, two-tier AWS network topology, deploys a containerized Python/Flask application, attaches a zero-trust encrypted PostgreSQL database, and orchestrates zero-touch CI/CD deployments via AWS CodeDeploy—all authenticated seamlessly via OpenID Connect (OIDC).

---

## 🛠️ The Tech Stack

This project integrates five distinct technology layers to create a highly efficient, automated security gate pipeline:

* **Infrastructure as Code (IaC):** Terraform (State managed via AWS S3 Backend)
* **Cloud Provider (AWS):** VPC, EC2, RDS PostgreSQL, ECR, S3, Secrets Manager, CodeDeploy, IAM (OIDC)
* **CI/CD Orchestration:** GitHub Actions
* **Containerization:** Docker
* **Application Layer:** Python 3.11, Flask, psycopg2-binary, Bash (Lifecycle Scripts)

* ---

## 🏛️ System Architecture

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
