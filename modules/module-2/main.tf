terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Config for public access
resource "aws_vpc" "lab-vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name      = "AWS_GOAT_VPC"
    yor_trace = "7478d819-7684-4dc6-b8f3-e25a2572dd66"
  }
}
resource "aws_subnet" "lab-subnet-public-1" {
  vpc_id                  = aws_vpc.lab-vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = {
    yor_trace = "7eea2ded-75dc-4d0b-b9f5-093b6a0a2167"
  }
}
resource "aws_internet_gateway" "my_vpc_igw" {
  vpc_id = aws_vpc.lab-vpc.id
  tags = {
    Name      = "My VPC - Internet Gateway"
    yor_trace = "c708b7c6-9d88-42c9-a5a8-3360a81c39af"
  }
}
resource "aws_route_table" "my_vpc_us_east_1_public_rt" {
  vpc_id = aws_vpc.lab-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_vpc_igw.id
  }

  tags = {
    Name      = "Public Subnet Route Table."
    yor_trace = "51e0e76d-a19e-421f-b4ae-dbcd11d99c56"
  }
}

resource "aws_route_table_association" "my_vpc_us_east_1a_public" {
  subnet_id      = aws_subnet.lab-subnet-public-1.id
  route_table_id = aws_route_table.my_vpc_us_east_1_public_rt.id
}
resource "aws_subnet" "lab-subnet-public-1b" {
  vpc_id                  = aws_vpc.lab-vpc.id
  cidr_block              = "10.0.128.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags = {
    yor_trace = "20793412-097f-483f-89ce-e609056ee1b9"
  }
}
resource "aws_route_table_association" "my_vpc_us_east_1b_public" {
  subnet_id      = aws_subnet.lab-subnet-public-1b.id
  route_table_id = aws_route_table.my_vpc_us_east_1_public_rt.id
}

resource "aws_security_group" "ecs_sg" {
  name        = "ECS-SG"
  description = "SG for cluster created from terraform"
  vpc_id      = aws_vpc.lab-vpc.id

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.load_balancer_security_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    yor_trace = "f0404076-2e2c-4f5c-a7cc-ccc625efc815"
  }
}

# Create Database Subnet Group
# terraform aws db subnet group
resource "aws_db_subnet_group" "database-subnet-group" {
  name        = "database subnets"
  subnet_ids  = [aws_subnet.lab-subnet-public-1.id, aws_subnet.lab-subnet-public-1b.id]
  description = "Subnets for Database Instance"

  tags = {
    Name      = "Database Subnets"
    yor_trace = "eb124e04-9d7b-4fc0-8a04-8dd9996cd9c0"
  }
}

# Create Security Group for the Database
# terraform aws create security group

resource "aws_security_group" "database-security-group" {
  name        = "Database Security Group"
  description = "Enable MYSQL Aurora access on Port 3306"
  vpc_id      = aws_vpc.lab-vpc.id

  ingress {
    description     = "MYSQL/Aurora Access"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = ["${aws_security_group.ecs_sg.id}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "rds-db-sg"
    yor_trace = "63af24a7-e492-4ac1-becf-b0aeceef8a1d"
  }

}

# Create Database Instance Restored from DB Snapshots
# terraform aws db instance
resource "aws_db_instance" "database-instance" {
  identifier             = "aws-goat-db"
  allocated_storage      = 10
  instance_class         = "db.t3.micro"
  engine                 = "mysql"
  engine_version         = "5.7"
  username               = "root"
  password               = "T2kVB3zgeN3YbrKS"
  parameter_group_name   = "default.mysql5.7"
  skip_final_snapshot    = true
  availability_zone      = "us-east-1a"
  db_subnet_group_name   = aws_db_subnet_group.database-subnet-group.name
  vpc_security_group_ids = [aws_security_group.database-security-group.id]
  tags = {
    yor_trace = "72fcfbcd-e274-4c11-9f49-3162c753fd87"
  }
}



resource "aws_security_group" "load_balancer_security_group" {
  name        = "Load-Balancer-SG"
  description = "SG for load balancer created from terraform"
  vpc_id      = aws_vpc.lab-vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name      = "aws-goat-m2-sg"
    yor_trace = "0a538d41-07a6-48d9-95d0-e4b5efad2c82"
  }
}



