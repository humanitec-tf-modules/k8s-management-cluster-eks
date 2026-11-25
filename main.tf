data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "eks" {
  name = var.eks_cluster_name
}

# Random suffix for the generated IAM policy name. Created only if no name is passed in
resource "random_string" "iam_policy_name_suffix" {
  count = var.iam_policy_name == null ? 1 : 0

  length  = 4
  upper   = false
  numeric = false
  special = false
}

locals {
  # Cluster ARN format: arn:<partition>:eks:<region>:<account id>:cluster/<name>
  eks_region = split(":", data.aws_eks_cluster.eks.arn)[3]

  # Account ID, type ("role" or "user"), and name of the Cloud Account principal, parsed from its ARN
  cloud_account_principal = regex(local.iam_principal_arn_pattern, var.cloud_account_principal_arn)

  # AWS limits IAM policy names to 128 characters.
  # Truncate the prefix so the "-" separator and the full random suffix always fit.
  # EKS cluster names only contain characters that IAM allows in policy names, so no replacement is needed.
  iam_policy_name_max_length = 128
  iam_policy_name = var.iam_policy_name != null ? var.iam_policy_name : join("-", [
    substr("humanitec-orchestrator-eks-${var.eks_cluster_name}", 0, local.iam_policy_name_max_length - 5),
    random_string.iam_policy_name_suffix[0].result,
  ])

  # Driver input values for humanitec/k8s-cluster-eks. The child module drops null values so that the Driver defaults apply
  cluster_values = {
    loadbalancer             = var.loadbalancer
    loadbalancer_hosted_zone = var.loadbalancer_hosted_zone
    name                     = var.eks_cluster_name
    proxy_url                = var.proxy_url
    region                   = local.eks_region
  }

  # Helm chart values making the Operator assume an IAM role via IRSA. EKS Pod Identity requires no Helm values
  use_irsa = var.operator_irsa_role_arn != null
  irsa_helm_values = yamlencode({
    controllerManager = {
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = var.operator_irsa_role_arn
        }
      }
    }
  })

  # Helm merges values documents in order, so the values passed in come last to take precedence
  helm_release_values = local.use_irsa ? concat(
    [local.irsa_helm_values],
    var.helm_release_values != null ? var.helm_release_values : [],
  ) : var.helm_release_values

  # Patterns for IAM ARNs, also used by the variable validations
  iam_principal_arn_pattern = "^arn:aws[a-z-]*:iam::(?P<account_id>[0-9]{12}):(?P<type>role|user)/(?:[^/]+/)*(?P<name>[\\w+=,.@-]+)$"
  iam_role_arn_pattern      = "^arn:aws[a-z-]*:iam::[0-9]{12}:role/(?:[^/]+/)*[\\w+=,.@-]+$"
}

# IAM policy granting access to the EKS cluster
# See https://developer.humanitec.com/platform-orchestrator/docs/integration-and-extensions/containerization/kubernetes/#eks
data "aws_iam_policy_document" "orchestrator_cluster_access" {
  version = "2012-10-17"
  statement {
    sid    = "EksClusterAccess"
    effect = "Allow"
    actions = [
      "eks:AccessKubernetesApi",
      "eks:DescribeCluster",
      "eks:ListNodegroups",
    ]
    resources = [data.aws_eks_cluster.eks.arn]
  }
}

resource "aws_iam_policy" "orchestrator_cluster_access" {
  name        = local.iam_policy_name
  path        = var.iam_policy_path
  description = "Humanitec Orchestrator access to the EKS cluster ${var.eks_cluster_name} in ${local.eks_region}"
  policy      = data.aws_iam_policy_document.orchestrator_cluster_access.json
  tags        = var.iam_policy_tags
}

# Attach the policy to the IAM role or user behind the Cloud Account. Exactly one of the two attachments is created
resource "aws_iam_role_policy_attachment" "orchestrator_cluster_access" {
  count = local.cloud_account_principal.type == "role" ? 1 : 0

  role       = local.cloud_account_principal.name
  policy_arn = aws_iam_policy.orchestrator_cluster_access.arn

  lifecycle {
    precondition {
      condition     = local.cloud_account_principal.account_id == data.aws_caller_identity.current.account_id
      error_message = "cloud_account_principal_arn must be located in the account of the aws provider (${data.aws_caller_identity.current.account_id})."
    }
  }
}

resource "aws_iam_user_policy_attachment" "orchestrator_cluster_access" {
  count = local.cloud_account_principal.type == "user" ? 1 : 0

  user       = local.cloud_account_principal.name
  policy_arn = aws_iam_policy.orchestrator_cluster_access.arn

  lifecycle {
    precondition {
      condition     = local.cloud_account_principal.account_id == data.aws_caller_identity.current.account_id
      error_message = "cloud_account_principal_arn must be located in the account of the aws provider (${data.aws_caller_identity.current.account_id})."
    }
  }
}

