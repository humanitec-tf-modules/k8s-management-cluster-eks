# Verifies the inputs this module sets on the management-cluster-k8s module, and that variables are passed through.
#
# All providers are mocked, so these tests run without AWS credentials, a Kubernetes cluster, or a Humanitec Organization.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_eks_cluster" {
    defaults = {
      arn = "arn:aws:eks:eu-central-1:123456789012:cluster/my-eks"
      access_config = [{
        authentication_mode                         = "API_AND_CONFIG_MAP"
        bootstrap_cluster_creator_admin_permissions = false
      }]
    }
  }
  # The mocked policy document does not render its statements
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\"}"
    }
  }
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/my-policy"
    }
  }
  mock_resource "aws_eks_access_entry" {
    defaults = {
      access_entry_arn = "arn:aws:eks:eu-central-1:123456789012:access-entry/my-eks/role/123456789012/humanitec-orchestrator/00000000-0000-0000-0000-000000000000"
    }
  }
}

mock_provider "random" {
  # The mocked result does not honor the length attribute
  mock_resource "random_string" {
    defaults = {
      result = "abcd"
    }
  }
}

mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "humanitec" {}
mock_provider "tls" {}

variables {
  eks_cluster_name            = "my-eks"
  cloud_account_principal_arn = "arn:aws:iam::123456789012:role/humanitec-orchestrator"
  cloud_account_id            = "my-aws-cloud-account"

  # terraform test sets the default of an ephemeral root variable only during apply, failing the apply. Set it explicitly
  helm_release_set_wo = []
}

run "sets_fixed_eks_inputs" {
  command = apply

  assert {
    condition     = module.management_cluster.resource_definition_driver_type == "humanitec/k8s-cluster-eks"
    error_message = "The Driver must be humanitec/k8s-cluster-eks"
  }

  assert {
    condition     = startswith(module.management_cluster.resource_definition_id, "management-cluster-eks-")
    error_message = "The generated Resource Definition ID must use the default prefix management-cluster-eks"
  }

  assert {
    condition     = module.management_cluster.cluster_access_subject.kind == "Group"
    error_message = "The cluster access subject must be a Group"
  }

  assert {
    condition     = module.management_cluster.cluster_access_subject.name == "humanitec-platform-orchestrator"
    error_message = "The cluster access subject must be the Kubernetes group of the access entry"
  }

  assert {
    condition     = toset(keys(local.cluster_values)) == toset(["loadbalancer", "loadbalancer_hosted_zone", "name", "proxy_url", "region"])
    error_message = "The cluster values must have exactly the keys loadbalancer, loadbalancer_hosted_zone, name, proxy_url, region"
  }

  assert {
    condition     = local.cluster_values.loadbalancer == null && local.cluster_values.loadbalancer_hosted_zone == null && local.cluster_values.proxy_url == null
    error_message = "The optional cluster values must be null by default so that the Driver defaults apply"
  }

  assert {
    condition     = local.cluster_values.name == "my-eks"
    error_message = "The name cluster value must be the EKS cluster name"
  }

  assert {
    condition     = local.cluster_values.region == "eu-central-1"
    error_message = "The region cluster value must be the region of the EKS cluster"
  }
}

run "sets_optional_values_and_custom_group" {
  command = apply

  variables {
    loadbalancer                  = "my-lb.elb.eu-central-1.amazonaws.com"
    loadbalancer_hosted_zone      = "ABC0DEF5WYYZ00"
    proxy_url                     = "http://proxy.example.com:3128"
    access_entry_kubernetes_group = "my-group"
  }

  assert {
    condition     = local.cluster_values.loadbalancer == "my-lb.elb.eu-central-1.amazonaws.com"
    error_message = "The loadbalancer cluster value must be taken from the loadbalancer variable"
  }

  assert {
    condition     = local.cluster_values.loadbalancer_hosted_zone == "ABC0DEF5WYYZ00"
    error_message = "The loadbalancer_hosted_zone cluster value must be taken from the loadbalancer_hosted_zone variable"
  }

  assert {
    condition     = local.cluster_values.proxy_url == "http://proxy.example.com:3128"
    error_message = "The proxy_url cluster value must be taken from the proxy_url variable"
  }

  assert {
    condition     = module.management_cluster.cluster_access_subject.name == "my-group"
    error_message = "The cluster access subject must be the custom Kubernetes group"
  }
}

