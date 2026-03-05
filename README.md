# GCP VPC Private Access

Set up private connectivity in GCP using VPC Peering, Serverless VPC Access Connector, and Private Service Connect.

In production environments, you don't want your services talking over the public internet. This workshop shows you how to keep traffic private — connect VPCs without public IPs, let Cloud Run access internal databases, and route Google API calls through private endpoints.

> **Duration**: 45 minutes  
> **Level**: Intermediate

**What you'll achieve:**
- Resources communicate using internal IPs only (no public internet)
- Cloud Run connects to private VPC resources (databases, internal APIs)
- Google API traffic stays within Google's network
- Zero public IP exposure for backend services

---

## What You'll Build

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Your Infrastructure                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌────────────────┐       VPC Peering        ┌────────────────┐            │
│   │  vpc-platform  │◄────────────────────────►│   vpc-data     │            │
│   │  10.1.0.0/24   │                          │  10.2.0.0/24   │            │
│   │                │                          │                │            │
│   │  ┌──────────┐  │                          │  ┌──────────┐  │            │
│   │  │ app-vm   │  │                          │  │ db-vm    │  │            │
│   │  └──────────┘  │                          │  └──────────┘  │            │
│   │                │                          └────────────────┘            │
│   │  ┌───────────────────┐                                                  │
│   │  │  VPC Connector    │◄─── my-api (Cloud Run)                           │
│   │  │  10.8.0.0/28      │                                                  │
│   │  └───────────────────┘                                                  │
│   │                │                                                        │
│   │  ┌───────────────────┐     ┌──────────────────┐                         │
│   │  │ PSC Endpoint      │────►│ Google Cloud     │                         │
│   │  │ 10.1.0.100        │     │ Storage (private)│                         │
│   │  └───────────────────┘     └──────────────────┘                         │
│   └────────────────┘                                                        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

| Service | What It Does |
|---------|--------------|
| **VPC Peering** | Connect two VPCs privately without going through the internet |
| **Serverless VPC Access** | Let Cloud Run / Cloud Functions reach private VPC resources |
| **Private Service Connect** | Access Google APIs through private endpoints |

---

## Prerequisites

- GCP account with billing enabled
- `gcloud` CLI installed and authenticated
- Terraform >= 1.0

---

## Deploy Infrastructure

### Step 1: Enable APIs

```bash
export PROJECT_ID="your-project-id"
gcloud config set project $PROJECT_ID

gcloud services enable compute.googleapis.com
gcloud services enable vpcaccess.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable dns.googleapis.com
gcloud services enable iap.googleapis.com
```

### Step 2: Build Container Image

Terraform doesn't build Docker images, so build the Cloud Run image first:

```bash
cd app
gcloud builds submit --tag gcr.io/$PROJECT_ID/my-api
cd ..
```

### Step 3: Deploy with Terraform

```bash
cd terraform

# Configure variables with your project ID
cp terraform.tfvars.example terraform.tfvars
sed -i '' "s/your-project-id/$PROJECT_ID/" terraform.tfvars

# Deploy
terraform init
terraform plan
terraform apply
```

Terraform creates:
- 2 VPCs with subnets
- 2 test VMs (no public IPs)
- VPC Peering between the VPCs
- Serverless VPC Access Connector
- Private Service Connect endpoint for Google APIs
- Private DNS zone
- Firewall rules
- Cloud Run service (connected to VPC)

### Step 4: Check Outputs

```bash
terraform output
```

You'll see:
- `app_vm_internal_ip` - IP of app-vm
- `db_vm_internal_ip` - IP of db-vm
- `vpc_connector_id` - Connector for Cloud Run
- `psc_endpoint_ip` - Private endpoint (10.1.0.100)
- `peering_status` - Should be ACTIVE
- `cloud_run_url` - Cloud Run service URL

---

## Test VPC Peering

Verify that app-vm can reach db-vm through the peered connection.

```bash
# Make sure you're in the terraform directory
cd terraform

# Get db-vm IP from Terraform output
DB_VM_IP=$(terraform output -raw db_vm_internal_ip)
echo "db-vm IP: $DB_VM_IP"

# SSH into app-vm and ping db-vm
gcloud compute ssh app-vm --zone=us-central1-a --tunnel-through-iap \
    --command="ping -c 3 $DB_VM_IP"

# Test HTTP
gcloud compute ssh app-vm --zone=us-central1-a --tunnel-through-iap \
    --command="curl http://$DB_VM_IP"
```

Expected output: "Hello from db-vm"

---

## Test Serverless VPC Access

Cloud Run is already deployed via Terraform. Test connectivity to VPC resources:

```bash
# Make sure you're in the terraform directory
cd terraform

# Get Cloud Run URL from Terraform
SERVICE_URL=$(terraform output -raw cloud_run_url)
echo "Cloud Run URL: $SERVICE_URL"

# Test health endpoint
curl $SERVICE_URL

# Test connectivity to internal VM
APP_VM_IP=$(terraform output -raw app_vm_internal_ip)
echo "Testing connection to app-vm: $APP_VM_IP"
curl "$SERVICE_URL/check-internal/$APP_VM_IP"
```

Expected: Cloud Run reaches the internal VM through VPC connector.

---

## Test Private Service Connect

Verify that Google APIs are accessed through the private endpoint.

```bash
# SSH into app-vm
gcloud compute ssh app-vm --zone=us-central1-a --tunnel-through-iap

# Check DNS resolution - should return 10.1.0.100
nslookup storage.googleapis.com

# Test Cloud Storage access through private endpoint
gsutil ls gs://gcp-public-data-landsat 2>/dev/null | head -5

# Exit
exit
```

Expected: DNS resolves to `10.1.0.100` (your PSC endpoint), not a public IP.

---

## Verification Summary

```bash
cd terraform

echo "=== VPC Peering ==="
terraform output peering_status

echo ""
echo "=== VPC Connector ==="
gcloud compute networks vpc-access connectors describe my-connector \
    --region=us-central1 --format="value(state)"

echo ""
echo "=== PSC Endpoint ==="
terraform output psc_endpoint_ip

echo ""
echo "=== Cloud Run ==="
terraform output cloud_run_url
```

---

## Cleanup

```bash
# Make sure you're in the terraform directory
cd terraform

# Destroy all Terraform resources
terraform destroy

# Delete container image (not managed by Terraform)
gcloud container images delete gcr.io/$PROJECT_ID/my-api --force-delete-tags --quiet
```

---

## Troubleshooting

### VPC Peering shows INACTIVE
Check both peering connections exist:
```bash
gcloud compute networks peerings list --network=vpc-platform
gcloud compute networks peerings list --network=vpc-data
```

### Cloud Run can't reach internal IPs
1. Connector must be READY: `gcloud compute networks vpc-access connectors list --region=us-central1`
2. Firewall must allow connector range (10.8.0.0/28)
3. Cloud Run and connector must be in the same region

### DNS still resolves to public IPs
1. VM must be in vpc-platform (the network linked to DNS zone)
2. Flush DNS cache: `sudo systemd-resolve --flush-caches`

---

## Resources

- [VPC Peering](https://cloud.google.com/vpc/docs/vpc-peering)
- [Serverless VPC Access](https://cloud.google.com/vpc/docs/serverless-vpc-access)
- [Private Service Connect](https://cloud.google.com/vpc/docs/private-service-connect)

---

## License

MIT
