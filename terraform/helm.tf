variable "helm_version" {
  default = "v2.12.3"
}

variable "jenkins_app_name" {
  default = "jenkins"
}

variable "spinnaker_app_name" {
  default = "spinnaker"
}

variable "acme_url" {
  default = "https://acme-v01.api.letsencrypt.org/directory"
}

provider "helm" {
  tiller_image = "gcr.io/kubernetes-helm/tiller:${var.helm_version}"

  service_account = "default"

  kubernetes {
    host                   = "${google_container_cluster.default.endpoint}"
    token                  = "${data.google_client_config.current.access_token}"
    cluster_ca_certificate = "${base64decode(google_container_cluster.default.master_auth.0.cluster_ca_certificate)}"
  }
}

resource "google_compute_address" "jenkins_address" {
  name   = "tf-gke-helm-${var.jenkins_app_name}"
  region = "${var.region}"
}

resource "google_compute_address" "spinnaker_address" {
  name   = "tf-gke-helm-${var.spinnaker_app_name}"
  region = "${var.region}"
}


resource "kubernetes_cluster_role_binding" "default" {
  metadata {
    name = "default"
  }

  subject {
    kind = "User"
    name = "system:serviceaccount:kube-system:default"
  }

  role_ref {
    kind  = "ClusterRole"
    name = "cluster-admin"
    api_group = ""
  }

  depends_on = ["google_container_cluster.default"]
}

data "template_file" "jenkins_openapi_spec" {
  template = "${file("${path.module}/openapi_spec.yaml")}"

  vars {
    endpoint_service = "${var.jenkins_app_name}-${random_id.endpoint-name.hex}.endpoints.${data.google_client_config.current.project}.cloud.goog"
    target           = "${google_compute_address.jenkins_address.address}"
  }
}

data "template_file" "spinnaker_openapi_spec" {
  template = "${file("${path.module}/openapi_spec.yaml")}"

  vars {
    endpoint_service = "${var.spinnaker_app_name}-${random_id.endpoint-name.hex}.endpoints.${data.google_client_config.current.project}.cloud.goog"
    target           = "${google_compute_address.spinnaker_address.address}"
  }
}

data "template_file" "jenkins_helm" {
  template = "${file("${path.module}/helm/jenkins/values.yaml")}"

  vars {
    jenkins_ingress_url = "${var.jenkins_app_name}-${random_id.endpoint-name.hex}.endpoints.${data.google_client_config.current.project}.cloud.goog"
  }
}

data "template_file" "spinnaker_helm" {
  template = "${file("${path.module}/helm/spinnaker/values.yaml")}"

  vars {
    spinnaker_ingress_url = "${var.spinnaker_app_name}-${random_id.endpoint-name.hex}.endpoints.${data.google_client_config.current.project}.cloud.goog"
  }
}

resource "random_id" "endpoint-name" {
  byte_length = 2
}

resource "google_endpoints_service" "jenkins_openapi_service" {
  service_name   = "${var.jenkins_app_name}-${random_id.endpoint-name.hex}.endpoints.${data.google_client_config.current.project}.cloud.goog"
  project        = "${data.google_client_config.current.project}"
  openapi_config = "${data.template_file.jenkins_openapi_spec.rendered}"
}

resource "google_endpoints_service" "spinnaker_openapi_service" {
  service_name   = "${var.spinnaker_app_name}-${random_id.endpoint-name.hex}.endpoints.${data.google_client_config.current.project}.cloud.goog"
  project        = "${data.google_client_config.current.project}"
  openapi_config = "${data.template_file.spinnaker_openapi_spec.rendered}"
}

resource "helm_release" "kube-lego" {
  name  = "kube-lego"
  chart = "stable/kube-lego"

  values = [<<EOF
rbac:
  create: true
config:
  LEGO_EMAIL: ${var.acme_email}
  LEGO_URL: ${var.acme_url}
  LEGO_SECRET_NAME: lego-acme
EOF
  ]

  depends_on = ["kubernetes_cluster_role_binding.default"]
}

resource "helm_release" "spinnaker-ingress" {
  name  = "spinnaker-ingress"
  chart = "stable/nginx-ingress"

  values = [<<EOF
rbac:
  create: true
controller:
  service:
    loadBalancerIP: ${google_compute_address.spinnaker_address.address}
EOF
  ]

  depends_on = [
    "helm_release.kube-lego",
  ]
}

resource "helm_release" "jenkins-ingress" {
  name  = "jenkins-ingress"
  chart = "stable/nginx-ingress"

  values = [<<EOF
rbac:
  create: true
controller:
  service:
    loadBalancerIP: ${google_compute_address.jenkins_address.address}
EOF
  ]

  depends_on = [
    "helm_release.kube-lego",
  ]
}

resource "kubernetes_namespace" "spinnaker-jenkins" {
  metadata {

//    labels {
//      istio-injection = "enabled"
//    }

    name = "spinnaker-jenkins"
  }

  depends_on = ["helm_release.spinnaker-ingress", "helm_release.jenkins-ingress"]
}

data "local_file" "spinnaker_values" {
  filename = "${path.module}/helm/spinnaker/values.yaml"
}

data "local_file" "jenkins_values" {
  filename = "${path.module}/helm/jenkins/values.yaml"
}

resource "helm_release" "spinnaker" {
  name = "spinnaker"
  namespace = "spinnaker-jenkins"

  timeout = 1000

  chart = "stable/spinnaker"

  values = ["${data.template_file.spinnaker_helm.rendered}"]

  depends_on = ["kubernetes_namespace.spinnaker-jenkins"]
}

resource "helm_release" "jenkins" {
  name = "jenkins"
  namespace = "spinnaker-jenkins"

  timeout = 600

  chart = "stable/jenkins"

  values = ["${data.template_file.jenkins_helm.rendered}"]

  depends_on = ["kubernetes_namespace.spinnaker-jenkins"]
}

