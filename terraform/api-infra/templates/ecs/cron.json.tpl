[
  {
    "name": "${environment}-${name}",
    "image": "${image}",
    "cpu": ${fargate_cpu},
    "memory": ${fargate_memory},
    "networkMode": "awsvpc",
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${environment}-crons",
          "awslogs-region": "${aws_region}",
          "awslogs-stream-prefix": "${name}"
        }
    },
    "command": ${jsonencode(command)},
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
    ]
  }
]
