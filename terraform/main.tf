terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# -----------------------------------------------------------------------------
# VPCs
# -----------------------------------------------------------------------------
resource "google_compute_network" "vpc_platform" {
  name                    = "vpc-platform"
  auto_create_subnetworks = false
  description             = "Platform team - application workloads"
}

resource "google_compute_network" "vpc_data" {
  name                    = "vpc-data"
  auto_create_subnetworks = false
  description             = "Data team - databases"
}

# -----------------------------------------------------------------------------
# Subnets
# -----------------------------------------------------------------------------
resource "google_compute_subnetwork" "subnet_platform" {
  name          = "subnet-platform"
  ip_cidr_range = "10.1.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc_platform.id
}

resource "google_compute_subnetwork" "subnet_data" {
  name          = "subnet-data"
  ip_cidr_range = "10.2.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc_data.id
}

# -----------------------------------------------------------------------------
# Firewall Rules - IAP SSH
# -----------------------------------------------------------------------------
resource "google_compute_firewall" "vpc_platform_allow_iap" {
  name    = "vpc-platform-allow-iap"
  network = google_compute_network.vpc_platform.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}

resource "google_compute_firewall" "vpc_data_allow_iap" {
  name    = "vpc-data-allow-iap"
  network = google_compute_network.vpc_data.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}

# -----------------------------------------------------------------------------
# Firewall Rules - VPC Peering Traffic
# -----------------------------------------------------------------------------
resource "google_compute_firewall" "vpc_data_allow_platform" {
  name    = "vpc-data-allow-platform"
  network = google_compute_network.vpc_data.id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["80", "3306", "5432"]
  }

  source_ranges = ["10.1.0.0/24"]
}

resource "google_compute_firewall" "vpc_platform_allow_data" {
  name    = "vpc-platform-allow-data"
  network = google_compute_network.vpc_platform.id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["10.2.0.0/24"]
}

# -----------------------------------------------------------------------------
# Firewall Rules - VPC Connector
# -----------------------------------------------------------------------------
resource "google_compute_firewall" "vpc_platform_allow_connector" {
  name    = "vpc-platform-allow-connector"
  network = google_compute_network.vpc_platform.id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "3306", "5432"]
  }

  source_ranges = ["10.8.0.0/28"]
}

# -----------------------------------------------------------------------------
# VMs
# -----------------------------------------------------------------------------
resource "google_compute_instance" "app_vm" {
  name         = "app-vm"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network    = google_compute_network.vpc_platform.id
    subnetwork = google_compute_subnetwork.subnet_platform.id
    # No external IP
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update && apt-get install -y nginx
    echo "Hello from app-vm" > /var/www/html/index.html
  EOF

  tags = ["app-server"]
}

resource "google_compute_instance" "db_vm" {
  name         = "db-vm"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network    = google_compute_network.vpc_data.id
    subnetwork = google_compute_subnetwork.subnet_data.id
    # No external IP
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update && apt-get install -y nginx
    echo "Hello from db-vm" > /var/www/html/index.html
  EOF

  tags = ["db-server"]
}

# -----------------------------------------------------------------------------
# VPC Peering
# -----------------------------------------------------------------------------
resource "google_compute_network_peering" "platform_to_data" {
  name         = "platform-to-data"
  network      = google_compute_network.vpc_platform.id
  peer_network = google_compute_network.vpc_data.id
}

resource "google_compute_network_peering" "data_to_platform" {
  name         = "data-to-platform"
  network      = google_compute_network.vpc_data.id
  peer_network = google_compute_network.vpc_platform.id

  depends_on = [google_compute_network_peering.platform_to_data]
}

# -----------------------------------------------------------------------------
# Serverless VPC Access Connector
# -----------------------------------------------------------------------------
resource "google_vpc_access_connector" "connector" {
  name          = "my-connector"
  region        = var.region
  network       = google_compute_network.vpc_platform.id
  ip_cidr_range = "10.8.0.0/28"
  min_instances = 2
  max_instances = 3
  machine_type  = "e2-micro"
}

# -----------------------------------------------------------------------------
# Private Service Connect - Google APIs
# -----------------------------------------------------------------------------
resource "google_compute_address" "psc_address" {
  name         = "psc-google-apis-ip"
  region       = var.region
  subnetwork   = google_compute_subnetwork.subnet_platform.id
  address_type = "INTERNAL"
  address      = "10.1.0.100"
}

resource "google_compute_forwarding_rule" "psc_google_apis" {
  name                  = "psc-google-apis"
  region                = var.region
  network               = google_compute_network.vpc_platform.id
  ip_address            = google_compute_address.psc_address.id
  target                = "all-apis"
  load_balancing_scheme = ""
}

# -----------------------------------------------------------------------------
# Private DNS Zone for Google APIs
# -----------------------------------------------------------------------------
resource "google_dns_managed_zone" "googleapis_private" {
  name        = "googleapis-private"
  dns_name    = "googleapis.com."
  description = "Private access to Google APIs"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.vpc_platform.id
    }
  }
}

resource "google_dns_record_set" "storage_googleapis" {
  name         = "storage.googleapis.com."
  managed_zone = google_dns_managed_zone.googleapis_private.name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.psc_address.address]
}

resource "google_dns_record_set" "wildcard_googleapis" {
  name         = "*.googleapis.com."
  managed_zone = google_dns_managed_zone.googleapis_private.name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.psc_address.address]
}

# -----------------------------------------------------------------------------
# Cloud Run Service
# -----------------------------------------------------------------------------
resource "google_cloud_run_v2_service" "my_api" {
  name     = "my-api"
  location = var.region

  template {
    containers {
      image = "gcr.io/${var.project_id}/my-api"
    }

    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }
  }

  depends_on = [google_vpc_access_connector.connector]
}

# Allow unauthenticated access
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.my_api.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}
