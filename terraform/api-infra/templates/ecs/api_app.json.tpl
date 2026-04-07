[
  {
    "name": "${environment}-api",
    "image": "${app_image}",
    "cpu": ${fargate_cpu - 32},
    "memory": ${fargate_memory - 256},
    "networkMode": "awsvpc",
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${environment}-app",
          "awslogs-region": "${aws_region}",
          "awslogs-stream-prefix": "ecs"
        }
    },
    "portMappings": [
      {
        "containerPort": ${app_port},
        "hostPort": ${app_port}
      }
    ],  
    "secrets": [
        {
          "name": "JWT_SECRET_OR_KEY",
          "valueFrom": "${jwt_secret_arn}"
        }
    ],
    "environmentFiles": [
      {
        "value": "arn:aws:s3:::tf-infra-automation-artifacts/${environment}.env",
        "type": "s3"
      }
    ],
    "dependsOn": [
      {
        "containerName": "xray-daemon",
        "condition": "START"
      }
    ]
  },
  {
    "name": "xray-daemon",
    "image": "amazon/aws-xray-daemon",
    "cpu": 32,
    "memoryReservation": 256,
    "portMappings": [
      {
        "containerPort": 2000,
        "protocol": "udp"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/${environment}-xray",
        "awslogs-region": "${aws_region}",
        "awslogs-stream-prefix": "xray"
      }
    }
  }
]