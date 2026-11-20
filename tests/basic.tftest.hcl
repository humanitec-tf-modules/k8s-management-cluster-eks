# See https://developer.hashicorp.com/terraform/language/tests for more on how to write tests.
# See https://developer.hashicorp.com/terraform/language/tests/mocking for information on mocking providers.
#
# All providers are mocked, so these tests run without AWS credentials and create no real infrastructure.

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

run "creates_aws_objects_with_defaults" {
  command = apply

  # IAM policy
  assert {
    condition     = aws_iam_policy.orchestrator_cluster_access.name == "humanitec-orchestrator-eks-my-eks-abcd"
    error_message = "The IAM policy name must be generated as humanitec-orchestrator-eks-<cluster name>-<suffix>, got ${aws_iam_policy.orchestrator_cluster_access.name}"
  }

  assert {
    condition     = aws_iam_policy.orchestrator_cluster_access.path == null && aws_iam_policy.orchestrator_cluster_access.tags == null
    error_message = "The IAM policy must have no custom path and no tags by default"
  }

  assert {
    condition     = aws_iam_policy.orchestrator_cluster_access.description == "Humanitec Orchestrator access to the EKS cluster my-eks in eu-central-1"
    error_message = "The IAM policy description must name the cluster and its region"
  }

  assert {
    condition     = aws_iam_policy.orchestrator_cluster_access.policy == data.aws_iam_policy_document.orchestrator_cluster_access.json
    error_message = "The IAM policy must use the cluster access policy document"
  }

  assert {
    condition = toset(data.aws_iam_policy_document.orchestrator_cluster_access.statement[0].actions) == toset([
      "eks:AccessKubernetesApi",
      "eks:DescribeCluster",
      "eks:ListNodegroups",
    ])
    error_message = "The IAM policy must allow exactly the EKS actions required by the Orchestrator"
  }

  assert {
    condition     = toset(data.aws_iam_policy_document.orchestrator_cluster_access.statement[0].resources) == toset(["arn:aws:eks:eu-central-1:123456789012:cluster/my-eks"])
    error_message = "The IAM policy must be scoped to the cluster ARN"
  }

  # Policy attachment
  assert {
    condition     = length(aws_iam_role_policy_attachment.orchestrator_cluster_access) == 1 && length(aws_iam_user_policy_attachment.orchestrator_cluster_access) == 0
    error_message = "Only the role policy attachment must be created for an IAM role principal"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.orchestrator_cluster_access[0].role == "humanitec-orchestrator"
    error_message = "The IAM policy must be attached to the Cloud Account role"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.orchestrator_cluster_access[0].policy_arn == "arn:aws:iam::123456789012:policy/my-policy"
    error_message = "The attachment must reference the created IAM policy"
  }

  # Access entry
  assert {
    condition     = aws_eks_access_entry.orchestrator.cluster_name == "my-eks"
    error_message = "The access entry must be created on the cluster"
  }

  assert {
    condition     = aws_eks_access_entry.orchestrator.principal_arn == "arn:aws:iam::123456789012:role/humanitec-orchestrator"
    error_message = "The access entry must be created for the Cloud Account principal"
  }

  assert {
    condition     = aws_eks_access_entry.orchestrator.type == "STANDARD"
    error_message = "The access entry must be of type STANDARD"
  }

  assert {
    condition     = toset(aws_eks_access_entry.orchestrator.kubernetes_groups) == toset(["humanitec-platform-orchestrator"])
    error_message = "The access entry must map the principal to the Kubernetes group humanitec-platform-orchestrator by default"
  }

  assert {
    condition     = aws_eks_access_entry.orchestrator.tags == null
    error_message = "The access entry must have no tags by default"
  }

  # Outputs
  assert {
    condition     = output.iam_policy_arn == "arn:aws:iam::123456789012:policy/my-policy"
    error_message = "The iam_policy_arn output must be the ARN of the IAM policy"
  }

  assert {
    condition     = output.iam_policy_name == "humanitec-orchestrator-eks-my-eks-abcd"
    error_message = "The iam_policy_name output must be the name of the IAM policy"
  }

  assert {
    condition     = output.access_entry_arn == aws_eks_access_entry.orchestrator.access_entry_arn
    error_message = "The access_entry_arn output must be the ARN of the access entry"
  }

  assert {
    condition     = output.eks_cluster_arn == "arn:aws:eks:eu-central-1:123456789012:cluster/my-eks"
    error_message = "The eks_cluster_arn output must be the ARN of the cluster"
  }
}

run "attaches_policy_to_role_with_path" {
  command = apply

  variables {
    cloud_account_principal_arn = "arn:aws:iam::123456789012:role/humanitec/orchestrator/my-role"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.orchestrator_cluster_access[0].role == "my-role"
    error_message = "The IAM policy must be attached to the role name without its path"
  }

  assert {
    condition     = aws_eks_access_entry.orchestrator.principal_arn == "arn:aws:iam::123456789012:role/humanitec/orchestrator/my-role"
    error_message = "The access entry must use the full role ARN"
  }
}

