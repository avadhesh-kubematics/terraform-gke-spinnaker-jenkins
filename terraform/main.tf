variable "region" {
  default = "us-central1"
}

variable "zone" {
  default = "us-central1-a"
}

variable "network_name" {
  default = "tf-gke-helm"
}

provider "google" {
  region = "${var.region}"
  credentials = "${file("terraform.json")}"
  project = "${var.project}"
}

provider "google-beta" {
  region = "${var.region}"
  credentials = "${file("terraform.json")}"
  project = "${var.project}"
}

data "google_client_config" "current" {}

resource "google_compute_network" "default" {
  name                    = "${var.network_name}"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "default" {
  name                     = "${var.network_name}"
  ip_cidr_range            = "10.127.0.0/20"
  network                  = "${google_compute_network.default.self_link}"
  region                   = "${var.region}"
  private_ip_google_access = true
}

data "google_container_engine_versions" "default" {
  zone = "${var.zone}"
  project = "fabled-era-223004"
}

resource "google_container_cluster" "default" {
  provider = "google-beta"

  name               = "tf-gke-helm"
  zone               = "${var.zone}"
  initial_node_count = 4
  min_master_version = "${data.google_container_engine_versions.default.latest_master_version}"
  network            = "${google_compute_subnetwork.default.name}"
  subnetwork         = "${google_compute_subnetwork.default.name}"

  // Wait for the GCE LB controller to cleanup the resources.
  provisioner "local-exec" {
    when    = "destroy"
    command = "sleep 90"
  }

  addons_config {
    kubernetes_dashboard {
      disabled = false
    }

    horizontal_pod_autoscaling {
      disabled = false
    }
    istio_config {
      disabled = true
    }
  }

//  network_policy {
//    enabled = true
//    provider = "CALICO"
//  }

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    machine_type = "n1-highmem-4"
  }
}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.default.endpoint}"

  token                  = "${data.google_client_config.current.access_token}"
  cluster_ca_certificate = "${base64decode(google_container_cluster.default.master_auth.0.cluster_ca_certificate)}"
}

