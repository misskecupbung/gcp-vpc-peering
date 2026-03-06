# GCP VPC Peering

Connect VPCs privately so resources in each network can talk to each other without going through the public internet.

This is a common pattern when you have separate teams or environments (platform, data, security) that need internal connectivity. VPC Peering gives you private RFC 1918 routing between networks — no VPN, no public IPs.

> **Duration**: 45 minutes  
> **Level**: Intermediate

**What you'll build:**
- Three VPCs with selective peering
- Cross-VPC PostgreSQL connectivity (app tier → data tier)
- Proof that VPC Peering is non-transitive (the #1 gotcha)

--- 

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Your Infrastructure                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌──────────────────┐       ┌──────────────────┐       ┌────────────────┐  │
│   │  vpc-platform    │       │  vpc-data        │       │ vpc-security   │  │
│   │  10.1.0.0/24     │       │  10.2.0.0/24     │       │ 10.3.0.0/24    │  │
│   │                  │       │                  │       │                │  │
│   │  ┌────────────┐  │  VPC  │  ┌────────────┐  │  VPC  │ ┌───────────┐  │  │
│   │  │ app-vm     │  │Peering│  │ data-vm    │  │Peering│ │security-vm│  │  │
│   │  │ (psql      │◄─┼──────►┼─►│ (PostgreSQL)│◄┼──────►┼─│ (nginx)   │  │  │
│   │  │  client)   │  │       │  │             │ │       │ │           │  │  │
│   │  └────────────┘  │       │  └─────────────┘ │       │ └───────────┘  │  │
│   │                  │       │                  │       │                │  │
│   └──────────────────┘       └──────────────────┘       └────────────────┘  │
│                                                                             │
│   platform ↔ data: ✅ PEERED                                                │
│   data ↔ security:  ✅ PEERED                                               │
│   platform → security: ❌ NOT PEERED (non-transitive)                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## VPC Peering vs Shared VPC

Both solve cross-VPC connectivity, but they work differently:

| | VPC Peering | Shared VPC |
|-|-------------|------------|
| **Setup** | Between any two VPCs | Requires GCP Organization |
| **Ownership** | Each team manages their own VPC | Central network team manages VPC |
| **Routing** | Non-transitive (A↔B, B↔C doesn't mean A↔C) | Shared subnets across projects |
| **Use case** | Connect separate teams/environments | Centralized network management |
| **Firewall** | Each VPC manages own firewall rules | Central firewall management |

**This workshop covers VPC Peering** because it works without an Organization and is the most common pattern for connecting separate environments.

---

## Prerequisites

- GCP account with billing enabled
- `gcloud` CLI installed and authenticated
- Terraform >= 1.0

---

## Deploy

### Step 0: Clone the Repo

```bash
git clone https://github.com/misskecupbung/gcp-vpc-peering.git
cd gcp-vpc-peering
```

### Step 1: Enable APIs

```bash
export PROJECT_ID="your-project-id"
gcloud config set project $PROJECT_ID

gcloud services enable compute.googleapis.com
gcloud services enable iap.googleapis.com
```

### Step 2: Deploy with Terraform

```bash
cd terraform

cp terraform.tfvars.example terraform.tfvars
sed -i "s/your-project-id/$PROJECT_ID/" terraform.tfvars

terraform init
terraform plan
terraform apply
```

Terraform creates:
- `vpc-platform` (10.1.0.0/24) with `app-vm`
- `vpc-data` (10.2.0.0/24) with `data-vm` (PostgreSQL + sample data)
- `vpc-security` (10.3.0.0/24) with `security-vm`
- Peering: platform ↔ data, data ↔ security
- Firewall rules for IAP SSH and cross-VPC traffic

> **Note**: VMs are created quickly, but startup scripts take 1-2 minutes to install packages. Wait before testing.

### Step 3: Check Outputs

```bash
terraform output
```

You'll see:
- `app_vm_ip` — Internal IP of app-vm
- `data_vm_ip` — Internal IP of data-vm
- `security_vm_ip` — Internal IP of security-vm
- `peering_platform_data` — Should be `ACTIVE`
- `peering_data_security` — Should be `ACTIVE`

> **Note**: If peering shows `INACTIVE` right after `terraform apply`, wait 30-60 seconds and run `terraform refresh` — peering takes a moment to become active.

---

## Verify

### 1. Check Peering Status

```bash
gcloud compute networks peerings list --network=vpc-platform
gcloud compute networks peerings list --network=vpc-data
gcloud compute networks peerings list --network=vpc-security
```

All peerings should show `ACTIVE` state.

### 2. Test Connectivity: app-vm → data-vm

```bash
cd terraform

DATA_VM_IP=$(terraform output -raw data_vm_ip)

# Ping
gcloud compute ssh app-vm --zone=us-central1-a --tunnel-through-iap \
    --command="ping -c 3 $DATA_VM_IP"

# HTTP (nginx)
gcloud compute ssh app-vm --zone=us-central1-a --tunnel-through-iap \
    --command="curl -s http://$DATA_VM_IP"
```

Expected: `Hello from data-vm`

### 3. Test PostgreSQL Across the Peering

This is the real test — can app-vm query a database running in a different VPC?

```bash
DATA_VM_IP=$(terraform output -raw data_vm_ip)

# Check if PostgreSQL port is reachable
gcloud compute ssh app-vm --zone=us-central1-a --tunnel-through-iap \
    --command="pg_isready -h $DATA_VM_IP -U appuser"
```

Expected: `accepting connections`

Now query the sample data:

```bash
gcloud compute ssh app-vm --zone=us-central1-a --tunnel-through-iap \
    --command="PGPASSWORD=changeme123 psql -h $DATA_VM_IP -U appuser -d appdb -c 'SELECT * FROM orders;'"
```

Expected:

```
 id | product  | quantity |         created_at
----+----------+----------+----------------------------
  1 | Widget A |       10 | 2026-03-06 ...
  2 | Widget B |       25 | 2026-03-06 ...
  3 | Widget C |        5 | 2026-03-06 ...
```

This works because vpc-platform and vpc-data are peered, and the firewall rule on vpc-data allows TCP:5432 from 10.1.0.0/24.

### 4. Test data-vm → security-vm

```bash
SECURITY_VM_IP=$(terraform output -raw security_vm_ip)

gcloud compute ssh data-vm --zone=us-central1-a --tunnel-through-iap \
    --command="ping -c 3 $SECURITY_VM_IP"

gcloud compute ssh data-vm --zone=us-central1-a --tunnel-through-iap \
    --command="curl -s http://$SECURITY_VM_IP"
```

Expected: `Hello from security-vm` — works because data ↔ security are peered.

### 5. Prove Non-Transitive Routing (the Gotcha)

Now the key test. Platform is peered with data, data is peered with security. Can platform reach security?

```bash
SECURITY_VM_IP=$(terraform output -raw security_vm_ip)

# This will FAIL — timeout expected
gcloud compute ssh app-vm --zone=us-central1-a --tunnel-through-iap \
    --command="ping -c 3 -W 3 $SECURITY_VM_IP"
```

**Expected: 100% packet loss.** app-vm cannot reach security-vm even though both are peered with vpc-data.

This is non-transitive routing — the most important thing to understand about VPC Peering. Each peering is an independent connection. Traffic does not hop through an intermediate VPC.

```
platform ↔ data:     ✅ peered, direct route exists
data ↔ security:     ✅ peered, direct route exists
platform → security: ❌ no peering, no route
```

If you need platform to reach security, you'd have to create a third peering directly between them.

### 6. Verify Private Routing

From inside app-vm, confirm traffic takes the internal path:

```bash
DATA_VM_IP=$(terraform output -raw data_vm_ip)

gcloud compute ssh app-vm --zone=us-central1-a --tunnel-through-iap \
    --command="traceroute -m 5 $DATA_VM_IP"
```

You should see a single hop — traffic goes directly between VPCs, not through any gateway or public internet.

---

## Cleanup

```bash
cd terraform
terraform destroy
```

---

## Resources

- [VPC Network Peering](https://cloud.google.com/vpc/docs/vpc-peering)
- [Shared VPC Overview](https://cloud.google.com/vpc/docs/shared-vpc)
- [VPC Peering Limits](https://cloud.google.com/vpc/docs/quota#vpc-peering)

---

## License

MIT