run "attaches_policy_to_user" {
  command = apply

  variables {
    cloud_account_principal_arn = "arn:aws:iam::123456789012:user/humanitec/my-user"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.orchestrator_cluster_access) == 0 && length(aws_iam_user_policy_attachment.orchestrator_cluster_access) == 1
    error_message = "Only the user policy attachment must be created for an IAM user principal"
  }

  assert {
    condition     = aws_iam_user_policy_attachment.orchestrator_cluster_access[0].user == "my-user"
    error_message = "The IAM policy must be attached to the user name without its path"
  }

  assert {
    condition     = aws_iam_user_policy_attachment.orchestrator_cluster_access[0].policy_arn == "arn:aws:iam::123456789012:policy/my-policy"
    error_message = "The attachment must reference the created IAM policy"
  }

  assert {
    condition     = aws_eks_access_entry.orchestrator.principal_arn == "arn:aws:iam::123456789012:user/humanitec/my-user"
    error_message = "The access entry must be created for the Cloud Account user"
  }
}

run "uses_custom_settings" {
  command = apply

  variables {
    iam_policy_name               = "my-policy"
    iam_policy_path               = "/humanitec/"
    iam_policy_tags               = { team = "platform" }
    access_entry_kubernetes_group = "my-group"
    access_entry_tags             = { team = "platform" }
  }

  assert {
    condition     = length(random_string.iam_policy_name_suffix) == 0
    error_message = "No random suffix must be created if a policy name is passed in"
  }

  assert {
    condition     = aws_iam_policy.orchestrator_cluster_access.name == "my-policy"
    error_message = "The IAM policy must use the name passed in"
  }

  assert {
    condition     = aws_iam_policy.orchestrator_cluster_access.path == "/humanitec/"
    error_message = "The IAM policy must use the path passed in"
  }

  assert {
    condition     = aws_iam_policy.orchestrator_cluster_access.tags == tomap({ team = "platform" })
    error_message = "The IAM policy must use the tags passed in"
  }

  assert {
    condition     = toset(aws_eks_access_entry.orchestrator.kubernetes_groups) == toset(["my-group"])
    error_message = "The access entry must use the Kubernetes group passed in"
  }

  assert {
    condition     = aws_eks_access_entry.orchestrator.tags == tomap({ team = "platform" })
    error_message = "The access entry must use the tags passed in"
  }
}

run "truncates_generated_policy_name" {
  command = apply

  variables {
    # EKS allows cluster names of up to 100 characters
    eks_cluster_name = "c${join("", [for i in range(99) : "x"])}"
  }

  assert {
    condition     = length(aws_iam_policy.orchestrator_cluster_access.name) == 128
    error_message = "The generated IAM policy name must be truncated to 128 characters, got ${length(aws_iam_policy.orchestrator_cluster_access.name)}"
  }

  assert {
    condition     = endswith(aws_iam_policy.orchestrator_cluster_access.name, "x-abcd")
    error_message = "The generated IAM policy name must keep the full random suffix"
  }
}

run "rejects_principal_in_other_account" {
  command = plan

  variables {
    cloud_account_principal_arn = "arn:aws:iam::999999999999:role/humanitec-orchestrator"
  }

  expect_failures = [aws_iam_role_policy_attachment.orchestrator_cluster_access]
}

run "rejects_cluster_without_access_entries" {
  command = plan

  override_data {
    target = data.aws_eks_cluster.eks
    values = {
      arn = "arn:aws:eks:eu-central-1:123456789012:cluster/my-eks"
      access_config = [{
        authentication_mode                         = "CONFIG_MAP"
        bootstrap_cluster_creator_admin_permissions = false
      }]
    }
  }

  expect_failures = [aws_eks_access_entry.orchestrator]
}

run "rejects_empty_cluster_name" {
  command = plan

  variables {
    eks_cluster_name = " "
  }

  expect_failures = [var.eks_cluster_name]
}

run "rejects_assumed_role_arn" {
  command = plan

  variables {
    cloud_account_principal_arn = "arn:aws:sts::123456789012:assumed-role/humanitec-orchestrator/session"
  }

  expect_failures = [var.cloud_account_principal_arn]
}

run "rejects_system_kubernetes_group" {
  command = plan

  variables {
    access_entry_kubernetes_group = "system:masters"
  }

  expect_failures = [var.access_entry_kubernetes_group]
}

run "rejects_empty_kubernetes_group" {
  command = plan

  variables {
    access_entry_kubernetes_group = ""
  }

  expect_failures = [var.access_entry_kubernetes_group]
}

run "rejects_invalid_policy_name" {
  command = plan

  variables {
    iam_policy_name = "my policy"
  }

  expect_failures = [var.iam_policy_name]
}

run "rejects_invalid_policy_path" {
  command = plan

  variables {
    iam_policy_path = "humanitec"
  }

  expect_failures = [var.iam_policy_path]
}
