#create a vpc
resource "aws_vpc" "commerce-vpc" {

    cidr_block = "10.0.0.0/16" 
  
}

#create an internet gateway for the vpc
resource "aws_internet_gateway" "commerce-gw"{

    vpc_id = aws_vpc.commerce-vpc.id
    
}

#attach created internet gateway to vpc
/*resource "aws_internet_gateway_attachment" "commerce-gw-attachment" {

  internet_gateway_id = aws_internet_gateway.commerce-gw.id
  vpc_id = aws_vpc.commerce-vpc.id

}*/


#create a route table that routes all traffic to the vpc through the internet gateway
resource "aws_route_table" "commerce-routetable" {

    vpc_id = aws_vpc.commerce-vpc.id

     route {
             cidr_block = "0.0.0.0/0"
             gateway_id =  aws_internet_gateway.commerce-gw.id
  }

}

#associate the public subnet with the route for the vpc to allow internet traffic from this instances running in the public subnet
resource "aws_route_table_association" "commerce-routetable-association-a"{

    subnet_id = aws_subnet.commerce-subnet-public1-us-west-2a.id
    route_table_id = aws_route_table.commerce-routetable.id
}
  
resource "aws_route_table_association" "commerce-routetable-aws_route_table_association-b" {

    subnet_id = aws_subnet.commerce-subnet-public2-us-west-2b.id
    route_table_id = aws_route_table.commerce-routetable.id
  
}
 

#create a public subnet in us-west-2a availability zone
resource "aws_subnet" "commerce-subnet-public1-us-west-2a" {

    vpc_id = aws_vpc.commerce-vpc.id
    availability_zone = "us-west-2a" 
    #map_public_ip_on_launch = true
    cidr_block = "10.0.0.0/17"

}

#create a private subnet in us-west-2a availability subnet
/*resource "aws_subnet" "commerce-subnet-private1-us-west-2a" {

    vpc_id =  aws_vpc.commerce-vpc.id
    availability_zone = "us-west-2a"
    #map_public_ip_on_launch = false
    cidr_block = "10.0.128.0/17"
}*/

#create a public subnet in us-west-2b availability zone
resource "aws_subnet" "commerce-subnet-public2-us-west-2b" {

    vpc_id = aws_vpc.commerce-vpc.id
    availability_zone = "us-west-2b"
    #map_public_ip_on_launch = true
    cidr_block = "10.0.144.0/20"
}

#create a private subnet in us-west-2b availibilty zone
/*resource "aws_subnet" "project-subnet-private2-us-west-2b" {

    vpc_id = aws_vpc.commerce-vpc.id
    availability_zone = "us-west-2b"
    #map_public_ip_on_launch = false
    cidr_block = "10.0.16.0/20"
}*/

#create a security group 
resource "aws_security_group" "commerce-lb-security-group" {

    name = "load-balancer-security-group"
    description = "allow http, ssh traffic"
    vpc_id = aws_vpc.commerce-vpc.id

    ingress {
        description = "allow http traffic"
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]

    }

    ingress {
        description = "allow https traffic"
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]

    }

    ingress {
        description = "allow ssh traffic"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    

    egress {
        description = "allow all outbound traffic"
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
        
    }

}

#create security group for auto scaling group to only allow traffic from vpc cidr block since load balancer is in the same network
resource "aws_security_group" "commerce-autoscaling-security-group" {

    name = "commerce-autoscaling-security-group"
    description = "allow traffic from vpc cidr block to instances"
    vpc_id = aws_vpc.commerce-vpc.id

    ingress {
        description = "allow inbound http traffic"
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = [ "10.0.0.0/16" ]
    }

    ingress {
        description = "allow htpps traffic"
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = ["10.0.0.0/16"]
    }


    egress {
        description = "allow all traffic go out"
        from_port = "0"
        to_port = "0"
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/16"]
    }

  
}




#create aws key pair for ec2 instance
resource "aws_key_pair" "commerce-key-pair" {

    key_name = "kodekloud-key"
    #public_key = file("/home/oche/aws-kodekloudapp/terraform/ec2.pub")
    public_key = file("${path.module}/ec2.pub")       

}



data "aws_ami" "kodekloud-apache" {
    most_recent = true
    owners = [ "self" ]


    filter {
        name = "image-id"
        #values = [ "ami-086eb415e8acccb9f" ]
        values = [ "ami-0a192cb1f6e74e1c5"]
    }
}

data "aws_iam_instance_profile" "commerce-ec2-profile" {
    name = "ec2-role"
  
}


#create ec2 testing server instannce
resource "aws_instance" "staging" {

    ami = data.aws_ami.kodekloud-apache.id
    subnet_id = aws_subnet.commerce-subnet-public2-us-west-2b.id
    vpc_security_group_ids = [ aws_security_group.commerce-lb-security-group.id ]
    tags = {
        Name = "staging-server"
    }
    associate_public_ip_address = true
    instance_type = "t2.micro"
    key_name = aws_key_pair.commerce-key-pair.id
    iam_instance_profile = data.aws_iam_instance_profile.commerce-ec2-profile.role_name

  
}




