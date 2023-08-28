#!/bin/bash
sudo apt update -y
sudo apt install -y curl

mkdir actions-runner 
cd actions-runner
curl -o actions-runner-linux-x64-2.308.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.308.0/actions-runner-linux-x64-2.308.0.tar.gz
tar xzf ./actions-runner-linux-x64-2.308.0.tar.gz
./bin/installdependencies.sh
cd ../