resource "aws_iam_role" "ecs-instance-role" {
  name                 = "ecs-instance-role"
  path                 = "/"
  permissions_boundary = aws_iam_policy.instance_boundary_policy.arn
  assume_role_policy = jsonencode({
    "Version" : "2008-10-17",
    "Statement" : [
      {
        "Sid" : "",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ec2.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
  tags = {
    yor_trace = "bd73e3d4-e2cd-4908-8c29-b7738286c423"
  }
}


resource "aws_iam_role_policy_attachment" "ecs-instance-role-attachment-1" {
  role       = aws_iam_role.ecs-instance-role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}
resource "aws_iam_role_policy_attachment" "ecs-instance-role-attachment-2" {
  role       = aws_iam_role.ecs-instance-role.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}

resource "aws_iam_role_policy_attachment" "ecs-instance-role-attachment-3" {
  role       = aws_iam_role.ecs-instance-role.name
  policy_arn = aws_iam_policy.ecs_instance_policy.arn
}

resource "aws_iam_policy" "ecs_instance_policy" {
  name = "aws-goat-instance-policy"
  policy = jsonencode({
    "Statement" : [
      {
        "Action" : [
          "ssm:*",
          "ssmmessages:*",
          "ec2:RunInstances",
          "ec2:Describe*"
        ],
        "Effect" : "Allow",
        "Resource" : "*",
        "Sid" : "Pol1"
      }
    ],
    "Version" : "2012-10-17"
  })
  tags = {
    yor_trace = "9ddaa929-a02a-4f21-be69-55f6e6ab1272"
  }
}

resource "aws_iam_policy" "instance_boundary_policy" {
  name = "aws-goat-instance-boundary-policy"
  policy = jsonencode({
    "Statement" : [
      {
        "Action" : [
          "iam:List*",
          "iam:Get*",
          "iam:PassRole",
          "iam:PutRole*",
          "ssm:*",
          "ssmmessages:*",
          "ec2:RunInstances",
          "ec2:Describe*",
          "ecs:*",
          "ecr:*",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Effect" : "Allow",
        "Resource" : "*",
        "Sid" : "Pol1"
      }
    ],
    "Version" : "2012-10-17"
  })
  tags = {
    yor_trace = "a198ea62-1947-4e3a-8fab-9515fc50137d"
  }
}

resource "aws_iam_instance_profile" "ec2-deployer-profile" {
  name = "ec2Deployer"
  path = "/"
  role = aws_iam_role.ec2-deployer-role.id
  tags = {
    yor_trace = "b1450f89-48d6-4fde-8abc-baa79adf5216"
  }
}
resource "aws_iam_role" "ec2-deployer-role" {
  name = "ec2Deployer-role"
  path = "/"
  assume_role_policy = jsonencode({
    "Version" : "2008-10-17",
    "Statement" : [
      {
        "Sid" : "",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ec2.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
  tags = {
    yor_trace = "f8a5ffa5-d199-4eb3-802c-3ab430531ae9"
  }
}

resource "aws_iam_policy" "ec2_deployer_admin_policy" {
  name = "ec2DeployerAdmin-policy"
  policy = jsonencode({
    "Statement" : [
      {
        "Action" : [
          "*"
        ],
        "Effect" : "Allow",
        "Resource" : "*",
        "Sid" : "Policy1"
      }
    ],
    "Version" : "2012-10-17"
  })
  tags = {
    yor_trace = "9dee31be-c2a1-4600-95e9-20d07bfb1e51"
  }
}

resource "aws_iam_role_policy_attachment" "ec2-deployer-role-attachment" {
  role       = aws_iam_role.ec2-deployer-role.name
  policy_arn = aws_iam_policy.ec2_deployer_admin_policy.arn
}

resource "aws_iam_instance_profile" "ecs-instance-profile" {
  name = "ecs-instance-profile"
  path = "/"
  role = aws_iam_role.ecs-instance-role.id
  tags = {
    yor_trace = "0aea6776-49ac-4946-89a1-b2d7f73580a7"
  }
}
resource "aws_iam_role" "ecs-task-role" {
  name = "ecs-task-role"
  path = "/"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ecs-tasks.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
    }
  )
  tags = {
    yor_trace = "cf078600-8622-4bcb-8ef5-34a092685e01"
  }
}

resource "aws_iam_role_policy_attachment" "ecs-task-role-attachment" {
  role       = aws_iam_role.ecs-task-role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy_attachment" "ecs-task-role-attachment-2" {
  role       = aws_iam_role.ecs-task-role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_iam_role_policy_attachment" "ecs-instance-role-attachment-ssm" {
  role       = aws_iam_role.ecs-instance-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


data "aws_ami" "ecs_optimized_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-2.0.202*-x86_64-ebs"]
  }
}



resource "aws_launch_configuration" "ecs_launch_config" {
  image_id             = data.aws_ami.ecs_optimized_ami.id
  iam_instance_profile = aws_iam_instance_profile.ecs-instance-profile.name
  security_groups      = [aws_security_group.ecs_sg.id]
  user_data            = data.template_file.user_data.rendered
  instance_type        = "t2.micro"
}
resource "aws_autoscaling_group" "ecs_asg" {
  name                 = "ECS-lab-asg"
  vpc_zone_identifier  = [aws_subnet.lab-subnet-public-1.id]
  launch_configuration = aws_launch_configuration.ecs_launch_config.name
  desired_capacity     = 1
  min_size             = 0
  max_size             = 1
}

resource "aws_ecs_cluster" "cluster" {
  name = "ecs-lab-cluster"

  tags = {
    name      = "ecs-cluster-name"
    yor_trace = "7545adc8-c787-43e6-9847-e6870d3eabb3"
  }
}

data "template_file" "user_data" {
  template = file("${path.module}/resources/ecs/user_data.tpl")
}

resource "aws_ecs_task_definition" "task_definition" {
  container_definitions    = data.template_file.task_definition_json.rendered
  family                   = "ECS-Lab-Task-definition"
  network_mode             = "bridge"
  memory                   = "512"
  cpu                      = "512"
  requires_compatibilities = ["EC2"]
  task_role_arn            = aws_iam_role.ecs-task-role.arn

  pid_mode = "host"
  volume {
    name      = "modules"
    host_path = "/lib/modules"
  }
  volume {
    name      = "kernels"
    host_path = "/usr/src/kernels"
  }
  tags = {
    yor_trace = "ee7bd9c4-1246-48d7-9763-1624c441c322"
  }
}

data "template_file" "task_definition_json" {
  template = file("${path.module}/resources/ecs/task_definition.json")
  depends_on = [
    null_resource.rds_endpoint
  ]
}



resource "aws_ecs_service" "worker" {
  name                              = "ecs_service_worker"
  cluster                           = aws_ecs_cluster.cluster.id
  task_definition                   = aws_ecs_task_definition.task_definition.arn
  desired_count                     = 1
  health_check_grace_period_seconds = 2147483647

  load_balancer {
    target_group_arn = aws_lb_target_group.target_group.arn
    container_name   = "aws-goat-m2"
    container_port   = 80
  }
  depends_on = [aws_lb_listener.listener]
  tags = {
    yor_trace = "007214f2-b259-4f69-ae64-01ac4d45de6e"
  }
}

resource "aws_alb" "application_load_balancer" {
  name               = "aws-goat-m2-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.lab-subnet-public-1.id, aws_subnet.lab-subnet-public-1b.id]
  security_groups    = [aws_security_group.load_balancer_security_group.id]

  tags = {
    Name      = "aws-goat-m2-alb"
    yor_trace = "8a73474e-08ca-48f8-ba04-31677d2a1a19"
  }
}

resource "aws_lb_target_group" "target_group" {
  name        = "aws-goat-m2-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.lab-vpc.id

  tags = {
    Name      = "aws-goat-m2-tg"
    yor_trace = "ac76d73f-8f57-44b3-9a6d-2461c7470975"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_alb.application_load_balancer.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.id
  }
}


resource "aws_secretsmanager_secret" "rds_creds" {
  name                    = "RDS_CREDS"
  recovery_window_in_days = 0
  tags = {
    yor_trace = "51cdf3c1-8ad4-4984-9a03-1ba9ac53a0ab"
  }
}

resource "aws_secretsmanager_secret_version" "secret_version" {
  secret_id     = aws_secretsmanager_secret.rds_creds.id
  secret_string = <<EOF
   {
    "username": "root",
    "password": "T2kVB3zgeN3YbrKS"
   }
EOF
}

resource "null_resource" "rds_endpoint" {
  provisioner "local-exec" {
    command     = <<EOF
RDS_URL="${aws_db_instance.database-instance.endpoint}"
RDS_URL=$${RDS_URL::-5}
sed -i "s,RDS_ENDPOINT_VALUE,$RDS_URL,g" ${path.module}/resources/ecs/task_definition.json
EOF
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    aws_db_instance.database-instance
  ]
}

resource "null_resource" "cleanup" {
  provisioner "local-exec" {
    command     = <<EOF
RDS_URL="${aws_db_instance.database-instance.endpoint}"
RDS_URL=$${RDS_URL::-5}
sed -i "s,$RDS_URL,RDS_ENDPOINT_VALUE,g" ${path.module}/resources/ecs/task_definition.json
EOF
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    null_resource.rds_endpoint, aws_ecs_task_definition.task_definition
  ]
}


/* Creating a S3 Bucket for Terraform state file upload. */
resource "aws_s3_bucket" "bucket_tf_files" {
  bucket        = "do-not-delete-awsgoat-state-files-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags = {
    Name        = "Do not delete Bucket"
    Environment = "Dev"
    yor_trace   = "d2baa596-3f03-4dff-a35c-575dee7ac339"
  }
}

output "ad_Target_URL" {
  value = "${aws_alb.application_load_balancer.dns_name}:80/login.php"
}
