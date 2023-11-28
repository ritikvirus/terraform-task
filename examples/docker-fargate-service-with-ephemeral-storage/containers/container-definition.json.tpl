[
  {
    "name": "${container_name}",
    "image": "${image}:${version}",
    "cpu": ${cpu},
    "memory": ${memory},
    ${length(command) > 0 ? "\"command\": ${command}," : ""}
    "essential": true,
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${awslogs_group}",
        "awslogs-region": "${awslogs_region}",
        "awslogs-stream-prefix": "${awslogs_prefix}"
      }
    },
    "portMappings": [{
      "containerPort": ${container_http_port},
      "hostPort": ${container_http_port},
      "protocol": "tcp"
    }],
    "environment": [
      {"name" : "SERVER_TEXT", "value" : "${server_text}"}
    ]
  }
]
