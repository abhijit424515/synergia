#!/bin/bash
clear

# ---------------- PARAMS ----------------

INIT_NODES=10     # Number of initial nodes (upto ~150 for 8GB RAM VM)
STRATEGY="random" # random | round-robin | least-connections | ip-hash

BUILD_IMG=true

CON_FLAGS="--memory=100m --memory-swap=100m --cpuset-cpus=1"
LEADER="leader"
ORIG_IMG="alpine:latest"
IMAGE_NAME="custom_image"
NETWORK="synergia"
PORT_OFFSET=3000
TARGET="sng"

# ---------------- FUNCTIONS ----------------

LEADER_IP=""

print_header() {
  echo -e "\e[32m$@\e[0m"
}

cleanup() {
  ./conductor.sh stop $1 >/dev/null
  ./conductor.sh delete $1 >/dev/null
}

cleanup_all() {
  NODES=$(docker ps -a | wc -l)
  NODES=$(($NODES - 3))

  for i in $(seq 1 $NODES); do
    cleanup "f$i" &
  done
  cleanup $LEADER &
  cleanup load_balancer &
  wait

  ./conductor.sh rmnetwork $NETWORK
}

prepare_image() {
  temp_image_name="TEMP"

  print_header "---- SETUP >> PREPARE IMAGE ----\n"
  ./conductor.sh stop $temp_image_name
  ./conductor.sh delete $temp_image_name
  docker image rm -f $IMAGE_NAME >/dev/null 2>&1
  docker pull $ORIG_IMG
  docker run --name $temp_image_name $ORIG_IMG /bin/sh -c "apk update && apk add --no-cache build-base iproute2 python3 py3-pip py3-aiohttp py3-requests && rm -rf /var/cache/apk/* && pip install hypercorn quart --break-system-packages"
  docker commit $temp_image_name $IMAGE_NAME

  ./conductor.sh stop $temp_image_name
  ./conductor.sh delete $temp_image_name
  sleep 0.1 && clear
}

build() {
  rm -f $TARGET
  cargo build --release --manifest-path synergia/Cargo.toml
  cp -f synergia/target/release/synergia $TARGET
  clear
}

find_ipv4_in_network() {
  docker network inspect "$NETWORK" | jq -r --arg cname "$1" '.[0].Containers | .[] | select(.Name == $cname) | .IPv4Address' | sed 's/\([0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+\)\/[0-9]\+/\1/g'
}

leader() {
  # 1. Clean up
  print_header "---- LEADER >> CLEAN UP ----\n"
  cleanup $LEADER

  # 2. Run the LEADER container
  print_header "---- LEADER >> RUN CONTAINER ----\n"
  ./conductor.sh run $IMAGE_NAME $LEADER "sleep inf"
  docker update $CON_FLAGS $LEADER

  # 3. Copy the services
  print_header "---- LEADER >> COPY SERVICE ----\n"
  ./conductor.sh copy ./services/counter-service $LEADER:/counter-service

  # 4. Make service
  print_header "---- LEADER >> MAKE SERVICE ----\n"
  ./conductor.sh exec $LEADER "make -C /counter-service > /dev/null 2>&1" --detached && wait

  # 6. Run the service in the container
  print_header "---- LEADER >> RUN SERVICE ----\n"
  ./conductor.sh exec $LEADER "sh /counter-service/run.sh &" --detached
}

add_follower() {
  FOLLOWER="f$1"
  FOLLOWER_MAPPED_PORT="$2"

  # 1. Clean up
  print_header "---- FOLLOWER >> CLEAN UP ----\n"
  cleanup $FOLLOWER

  # 2. Run the FOLLOWER container
  print_header "---- FOLLOWER >> RUN CONTAINER ----\n"
  ./conductor.sh run $IMAGE_NAME $FOLLOWER "sleep inf" -p $FOLLOWER_MAPPED_PORT:8080
  docker update $CON_FLAGS $FOLLOWER

  # 3. Copy the services
  print_header "---- FOLLOWER >> COPY SERVICE ----\n"
  ./conductor.sh copy ./services/external-service $FOLLOWER:/external-service

  # 4. Configure network
  print_header "---- FOLLOWER >> CONFIGURE NETWORK ----\n"
  ./conductor.sh addnetwork $NETWORK $FOLLOWER

  # 5. Run the services in the containers
  print_header "---- FOLLOWER >> RUN SERVICES ----\n"
  ./conductor.sh exec $FOLLOWER "sh /external-service/run.sh http://$LEADER_IP:8080 &" --detached
}

run() {
  start_time=$(date +%s)

  # ---------------- CONTAINERS ----------------

  $BUILD_IMG && prepare_image
  leader

  ./conductor.sh addnetwork $NETWORK $LEADER
  LEADER_IP=$(find_ipv4_in_network $LEADER)

  for i in $(seq 1 $INIT_NODES); do
    port=$(($PORT_OFFSET + i))
    add_follower $i $port &
  done
  wait

  # ---------------- BALANCER ----------------

  print_header "---- STARTING LOAD BALANCER ----\n"
  ./load_balancer.sh run
  wait && sleep 2 
  ./load_balancer.sh reload # for an unresolved nginx error, need to reload config

  end_time=$(date +%s)
  startup_time=$((end_time - start_time))

  clear
  echo -e "\e[34m---- STARTUP_TIME: "${startup_time}s" ----\e[0m"
  url=$(find_ipv4_in_network load_balancer)

  if [ -z "$url" ]; then
    echo "Load balancer hostname failure. Please rerun the script. Exiting..."
    exit 1
  fi

  echo -e "\e[32mURLS:\n\thttp://"$url:8080"\n\thttp://localhost:8080\e[0m"
}

case "$1" in
"run")
  run
  ;;
"reset")
  cleanup_all
  ;;
"add")
  LEADER_IP=$(find_ipv4_in_network $LEADER)
  add_follower $2 $(($PORT_OFFSET + $2)) >/dev/null
  ;;
"rm")
  cleanup $2
  ;;
"scale")
  python3 scale.py "${@:2}"
  ;;
"test")
  python3 load_test.py http://localhost:8080 "${@:2}"
  ;;
*)
  echo "Usage: $0 {run|add|reset} [arguments...]"
  exit 1
  ;;
esac
