# Cloud Data Pipeline – Gym Usage Tracker

## 📌 Overview
This project demonstrates a **serverless data pipeline on AWS** built with **Terraform** and automated using **GitHub Actions**.  
The system collects **gym equipment usage events** via an API, stores them in **Amazon S3**, and generates **daily reports** using **Athena**, which are then emailed via **AWS SES**.

---

## 🚀 Architecture
<img width="3675" height="1464" alt="image" src="https://github.com/user-attachments/assets/d8f3b277-ab03-4565-b57e-2c07e5bcfa1c" />



**Workflow:**
1. **API Gateway** – Receives gym usage events.
2. **Lambda (Ingest)** – Processes and stores events in **S3 (Raw Data)**.
3. **Glue Data Catalog** – Creates a schema for Athena queries.
4. **Athena** – Analyzes JSON event data.
5. **Lambda (Report)** – Runs daily queries and stores CSV reports in **S3 (Reports)**.
6. **SES (Email)** – Sends daily report links to configured recipients.

---

## 🛠 Tech Stack
- **AWS Services**: API Gateway, Lambda, S3, Glue, Athena, EventBridge, SES.
- **Infrastructure as Code**: Terraform.
- **CI/CD**: GitHub Actions (automated packaging & deployment).
- **Languages**: Python (for Lambda functions).

---

## ⚙️ Prerequisites
- **AWS Account** with IAM user & programmatic access.
- **Terraform** installed (v1.5+ recommended).
- **AWS CLI** configured (`aws configure`).
- **GitHub Secrets**:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - `AWS_REGION` = `ap-south-1`

---

## 📦 Deployment

### **1. Clone Repository**
```bash
git clone https://github.com/mks8600/AI-Certs-assignment.git
cd AI-Certs-assignment/iac
terraform init
terraform apply -auto-approve

```
This will:

Create S3 buckets (raw_data & reports).

Deploy Lambda functions.

Configure API Gateway, Glue DB, Athena, and EventBridge.


🔍 Testing the Pipeline
1. Send a Test Event
```
curl -X POST <API_INVOKE_URL> \
  -H "Content-Type: application/json" \
  -d '{
    "member_id": "M12345",
    "equipment_id": "Treadmill-01",
    "start_time": "2025-07-19T06:30:00Z",
    "end_time": "2025-07-19T07:00:00Z",
    "calories_burned": 200,
    "membership_expiry": "2025-07-31"
  }'
```

2. Query in Athena
In AWS Athena, run:

```SELECT * FROM gym_events LIMIT 10;```
3. Daily Report
A Lambda function (gym-daily-report) generates a CSV report daily and stores it in the reports S3 bucket.

AWS SES sends an email with a report link.

🔄 CI/CD with GitHub Actions
The ci.yml workflow:

Packages Lambda code (handler.py).

Runs Terraform init, validate, plan, and apply.

Deploys the infrastructure automatically on push to main.

Screenshorts:
1.S3 Bucket
<img width="1440" height="900" alt="Screenshot 2025-07-19 at 12 08 16 PM" src="https://github.com/user-attachments/assets/183a48da-c2df-4d29-8c34-46b5e7620f23" />

2.Lambda (Report function manual testing )
<img width="1440" height="900" alt="Screenshot 2025-07-19 at 12 08 29 PM" src="https://github.com/user-attachments/assets/7da9b6fa-893b-49b0-b894-30e7bf634749" />

3.Github Action (Automation pipline)
<img width="1440" height="900" alt="Screenshot 2025-07-19 at 12 10 31 PM" src="https://github.com/user-attachments/assets/bd07098c-57f3-4970-b840-42d9ecf2b4ea" />




