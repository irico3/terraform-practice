resource "aws_vpc" "example" {
    cidr_block = "10.0.0.0/16"
    enable_dns_support = true
    enable_dns_hostnames = true

    tags = {
        Name = "example"
    }
}

resource "aws_subnet" "public_0" {
    vpc_id = aws_vpc.example.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "ap-northeast-1a"
    map_public_ip_on_launch = true
}

resource "aws_subnet" "public_1" {
    vpc_id = aws_vpc.example.id
    cidr_block = "10.0.2.0/24"
    availability_zone = "ap-northeast-1c"
    map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "example" {
    vpc_id = aws_vpc.example.id
}

resource "aws_route_table" "public" {
    vpc_id = aws_vpc.example.id
}

resource "aws_route" "public" {
    route_table_id = aws_route_table.public.id
    gateway_id = aws_internet_gateway.example.id
    destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "pubic_0" {
    subnet_id = aws_subnet.public_0.id
    route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "pubic_1" {
    subnet_id = aws_subnet.public_0.id
    route_table_id = aws_route_table.public.id
}

# プライベートサブネット
resource "aws_subnet" "private_0" {
    vpc_id = aws_vpc.example.id
    cidr_block = "10.0.65.0/24"
    availability_zone =  "ap-northeast-1a"
    map_public_ip_on_launch = false

}
resource "aws_subnet" "private_1" {
    vpc_id = aws_vpc.example.id
    cidr_block = "10.0.66.0/24"
    availability_zone =  "ap-northeast-1c"
    map_public_ip_on_launch = false

}

resource "aws_route_table" "private_0" {
    vpc_id = aws_vpc.example.id
}
resource "aws_route_table" "private_1" {
    vpc_id = aws_vpc.example.id
}

resource "aws_route_table_association" "private_0" {
    subnet_id = aws_subnet.private_0.id
    route_table_id = aws_route_table.private_0.id
}
resource "aws_route_table_association" "private_1" {
    subnet_id = aws_subnet.private_1.id
    route_table_id = aws_route_table.private_1.id
}

resource "aws_eip" "nat_gateway_0" {
    vpc = true
    depends_on = [
      aws_internet_gateway.example
    ]
}
resource "aws_eip" "nat_gateway_1" {
    vpc = true
    depends_on = [
      aws_internet_gateway.example
    ]
}

resource "aws_nat_gateway" "nat_gateway_0" {
    allocation_id = aws_eip.nat_gateway_0.id
    subnet_id = aws_subnet.public_0.id
    depends_on = [aws_internet_gateway.example]
}

resource "aws_nat_gateway" "nat_gateway_1" {
    allocation_id = aws_eip.nat_gateway_1.id
    subnet_id = aws_subnet.public_1.id
    depends_on = [aws_internet_gateway.example]
}

resource "aws_route" "private_0" {
    route_table_id = aws_route_table.private_0.id
    nat_gateway_id = aws_nat_gateway.nat_gateway_0.id
    destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route" "private_1" {
    route_table_id = aws_route_table.private_1.id
    nat_gateway_id = aws_nat_gateway.nat_gateway_1.id
    destination_cidr_block = "0.0.0.0/0"
}

# S3
resource "aws_s3_bucket" "alb_log" {
    bucket = "alb-pragmatic-terraform3"
    lifecycle_rule {
        enabled = true
        expiration {
          days = "180"
        }
    }
    force_destroy = true
}

resource "aws_s3_bucket_policy" "alb_log" {
    bucket = aws_s3_bucket.alb_log.id
    policy = data.aws_iam_policy_document.alb_log.json
}

data "aws_iam_policy_document" "alb_log" {
    statement {
        effect = "Allow"
        actions = ["s3:PutObject"]
        resources = ["arn:aws:s3:::${aws_s3_bucket.alb_log.id}/*"]
        principals {
            type = "AWS"
            identifiers = ["582318560864"]
        }
    }
}

# セキュリティグループ
module "http_sg" {
    source = "./security_group"
    name = "http_sg"
    vpc_id = aws_vpc.example.id
    port = 80
    cidr_blocks = ["0.0.0.0/0"]
}

module "https_sg" {
    source = "./security_group"
    name = "https_sg"
    vpc_id = aws_vpc.example.id
    port = 443
    cidr_blocks = ["0.0.0.0/0"]
}
module "http_redirect_sg" {
    source = "./security_group"
    name = "http-redirect-sg"
    vpc_id = aws_vpc.example.id
    port = 8080
    cidr_blocks = ["0.0.0.0/0"]
}

# ロードバランサー
resource "aws_lb" "example" {
    name = "example"
    load_balancer_type = "application"
    internal = "false"
    idle_timeout = 60
    enable_deletion_protection = false

    subnets = [
        aws_subnet.public_0.id,
        aws_subnet.public_1.id
    ]

    access_logs {
      bucket = aws_s3_bucket.alb_log.id
      enabled = true
    }

    security_groups = [
        module.http_sg.security_group_id,
        module.https_sg.security_group_id,
        module.http_redirect_sg.security_group_id
    ]
}

resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.example.arn
    port = "80"
    protocol = "HTTP"

    default_action {
        type = "fixed-response"
        fixed_response {
            content_type = "text/plain"
            message_body = "これは【HTTP】です"
            status_code = "200"
        }
    }

}

output "alb_dns_name" {
    value = aws_lb.example.dns_name
}