# Access entry mapping the Cloud Account principal to a Kubernetes group.
# Least privilege: no access policy is associated, as none of the predefined access policies meet the requirements.
# The child module binds the ClusterRole with the required permissions to the Kubernetes group instead.
resource "aws_eks_access_entry" "orchestrator" {
  cluster_name      = var.eks_cluster_name
  principal_arn     = var.cloud_account_principal_arn
  type              = "STANDARD"
  kubernetes_groups = [var.access_entry_kubernetes_group]
  tags              = var.access_entry_tags

  lifecycle {
    precondition {
      condition     = contains(["API", "API_AND_CONFIG_MAP"], try(data.aws_eks_cluster.eks.access_config[0].authentication_mode, ""))
      error_message = "The authentication mode of the EKS cluster ${var.eks_cluster_name} must be API or API_AND_CONFIG_MAP to support access entries."
    }
  }
}

module "management_cluster" {
  source = "github.com/humanitec-tf-modules/k8s-management-cluster?ref=v1.0.0"

  driver_type                 = "humanitec/k8s-cluster-eks"
  cluster_access_subject_kind = "Group"
  # Referencing the access entry makes the ClusterRoleBinding, and therefore the Resource Definition, depend on it
  cluster_access_subject_name = one(aws_eks_access_entry.orchestrator.kubernetes_groups)
  cluster_values              = local.cluster_values

  # Pass-through variables
  resource_definition_id                  = var.resource_definition_id
  resource_definition_id_prefix           = var.resource_definition_id_prefix
  resource_definition_name                = var.resource_definition_name
  resource_definition_criteria            = var.resource_definition_criteria
  cloud_account_id                        = var.cloud_account_id
  enable_agent                            = var.enable_agent
  cluster_role_name                       = var.cluster_role_name
  cluster_secrets                         = var.cluster_secrets
  humanitec_org_id                        = var.humanitec_org_id
  enable_driver_authentication            = var.enable_driver_authentication
  operator_private_key                    = var.operator_private_key
  operator_public_key                     = var.operator_public_key
  helm_release_namespace                  = var.helm_release_namespace
  helm_release_create_namespace           = var.helm_release_create_namespace
  helm_release_name                       = var.helm_release_name
  helm_release_version                    = var.helm_release_version
  helm_release_repository                 = var.helm_release_repository
  helm_release_chart                      = var.helm_release_chart
  helm_release_atomic                     = var.helm_release_atomic
  helm_release_cleanup_on_fail            = var.helm_release_cleanup_on_fail
  helm_release_dependency_update          = var.helm_release_dependency_update
  helm_release_description                = var.helm_release_description
  helm_release_devel                      = var.helm_release_devel
  helm_release_disable_crd_hooks          = var.helm_release_disable_crd_hooks
  helm_release_disable_openapi_validation = var.helm_release_disable_openapi_validation
  helm_release_disable_webhooks           = var.helm_release_disable_webhooks
  helm_release_force_update               = var.helm_release_force_update
  helm_release_keyring                    = var.helm_release_keyring
  helm_release_lint                       = var.helm_release_lint
  helm_release_max_history                = var.helm_release_max_history
  helm_release_pass_credentials           = var.helm_release_pass_credentials
  helm_release_postrender                 = var.helm_release_postrender
  helm_release_recreate_pods              = var.helm_release_recreate_pods
  helm_release_render_subchart_notes      = var.helm_release_render_subchart_notes
  helm_release_replace                    = var.helm_release_replace
  helm_release_repository_ca_file         = var.helm_release_repository_ca_file
  helm_release_repository_cert_file       = var.helm_release_repository_cert_file
  helm_release_repository_key_file        = var.helm_release_repository_key_file
  helm_release_repository_password        = var.helm_release_repository_password
  helm_release_repository_username        = var.helm_release_repository_username
  helm_release_reset_values               = var.helm_release_reset_values
  helm_release_reuse_values               = var.helm_release_reuse_values
  helm_release_set                        = var.helm_release_set
  helm_release_set_wo                     = var.helm_release_set_wo
  helm_release_set_wo_revision            = var.helm_release_set_wo_revision
  helm_release_set_list                   = var.helm_release_set_list
  helm_release_set_sensitive              = var.helm_release_set_sensitive
  helm_release_skip_crds                  = var.helm_release_skip_crds
  helm_release_take_ownership             = var.helm_release_take_ownership
  helm_release_timeout                    = var.helm_release_timeout
  helm_release_upgrade_install            = var.helm_release_upgrade_install
  helm_release_values                     = local.helm_release_values
  helm_release_verify                     = var.helm_release_verify
  helm_release_wait                       = var.helm_release_wait
  helm_release_wait_for_jobs              = var.helm_release_wait_for_jobs
}
