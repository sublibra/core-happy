# core-happy
Container of build and deployment scripts for the instant happiness application.

## Usage

The setup.sh script is currently used to setup, build and deplou the solution:

* setup - clones repos required to build the solution where a public image has not been provided
* create - setup a docker swarm instance based on the information in config.env (config.example.env supplied)
* deploy - pull latest images, build local images and deploy to docker swarm
* clean - remove services on local swarm
* remove - kill swarm machine(s)