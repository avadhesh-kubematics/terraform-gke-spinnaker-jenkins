output "network" {
  value = "${google_compute_subnetwork.default.network}"
}

output "subnetwork_name" {
  value = "${google_compute_subnetwork.default.name}"
}

output "cluster_name" {
  value = "${google_container_cluster.default.name}"
}

output "cluster_region" {
  value = "${var.region}"
}

output "cluster_zone" {
  value = "${google_container_cluster.default.zone}"
}

output "jenkins_service_url" {
  value = "https://${google_endpoints_service.jenkins_openapi_service.service_name}"
}

output "spinnaker_service_url" {
  value = "https://${google_endpoints_service.spinnaker_openapi_service.service_name}"
}