run "passes_through_variables" {
  command = apply

  variables {
    resource_definition_id       = "my-cluster"
    cluster_role_name            = "my-deploy-access"
    helm_release_name            = "my-operator"
    helm_release_namespace       = "my-namespace"
    helm_release_version         = "1.2.3"
    helm_release_repository      = "oci://example.com/charts"
    helm_release_chart           = "my-chart"
    enable_driver_authentication = true
    humanitec_org_id             = "my-org"
  }

  assert {
    condition     = module.management_cluster.resource_definition_id == "my-cluster"
    error_message = "resource_definition_id must be passed through"
  }

  assert {
    condition     = module.management_cluster.cluster_role_name == "my-deploy-access"
    error_message = "cluster_role_name must be passed through"
  }

  assert {
    condition     = module.management_cluster.helm_release_name == "my-operator"
    error_message = "helm_release_name must be passed through"
  }

  assert {
    condition     = module.management_cluster.helm_release_namespace == "my-namespace"
    error_message = "helm_release_namespace must be passed through"
  }

  assert {
    condition     = module.management_cluster.helm_release_version == "1.2.3"
    error_message = "helm_release_version must be passed through"
  }

  assert {
    condition     = module.management_cluster.helm_release_repository == "oci://example.com/charts"
    error_message = "helm_release_repository must be passed through"
  }

  assert {
    condition     = module.management_cluster.helm_release_chart == "my-chart"
    error_message = "helm_release_chart must be passed through"
  }

  assert {
    condition     = module.management_cluster.operator_private_key_secret_name == "humanitec-operator-private-key"
    error_message = "enable_driver_authentication must be passed through"
  }
}

run "passes_through_resource_definition_id_prefix" {
  command = apply

  variables {
    resource_definition_id_prefix = "my-prefix"
  }

  assert {
    condition     = can(regex("^my-prefix-[a-z0-9]{4}$", module.management_cluster.resource_definition_id))
    error_message = "resource_definition_id_prefix must be passed through"
  }
}

run "passes_through_outputs" {
  command = apply

  # Enable driver authentication and set a chart version so that all outputs have non-null values
  variables {
    enable_driver_authentication = true
    humanitec_org_id             = "my-org"
    helm_release_version         = "1.2.3"
  }

  assert {
    condition     = alltrue([for v in [output.operator_public_key, output.operator_private_key, output.operator_public_key_id, output.operator_public_key_fingerprint, output.operator_private_key_secret_name, output.helm_release_version] : v != null])
    error_message = "The operator and chart version outputs must not be null when driver authentication is enabled"
  }

  assert {
    condition     = output.operator_public_key == module.management_cluster.operator_public_key
    error_message = "Output operator_public_key must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.operator_private_key == module.management_cluster.operator_private_key
    error_message = "Output operator_private_key must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.operator_public_key_id == module.management_cluster.operator_public_key_id
    error_message = "Output operator_public_key_id must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.operator_public_key_fingerprint == module.management_cluster.operator_public_key_fingerprint
    error_message = "Output operator_public_key_fingerprint must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.operator_private_key_secret_name == module.management_cluster.operator_private_key_secret_name
    error_message = "Output operator_private_key_secret_name must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.helm_release_namespace == module.management_cluster.helm_release_namespace
    error_message = "Output helm_release_namespace must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.helm_release_name == module.management_cluster.helm_release_name
    error_message = "Output helm_release_name must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.helm_release_version == module.management_cluster.helm_release_version
    error_message = "Output helm_release_version must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.helm_release_repository == module.management_cluster.helm_release_repository
    error_message = "Output helm_release_repository must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.helm_release_chart == module.management_cluster.helm_release_chart
    error_message = "Output helm_release_chart must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.resource_definition_id == module.management_cluster.resource_definition_id
    error_message = "Output resource_definition_id must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.resource_definition_driver_type == module.management_cluster.resource_definition_driver_type
    error_message = "Output resource_definition_driver_type must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.cluster_role_name == module.management_cluster.cluster_role_name
    error_message = "Output cluster_role_name must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.cluster_role_binding_name == module.management_cluster.cluster_role_binding_name
    error_message = "Output cluster_role_binding_name must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.cluster_access_subject == module.management_cluster.cluster_access_subject
    error_message = "Output cluster_access_subject must be passed through from the management-cluster-k8s module"
  }
}
