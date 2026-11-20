output "iam_policy_arn" {
  description = "ARN of the IAM policy granting the Cloud Account principal access to the cluster."
  value       = aws_iam_policy.orchestrator_cluster_access.arn
}

output "iam_policy_name" {
  description = "Name of the IAM policy granting the Cloud Account principal access to the cluster."
  value       = aws_iam_policy.orchestrator_cluster_access.name
}

output "access_entry_arn" {
  description = "ARN of the EKS access entry mapping the Cloud Account principal to the Kubernetes group `access_entry_kubernetes_group`."
  value       = aws_eks_access_entry.orchestrator.access_entry_arn
}

output "eks_cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = data.aws_eks_cluster.eks.arn
}

# Outputs passed through from the management-cluster-k8s module
output "operator_public_key" {
  description = "Public key of the Operator in PEM format. `null` if `enable_driver_authentication` is `false`."
  value       = module.management_cluster.operator_public_key
}
output "operator_private_key" {
  description = "Private key of the Operator in PEM format. `null` if `enable_driver_authentication` is `false`."
  value       = module.management_cluster.operator_private_key
  sensitive   = true
}
output "operator_public_key_id" {
  description = "ID of the public key registered in the Humanitec Organization. `null` if `enable_driver_authentication` is `false`."
  value       = module.management_cluster.operator_public_key_id
}
output "operator_public_key_fingerprint" {
  description = "Fingerprint (SHA256 hash of the DER representation) of the public key registered in the Humanitec Organization. Use it to debug authentication against Humanitec-hosted Drivers. `null` if `enable_driver_authentication` is `false`."
  value       = module.management_cluster.operator_public_key_fingerprint
}
output "operator_private_key_secret_name" {
  description = "Name of the Kubernetes Secret holding the private key of the Operator. `null` if `enable_driver_authentication` is `false`."
  value       = module.management_cluster.operator_private_key_secret_name
}
output "helm_release_namespace" {
  description = "Kubernetes namespace where the Operator is installed"
  value       = module.management_cluster.helm_release_namespace
}
output "helm_release_name" {
  description = "Name of the Helm release for the Operator"
  value       = module.management_cluster.helm_release_name
}
output "helm_release_version" {
  description = "Chart version used for the Operator installation"
  value       = module.management_cluster.helm_release_version
}
output "helm_release_repository" {
  description = "Repository used for the Operator Helm chart"
  value       = module.management_cluster.helm_release_repository
}
output "helm_release_chart" {
  description = "Chart name used for the Operator Helm chart"
  value       = module.management_cluster.helm_release_chart
}
output "resource_definition_id" {
  description = "ID of the Resource Definition of type `k8s-cluster` representing the cluster"
  value       = module.management_cluster.resource_definition_id
}
output "resource_definition_driver_type" {
  description = "Driver type of the Resource Definition"
  value       = module.management_cluster.resource_definition_driver_type
}
output "cluster_role_name" {
  description = "Name of the Kubernetes ClusterRole granting the Orchestrator access to the cluster"
  value       = module.management_cluster.cluster_role_name
}
output "cluster_role_binding_name" {
  description = "Name of the Kubernetes ClusterRoleBinding granting the Orchestrator access to the cluster"
  value       = module.management_cluster.cluster_role_binding_name
}
output "cluster_access_subject" {
  description = "Subject of the Kubernetes ClusterRoleBinding, i.e. the identity the Orchestrator uses to access the cluster, as an object with the attributes `kind` and `name`"
  value       = module.management_cluster.cluster_access_subject
}
