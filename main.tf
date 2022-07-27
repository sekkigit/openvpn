terraform {
  backend "s3" {
    bucket         = "convect-sandbox-terraform-state"
    dynamodb_table = "convect-sandbox-terraform-state"
    key            = "integration-components/vpn"
    region         = "eu-central-1"
    encrypt        = true
  }
}

locals {
  project = "vpn"
  domain  = "integration-components"
  env     = "sandbox"
}

module "baseTags" {
  source      = "../terraform-modules/tags"
  project     = local.project
  application = "eks"
  owner       = "Convect"
  team        = "DevOps"
  env         = local.env
  domain      = local.domain
}

data "aws_region" "current" {}

provider "aws" {
  region = "eu-central-1"
}

data "aws_ssm_parameter" "terraformStateBucket" {
  name = "terraformStateBucket"
}
data "aws_ssm_parameter" "terraformStateLock" {
  name = "terraformStateLock"
}

data "aws_ssm_parameter" "publicSubnetIds" {
  name = "/${local.env}/${local.domain}/stage-network/publicSubnetIds"
}

resource "aws_instance" "vpn" {
  ami                    = data.aws_ami.vpn.id
  instance_type          = "t2.micro"
  tags                   = { Name = "vpn" }
  subnet_id              = split(",", data.aws_ssm_parameter.publicSubnetIds.value)[0]
  vpc_security_group_ids = [aws_security_group.vpn.id]
  iam_instance_profile   = aws_iam_instance_profile.vpn.name
  key_name               = "terraform-key"
  root_block_device {
    volume_type = "gp2"
    volume_size = "20"
  }
}

data "aws_ami" "vpn" {
  owners      = ["099720109477"]
  #most_recent = true
  filter {
    name   = "name"
    #values = ["Cloud9Ubuntu-*"]
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-20210223"]
  }
 # filter {
 #   name   = "virtualization-type"
 #   values = ["hvm"]
 # }
}

data "aws_ssm_parameter" "vpc_id" {
  name = "/${local.env}/${local.domain}/stage-network/vpc_id"
}

resource "aws_security_group" "vpn" {
  name   = "vpn"
  tags = module.baseTags.tags
  vpc_id = data.aws_ssm_parameter.vpc_id.value
  ingress {
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
    cidr_blocks = ["10.0.0.0/16"]
    description = "allow ssh from vpc"
  }
  ingress {
    from_port   = -1
    protocol    = "icmp"
    to_port     = -1
    cidr_blocks = ["0.0.0.0/0"]
    description = "allow ping from all"
  }
  ingress {
    from_port   = 1194
    protocol    = "udp"
    to_port     = 1194
    cidr_blocks = ["0.0.0.0/0"]
    description = "allow vpn from all"
  }

  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    description = "allow to all"
  }
}

resource "aws_eip" "vpn" {
  tags     = module.baseTags.tags
  instance = aws_instance.vpn.id
}

resource "aws_iam_instance_profile" "vpn" {
  tags  = module.baseTags.tags
  name  = "vpn"
  role  = aws_iam_role.vpn.name
}

resource "aws_iam_role_policy_attachment" "vpnSSM" {
  role       = aws_iam_role.vpn.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role" "vpn" {
  tags               = module.baseTags.tags
  name               = "vpn"
  assume_role_policy = data.aws_iam_policy_document.assumeRole.json
}

data "aws_iam_policy_document" "assumeRole" {
  
  statement {
    sid     = "allowAssume"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["ec2.amazonaws.com"]
      type        = "Service"
    }
  }
}