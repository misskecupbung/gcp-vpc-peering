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
# VPC - Platform
# -----------------------------------------------------------------------------
resource "google_compute_network" "vpc_platform" {
  name                    = "vpc-platform"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet_platform" {
  name          = "subnet-platform"
  ip_cidr_range = "10.1.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc_platform.id
}

# -----------------------------------------------------------------------------
# VPC - Data
# -----------------------------------------------------------------------------
resource "google_compute_network" "vpc_data" {
  name                    = "vpc-data"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet_data" {
  name          = "subnet-data"
  ip_cidr_range = "10.2.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc_data.id
}

# -----------------------------------------------------------------------------
# VPC Peering - both directions
# -----------------------------------------------------------------------------
resource "google_compute_network_peering" "platform_to_data" {
  name         = "platform-to-data"
  network      = google_compute_network.vpc_platform.self_link
  peer_network = google_compute_network.vpc_data.self_link
}

resource "google_compute_network_peering" "data_to_platform" {
  name         = "data-to-platform"
  network      = google_compute_network.vpc_data.self_link
  peer_network = google_compute_network.vpc_platform.self_link

  depends_on = [google_compute_network_peering.platform_to_data]
}

# -----------------------------------------------------------------------------
# Firewall - Platform VPC
# -----------------------------------------------------------------------------
resource "google_compute_firewall" "platform_allow_iap" {
  name    = "platform-allow-iap"
  network = google_compute_network.vpc_platform.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}

resource "google_compute_firewall" "platform_allow_from_data" {
  name    = "platform-allow-from-data"
  network = google_compute_network.vpc_platform.id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["10.2.0.0/24"]
}

# -----------------------------------------------------------------------------
# Firewall - Data VPC
# -----------------------------------------------------------------------------
resource "google_compute_firewall" "data_allow_iap" {
  name    = "data-allow-iap"
  network = google_compute_network.vpc_data.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}

resource "google_compute_firewall" "data_allow_from_platform" {
  name    = "data-allow-from-platform"
  network = google_compute_network.vpc_data.id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "5432"]
  }

  source_ranges = ["10.1.0.0/24"]
}

# -----------------------------------------------------------------------------
# VM - app-vm in Platform VPC
# -----------------------------------------------------------------------------
resource "google_compute_instance" "app_vm" {
  name         = "app-vm"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network    = google_compute_network.vpc_platform.id
    subnetwork = google_compute_subnetwork.subnet_platform.id
  }

  metadata_startup_script = file("${path.module}/../scripts/startup-app.sh")

  tags = ["app-server"]
}

# -----------------------------------------------------------------------------
# VM - data-vm in Data VPC (with PostgreSQL)
# -----------------------------------------------------------------------------
resource "google_compute_instance" "data_vm" {
  name         = "data-vm"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network    = google_compute_network.vpc_data.id
    subnetwork = google_compute_subnetwork.subnet_data.id
  }

  metadata_startup_script = file("${path.module}/../scripts/startup-data.sh")

  tags = ["data-server"]
}

# -----------------------------------------------------------------------------
# VPC - Security (to demonstrate non-transitive routing)
# -----------------------------------------------------------------------------
resource "google_compute_network" "vpc_security" {
  name                    = "vpc-security"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet_security" {
  name          = "subnet-security"
  ip_cidr_range = "10.3.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc_security.id
}

# -----------------------------------------------------------------------------
# VPC Peering - data ↔ security
# -----------------------------------------------------------------------------
resource "google_compute_network_peering" "data_to_security" {
  name         = "data-to-security"
  network      = google_compute_network.vpc_data.self_link
  peer_network = google_compute_network.vpc_security.self_link

  depends_on = [google_compute_network_peering.data_to_platform]
}

resource "google_compute_network_peering" "security_to_data" {
  name         = "security-to-data"
  network      = google_compute_network.vpc_security.self_link
  peer_network = google_compute_network.vpc_data.self_link

  depends_on = [google_compute_network_peering.data_to_security]
}

# -----------------------------------------------------------------------------
# Firewall - Security VPC
# -----------------------------------------------------------------------------
resource "google_compute_firewall" "security_allow_iap" {
  name    = "security-allow-iap"
  network = google_compute_network.vpc_security.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}

resource "google_compute_firewall" "security_allow_from_data" {
  name    = "security-allow-from-data"
  network = google_compute_network.vpc_security.id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["10.2.0.0/24"]
}

# Update data VPC firewall to also allow from security
resource "google_compute_firewall" "data_allow_from_security" {
  name    = "data-allow-from-security"
  network = google_compute_network.vpc_data.id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["10.3.0.0/24"]
}

# -----------------------------------------------------------------------------
# VM - security-vm in Security VPC
# -----------------------------------------------------------------------------
resource "google_compute_instance" "security_vm" {
  name         = "security-vm"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network    = google_compute_network.vpc_security.id
    subnetwork = google_compute_subnetwork.subnet_security.id
  }

  metadata_startup_script = file("${path.module}/../scripts/startup-security.sh")

  tags = ["security-server"]
}
