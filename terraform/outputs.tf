# Output values that will be useful for monitoring and connecting to your infrastructure

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.medusa_alb.dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the load balancer"
  value       = aws_lb.medusa_alb.zone_id
}

output "medusa_url" {
  description = "URL to access Medusa application"
  value       = var.certificate_arn != "" ? "https://${aws_lb.medusa_alb.dns_name}" : "http://${aws_lb.medusa_alb.dns_name}"
}

output "medusa_admin_url" {
  description = "URL to access Medusa Admin dashboard"
  value       = var.certificate_arn != "" ? "https://${aws_lb.medusa_alb.dns_name}/app" : "http://${aws_lb.medusa_alb.dns_name}/app"
}

output "database_endpoint" {
  description = "PostgreSQL database endpoint"
  value       = aws_db_instance.medusa_postgres.endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "Redis cache endpoint"
  value       = aws_elasticache_cluster.medusa_redis.cache_nodes[0].address
  sensitive   = true
}

output "s3_bucket_name" {
  description = "S3 bucket name for file storage"
  value       = aws_s3_bucket.medusa_files.bucket
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.medusa_cluster.name
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.medusa_vpc.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private_subnets[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public_subnets[*].id
}
