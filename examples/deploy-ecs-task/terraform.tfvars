aws_region = "ap-south-1"
docker_image = "nginx"
docker_image_command = ["nginx", "-g", "daemon off;"]
docker_image_version = "latest"
ecs_cluster_instance_ami = "ami-0287a05f0ef0e9d9a"
ecs_cluster_name = "testingterraform"
instance_types = ["t3.micro", "t2.micro"]