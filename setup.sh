#!/bin/bash
# Add -x above to debug.

# We require a config.env file defining the environment variables needed to manage a swarm.
# If SKIP_SWARM_ENV is defined as 'true' however, we rely on those variables already
# being set in the environment.
if [ "$SKIP_SWARM_ENV" != "true" ] && [ ! -f $(dirname "$0")/config.env ]; then
  echo "You need to create a config.env file (or set SKIP_SWARM_ENV=true). Check docs/deploying-swarm.md for more information how to create and modify this file."
  exit 1
fi

# This trap is executed whenever a process exits within this script, we use it
# to output the exact command that failed to find potential issues faster.
exit_trap () {
  local lc="$BASH_COMMAND" rc=$?
  if [ "$rc" != "0" ]; then
    echo "Command [$lc] exited with code [$rc] - bailing"
    exit 1
  fi
}

trap exit_trap EXIT

# Move to project root to simplify execution context for processes.
cd "$(dirname "$0")"

if [ "$SKIP_SWARM_ENV" != "true" ]; then
  # Read environment variables configuration from config.env.
  set -o allexport; source ./config.env; set +o allexport
fi

set -e

command=$1
rest=${@:2}
user=$(id -u -n)
machine_prefix="${user}-ca"
switches="--driver=$DOCKER_DRIVER --engine-opt log-opt="max-size=10m" --amazonec2-open-port 19076 --engine-opt experimental=true --engine-opt metrics-addr=0.0.0.0:4999 --engine-label env=qliktive"
machines=
managers=

# Override default node name prefix if the user wants to.
if [ "$DOCKER_PREFIX" != "" ]; then
  machine_prefix=$DOCKER_PREFIX
fi

# Some parts of this script may need to refresh our swarm node list (e.g. when creating
# or removing nodes), this function simplifies it.
function refresh_nodes() {
  machines=$(docker-machine ls --filter label=env=qliktive -q)
  managers=$(echo "$machines" | grep -i 'manager' || true)
  echo "Managers found:"
  echo "$managers"
}

function build_containers() {
    echo "Building containers without public image"
    docker-compose -f docker-compose.yml build
    docker push sublibra/core-happy_happy-server
    docker push sublibra/core-happy_jdbc-connector

}

# Deploy stack - currently on the same machine but prepare for future possibility of
# multimachine setup
function deploy_stack() {
  if [ -z "$machines" ]; then
    echo "No nodes to deploy against."
    exit 0
  fi

  for manager in $managers
  do
    ip=$(docker-machine ip $manager)
    eval $(docker-machine env $manager)
    docker stack deploy -c ./docker-compose.yml happy-service
    echo
    echo "$(docker service ls)"
    echo
    echo "Then all the replicas for the service is started (this may take several minutes) -"
    echo "The following routes can be accessed:"
    echo "Deployment target         - http://$ip/"
  done
}

# Clean a deployed stack from the swarm nodes.
function clean() {
  if [ -z "$managers" ]; then
    echo "No nodes to clean."
    exit 0
  fi

  for manager in $managers
  do
    eval $(docker-machine env $manager)
    docker stack rm happy-service
  done
}

# Create node (1 manager)
function create() {
  if [ "$machines" ]; then
    echo "There are existing qliktive nodes, please remove them and try again."
    exit 0
  fi

  name="${machine_prefix}-manager"

  AWS_INSTANCE_TYPE="${AWS_INSTANCE_TYPE_MANAGER:-$AWS_INSTANCE_TYPE_DEFAULT}" \
  docker-machine create $switches $name
  ip=$(docker-machine inspect --format '{{.Driver.PrivateIPAddress}}' $name)

  if [ "$ip" == "<no value>" ]; then
    ip=$(docker-machine ip $name)
  fi

  eval $(docker-machine env $name)
  echo "docker swarm init --advertise-addr $ip --listen-addr $ip:2377:"
  docker swarm init --advertise-addr $ip --listen-addr $ip:2377

   refresh_nodes
}

# Remove all nodes related to this project.
function remove() {
  if [ -z "$machines" ]; then
    echo "No qliktive nodes to remove."
    exit 0
  fi

  docker-machine rm $machines
}

function list() {
  echo "Managers:"
  echo "$managers"
  for manager in $managers
  do
    docker-machine ssh $manager docker service ls
  done
}

# Since development we don't build official docker containers for these
function setup(){
  echo "Pulling latest repositories"
  cd ..
  if [ ! -d "happy-web" ]; then
    git clone git@github.com:JohanBjerning/happy-web.git
  fi
  if [ ! -d "core-grpc-jdbc-connector" ]; then
    git clone git@github.com:qlik-oss/core-grpc-jdbc-connector.git
  fi
  if [ ! -d "core-happy-server" ]; then
    git clone git@github.com:sublibra/core-happy-server.git
  fi
}

refresh_nodes

if   [ "$command" == "deploy" ];        then deploy_stack
elif [ "$command" == "deploy-stack" ];  then deploy_stack
elif [ "$command" == "clean" ];         then clean
elif [ "$command" == "build" ];         then build_containers
elif [ "$command" == "create" ];        then create
elif [ "$command" == "remove" ];        then remove
elif [ "$command" == "ls" ];            then list
elif [ "$command" == "setup" ];         then setup

else echo "Invalid option: $command - please use one of: setup, build, deploy, clean, create, remove, deploy-stack, ls"; fi
