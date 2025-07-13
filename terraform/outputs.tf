output "ecs_cluster_name" {
  value = aws_ecs_cluster.medusa_cluster.name
}

output "ecs_service_name" {
  value = aws_ecs_service.medusa_service.name
}

output "ecs_task_family" {
  value = aws_ecs_task_definition.medusa_task.family
}

output "ecr_repo_url" {
  value = aws_ecr_repository.medusa_repo.repository_url
}
