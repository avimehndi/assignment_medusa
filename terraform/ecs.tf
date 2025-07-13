# ECS Cluster - Container orchestration service
resource "aws_ecs_cluster" "medusa_cluster" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "${var.project_name}-cluster"
    Environment = var.environment
  }
}

# ECS Cluster Capacity Providers - Use Fargate for serverless containers
resource "aws_ecs_cluster_capacity_providers" "medusa_cluster_capacity_providers" {
  cluster_name = aws_ecs_cluster.medusa_cluster.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# CloudWatch Log Group for ECS tasks
resource "aws_cloudwatch_log_group" "medusa_log_group" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-log-group"
    Environment = var.environment
  }
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.project_name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-ecs-execution-role"
    Environment = var.environment
  }
}

# IAM Role for ECS Task (application permissions)
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-ecs-task-role"
    Environment = var.environment
  }
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Custom IAM policy for ECS task (S3 access, Secrets Manager, etc.)
resource "aws_iam_role_policy" "ecs_task_policy" {
  name = "${var.project_name}-ecs-task-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.medusa_files.arn,
          "${aws_s3_bucket.medusa_files.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.db_password.arn
        ]
      }
    ]
  })
}

# Generate secure secrets for Medusa
resource "random_password" "cookie_secret" {
  length  = 32
  special = true
}

resource "random_password" "jwt_secret" {
  length  = 32
  special = true
}

# ECS Task Definition for Medusa Server
resource "aws_ecs_task_definition" "medusa_server" {
  family                   = "${var.project_name}-server"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.medusa_server_cpu
  memory                   = var.medusa_server_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "medusa-server"
      image = "medusajs/medusa:${var.medusa_image_tag}"
      
      portMappings = [
        {
          containerPort = 9000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        },
        {
          name  = "MEDUSA_WORKER_MODE"
          value = "server"
        },
        {
          name  = "DISABLE_MEDUSA_ADMIN"
          value = "false"
        },
        {
          name  = "PORT"
          value = "9000"
        },
        {
          name  = "COOKIE_SECRET"
          value = random_password.cookie_secret.result
        },
        {
          name  = "JWT_SECRET"
          value = random_password.jwt_secret.result
        },
        {
          name  = "DATABASE_URL"
          value = "postgresql://${aws_db_instance.medusa_postgres.username}:${random_password.db_password.result}@${aws_db_instance.medusa_postgres.endpoint}/${aws_db_instance.medusa_postgres.db_name}"
        },
        {
          name  = "REDIS_URL"
          value = "redis://${aws_elasticache_cluster.medusa_redis.cache_nodes[0].address}:${aws_elasticache_cluster.medusa_redis.cache_nodes[0].port}"
        },
        {
          name  = "STORE_CORS"
          value = "https://${aws_lb.medusa_alb.dns_name}"
        },
        {
          name  = "ADMIN_CORS"
          value = "https://${aws_lb.medusa_alb.dns_name}"
        },
        {
          name  = "AUTH_CORS"
          value = "https://${aws_lb.medusa_alb.dns_name}"
        },
        {
          name  = "MEDUSA_BACKEND_URL"
          value = "https://${aws_lb.medusa_alb.dns_name}"
        },
        {
          name  = "AWS_S3_BUCKET_NAME"
          value = aws_s3_bucket.medusa_files.bucket
        },
        {
          name  = "AWS_S3_REGION"
          value = var.aws_region
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.medusa_log_group.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "medusa-server"
        }
      }

      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost:9000/health || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 120
      }

      essential = true
    }
  ])

  tags = {
    Name        = "${var.project_name}-server-task"
    Environment = var.environment
  }
}

# ECS Task Definition for Medusa Worker
resource "aws_ecs_task_definition" "medusa_worker" {
  family                   = "${var.project_name}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.medusa_worker_cpu
  memory                   = var.medusa_worker_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "medusa-worker"
      image = "medusajs/medusa:${var.medusa_image_tag}"

      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        },
        {
          name  = "MEDUSA_WORKER_MODE"
          value = "worker"
        },
        {
          name  = "DISABLE_MEDUSA_ADMIN"
          value = "true"
        },
        {
          name  = "COOKIE_SECRET"
          value = random_password.cookie_secret.result
        },
        {
          name  = "JWT_SECRET"
          value = random_password.jwt_secret.result
        },
        {
          name  = "DATABASE_URL"
          value = "postgresql://${aws_db_instance.medusa_postgres.username}:${random_password.db_password.result}@${aws_db_instance.medusa_postgres.endpoint}/${aws_db_instance.medusa_postgres.db_name}"
        },
        {
          name  = "REDIS_URL"
          value = "redis://${aws_elasticache_cluster.medusa_redis.cache_nodes[0].address}:${aws_elasticache_cluster.medusa_redis.cache_nodes[0].port}"
        },
        {
          name  = "AWS_S3_BUCKET_NAME"
          value = aws_s3_bucket.medusa_files.bucket
        },
        {
          name  = "AWS_S3_REGION"
          value = var.aws_region
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.medusa_log_group.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "medusa-worker"
        }
      }

      essential = true
    }
  ])

  tags = {
    Name        = "${var.project_name}-worker-task"
    Environment = var.environment
  }
}

# ECS Service for Medusa Server
resource "aws_ecs_service" "medusa_server_service" {
  name            = "${var.project_name}-server-service"
  cluster         = aws_ecs_cluster.medusa_cluster.id
  task_definition = aws_ecs_task_definition.medusa_server.arn
  desired_count   = var.desired_count_server
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private_subnets[*].id
    security_groups  = [aws_security_group.ecs_security_group.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.medusa_server_tg.arn
    container_name   = "medusa-server"
    container_port   = 9000
  }

  depends_on = [
    aws_lb_listener.medusa_http_listener,
    aws_lb_listener.medusa_https_listener,
    aws_lb_listener.medusa_http_listener_no_cert
  ]

  tags = {
    Name        = "${var.project_name}-server-service"
    Environment = var.environment
  }
}

# ECS Service for Medusa Worker
resource "aws_ecs_service" "medusa_worker_service" {
  name            = "${var.project_name}-worker-service"
  cluster         = aws_ecs_cluster.medusa_cluster.id
  task_definition = aws_ecs_task_definition.medusa_worker.arn
  desired_count   = var.desired_count_worker
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private_subnets[*].id
    security_groups  = [aws_security_group.ecs_security_group.id]
    assign_public_ip = false
  }

  tags = {
    Name        = "${var.project_name}-worker-service"
    Environment = var.environment
  }
}
