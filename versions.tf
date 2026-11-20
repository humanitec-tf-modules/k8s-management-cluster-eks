terraform {
  # The management-cluster-k8s child module requires >= 1.11.0 for write-only attributes
  required_version = ">= 1.11.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    # EKS access entries require >= 5.33.0
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.34.0, < 7.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3"
    }
    humanitec = {
      source  = "humanitec/humanitec"
      version = "~> 1.9"
    }
  }
}
