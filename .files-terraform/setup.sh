#!/bin/bash 
sudo apt update
sudo apt install -y ruby-full
sudo apt install -y wget
cd /home/ubuntu
wget https://aws-codedeploy-us-west-2.s3.us-west-2.amazonaws.com/latest/install
chmod 777 ./install
sudo ./install auto > /tmp/logfile
sudo systemctl start codedeploy-agent