#create aws launch template to be used by autoscaling group
resource "aws_launch_template" "commerce-launchtemplate" {

    name = "kodekloud-lauch-template"
    key_name = aws_key_pair.commerce-key-pair.id
    instance_type = "t2.micro"
    image_id = data.aws_ami.kodekloud-apache.id
    iam_instance_profile {
        name = data.aws_iam_instance_profile.commerce-ec2-profile.role_name
    }
    vpc_security_group_ids = [ aws_security_group.commerce-autoscaling-security-group.id ]
    #user_data = filebase64("${path.module}/setup.sh")
    lifecycle {
      create_before_destroy = true
    }
    update_default_version = true
   
}

#create load balancer target group
resource "aws_lb_target_group" "commerce-targetgroup" {
    name = "kodekloud-target-group"
    port = "80"
    protocol = "HTTP"
    vpc_id = aws_vpc.commerce-vpc.id

}

#create load balancer
resource "aws_lb" "commerce-lb" {

    name = "kodekloud-loadbalancer"
    internal = false
    load_balancer_type = "application"
    security_groups = [ aws_security_group.commerce-lb-security-group.id ]
    subnets = [ aws_subnet.commerce-subnet-public1-us-west-2a.id, aws_subnet.commerce-subnet-public2-us-west-2b.id ]

}

#create a load balancer listener to listen for ingress traffic on a particular port
resource "aws_lb_listener" "commerce-lb-listener" {

    load_balancer_arn = aws_lb.commerce-lb.arn
    port = "80"
    protocol = "HTTP"


    default_action {
      type = "forward"
      target_group_arn = aws_lb_target_group.commerce-targetgroup.arn
    }
  
}

#create an autoscaling group
resource "aws_autoscaling_group" "commerce-autoscaling-group" {

    name = "kodecloud-autoscaling-group"
    max_size = 4
    min_size = 1
    desired_capacity = 2
    health_check_grace_period = 300
    health_check_type = "EC2"
    vpc_zone_identifier = [ aws_subnet.commerce-subnet-public1-us-west-2a.id, aws_subnet.commerce-subnet-public2-us-west-2b.id ]


    launch_template {
      id = aws_launch_template.commerce-launchtemplate.id
      version = aws_launch_template.commerce-launchtemplate.latest_version   #always use the latest version of the launch template when launching
    
    }

    instance_refresh {
      strategy = "Rolling"
      preferences {
        min_healthy_percentage = 50
      }
    }
    
    #must configure if instance refresh is enabled
    lifecycle {
      ignore_changes = [ load_balancers, target_group_arns]
    }
  
}

#create an autoscaling policy
resource "aws_autoscaling_policy" "commerce-scaling-policy" {

    name = "commerce-scaling-policy"
    autoscaling_group_name = aws_autoscaling_group.commerce-autoscaling-group.name                                    #everytime the cpu usage of an instance exceeds %50, add an instance
    policy_type = "TargetTrackingScaling"                       #track individual targets

    target_tracking_configuration {
        predefined_metric_specification {
            predefined_metric_type = "ASGAverageCPUUtilization"      
        }
        target_value = 50.0

    }

}


#attach autoscaling group wit load balancer
resource "aws_autoscaling_attachment" "commerce-as-attachment" {

    autoscaling_group_name = aws_autoscaling_group.commerce-autoscaling-group.id
    lb_target_group_arn = aws_lb_target_group.commerce-targetgroup.arn
    #elb = aws_lb.commerce-lb.id
  
}














#create codedeploy application
resource "aws_codedeploy_app" "commerce-app" {
    compute_platform = "Server"
    name = "commerce-app"
  
}


#create service role for code deploy
resource "aws_iam_role" "codedeploy-role" {
  name = "codedeploy-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "codedeploy.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

#attach policy to codedeploy role
resource "aws_iam_role_policy_attachment" "AWSCodeDeployRole" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
  role       = aws_iam_role.codedeploy-role.name
}


#create codedeploy deployment group for prod
resource "aws_codedeploy_deployment_group" "commerce-deployment-group" {

    app_name =  aws_codedeploy_app.commerce-app.name
    deployment_group_name = "commerce-deployment"
    service_role_arn = aws_iam_role.codedeploy-role.arn

    autoscaling_groups = [aws_autoscaling_group.commerce-autoscaling-group.id]
    deployment_style {
      deployment_option =  "WITH_TRAFFIC_CONTROL"
      deployment_type = "IN_PLACE"
    }

    load_balancer_info {
      target_group_info{
          name = aws_lb_target_group.commerce-targetgroup.name
      }
    }
    
    auto_rollback_configuration {
       enabled = true
       events  = ["DEPLOYMENT_FAILURE"]
    }

}


#create code deployment group for staging
resource "aws_codedeploy_deployment_group" "staging-deployment-group" {

    app_name = aws_codedeploy_app.commerce-app.name
    deployment_group_name = "staging-deployment"
    service_role_arn = aws_iam_role.codedeploy-role.arn
    ec2_tag_set {
      ec2_tag_filter {
        key = "Name"
        type = "KEY_AND_VALUE"
        value = "staging-server"
      }
    }

    auto_rollback_configuration {
      enabled = true
      events = ["DEPLOYMENT_FAILURE"]

    }
  
}


#access s3 bucket that stores application revision
data "aws_s3_bucket" "prod-bucket" {
    bucket = "kodekloud-prod-bucket"
  
}

#access s3 staging bucket
data "aws_s3_bucket" "staging-bucket"{
    bucket = "kodekloud-codedeploy-bucket"
}

data "aws_iam_role" "codepipeline"{
    name = "codepipelinerole"

}
#create code deploy pipeline

