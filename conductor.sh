#!/bin/bash

pull_image() {
  docker pull "$1"
}

run_container() {
  local image_name="$1"
  local container_name="$2"
  local command_to_execute="$3"
  local port_mapping=""

  if [[ "$4" == "-p" && ! -z "$5" ]]; then
    port_mapping="$5"
  fi

  if [ -z "$port_mapping" ]; then
    docker run -d --name "$container_name" "$image_name" sh -c "$command_to_execute"
  else
    docker run -d --name "$container_name" -p $port_mapping "$image_name" sh -c "$command_to_execute"
  fi
}

stop_container() {
  local container_name="$1"
  if docker ps -a --format '{{.Names}}' | grep -q "^$container_name$"; then
    docker stop "$container_name" >/dev/null
    echo "Container '$container_name' stopped."
  else
    echo "Container '$container_name' is not running."
  fi
}

delete_container() {
  local container_name="$1"
  if docker ps -a --format '{{.Names}}' | grep -q "^$container_name$"; then
    docker stop "$container_name" >/dev/null
    docker rm "$container_name" >/dev/null
    echo "Container '$container_name' deleted."
  else
    echo "Container '$container_name' does not exist."
  fi
}

copy() {
  docker cp "$1" "$2"
}

add_network() {
  local network_name="$1"
  local container_name="$2"
  local internet_arg="$3"

  # Check if the network already exists
  while true; do
    if ! docker network inspect "$network_name" >/dev/null 2>&1; then
      docker network create "$network_name" && break
      echo "Retrying to create network $network_name ..."
    else
      echo "Network '$network_name' created or already exists"
      break
    fi
    sleep 1
  done

  # Check if the container is already connected to the network
  while true; do
    containers_connected=$(docker network inspect "$network_name" --format='{{range .Containers}}{{.Name}}{{end}}' | grep "$container_name")
    if [ -z "$containers_connected" ]; then
      docker network connect "$network_name" "$container_name" && break
    else
      echo "Container '$container_name' is already connected to network '$network_name'."
      break
    fi
    sleep 1
  done

  # Connect the container to the bridge network if required
  if [ "$internet_arg" == "--internet" ]; then
    while true; do
      bridge_connected=$(docker network inspect bridge --format='{{range .Containers}}{{.Name}}{{end}}' | grep "$container_name")
      if [ -z "$bridge_connected" ]; then
        docker network connect bridge "$container_name" && break
      else
        echo "Container '$container_name' is already connected to the bridge network."
        break
      fi
      sleep 1
    done
  fi
}

disconnect_network() {
  local network_name="$1"
  local container_name="$2"

  # Check if the network exists
  if docker network inspect "$network_name" >/dev/null 2>&1; then
    # Save the output of grep into a variable
    containers_connected=$(docker network inspect "$network_name" --format='{{range .Containers}}{{.Name}}{{end}}' | grep "$container_name")

    # Check if the container is connected to the network
    if [ -n "$containers_connected" ]; then
      docker network disconnect "$network_name" "$container_name" >/dev/null 2>&1
    else
      echo "Container '$container_name' is not connected to network '$network_name'."
    fi
  else
    echo "Network '$network_name' does not exist."
  fi
}

remove_network() {
  local network_name="$1"

  # Check if the network exists
  if docker network inspect "$network_name" >/dev/null 2>&1; then
    docker network rm "$network_name" >/dev/null 2>&1
  else
    echo "Network '$network_name' does not exist."
  fi
}

peer() {
  local container_name_a="$1"
  local container_name_b="$2"

  [ -z "$container_name_a" ] && die "First Container name is required"
  [ -z "$container_name_b" ] && die "Second Container name is required"
  peer_network="${container_name_a}_${container_name_b}_peer"

  remove_network "$peer_network"
  add_network "$peer_network" "$container_name_a"
  add_network "$peer_network" "$container_name_b"
}

exec_command() {
  local container_name="$1"
  local command_to_execute="$2"
  local detached_flag="$3"

  if [ "$detached_flag" = "--detached" ]; then
    docker exec -d "$container_name" sh -c "$command_to_execute"
  else
    docker exec "$container_name" sh -c "$command_to_execute"
  fi
}

get_ip_address() {
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1"
}

case "$1" in
"pull")
  pull_image "$2"
  ;;
"run")
  if [ "$#" -eq 6 ] && [ "$5" == "-p" ]; then
    run_container "$2" "$3" "$4" "$5" "$6" # Include the additional argument for port mapping
  else
    run_container "$2" "$3" "$4" # Call run_container without port mapping
  fi
  ;;
"stop")
  stop_container "$2"
  ;;
"delete")
  delete_container "$2"
  ;;
"copy")
  copy "$2" "$3"
  ;;
"addnetwork")
  add_network "$2" "$3" "$4"
  ;;
"dscnetwork")
  disconnect_network "$2" "$3"
  ;;
"rmnetwork")
  remove_network "$2"
  ;;
"peer")
  peer "$2" "$3" "$4"
  ;;
"exec")
  exec_command "$2" "$3"
  ;;
"ip")
  get_ip_address "$2"
  ;;
*)
  echo "Usage: $0 {pull|run|stop|copy|addnetwork|peer|exec|ip} [arguments...]"
  exit 1
  ;;
esac
