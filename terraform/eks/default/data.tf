data "aws_eks_cluster_auth" "this" {
  name = module.retail_app_eks.eks_cluster_id

  depends_on = [
    null_resource.cluster_blocker
  ]
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.retail_app_eks.eks_cluster_id

  depends_on = [
    null_resource.cluster_blocker
  ]
}

data "kubernetes_ingress_v1" "ui_ingress" {
  depends_on = [helm_release.ui]

  metadata {
    name      = "ui"
    namespace = "ui"
  }
}