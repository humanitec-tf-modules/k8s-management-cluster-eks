# Verifies the Helm chart values making the Operator use IRSA, and their merging with values passed in.
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

run "omits_irsa_values_by_default" {
  command = plan

  assert {
    condition     = local.helm_release_values == null
    error_message = "No Helm values must be set if operator_irsa_role_arn is not set and no values are passed in"
  }
}

run "passes_values_through_without_irsa" {
  command = plan

  variables {
    helm_release_values = [yamlencode({ foo = "bar" })]
  }

  assert {
    condition     = local.helm_release_values == tolist(var.helm_release_values)
    error_message = "The values passed in must be used unchanged if operator_irsa_role_arn is not set"
  }
}

run "adds_irsa_values" {
  command = plan

  variables {
    operator_irsa_role_arn = "arn:aws:iam::123456789012:role/humanitec-operator"
  }

  assert {
    condition     = length(local.helm_release_values) == 1
    error_message = "Only the IRSA values must be set if no values are passed in"
  }

  assert {
    condition     = yamldecode(local.helm_release_values[0]).controllerManager.serviceAccount.annotations["eks.amazonaws.com/role-arn"] == "arn:aws:iam::123456789012:role/humanitec-operator"
    error_message = "The service account annotation must hold the IAM role ARN"
  }
}

run "merges_irsa_values_with_values_passed_in" {
  command = plan

  variables {
    operator_irsa_role_arn = "arn:aws:iam::123456789012:role/humanitec-operator"
    helm_release_values = [
      yamlencode({ controllerManager = { podLabels = { team = "platform" } } }),
      yamlencode({ foo = "bar" }),
    ]
  }

  assert {
    condition     = length(local.helm_release_values) == 3
    error_message = "The IRSA values and all values passed in must be set"
  }

  assert {
    condition     = yamldecode(local.helm_release_values[0]).controllerManager.serviceAccount.annotations["eks.amazonaws.com/role-arn"] == "arn:aws:iam::123456789012:role/humanitec-operator"
    error_message = "The IRSA values must come first so that the values passed in take precedence"
  }

  assert {
    condition     = slice(local.helm_release_values, 1, 3) == tolist(var.helm_release_values)
    error_message = "The values passed in must follow the IRSA values in their original order"
  }
}

run "rejects_non_role_arn" {
  command = plan

  variables {
    operator_irsa_role_arn = "arn:aws:iam::123456789012:user/humanitec-operator"
  }

  expect_failures = [var.operator_irsa_role_arn]
}
