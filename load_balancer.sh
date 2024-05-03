#!/bin/bash

create_nginx_conf() {
  N_list=$(docker ps --format '{{.Names}}' | grep -E '^f[0-9]+$' | sort)
  NG=""

  NG+="worker_processes auto;\n"
  NG+="events { worker_connections 1024; }\n"
  NG+="http {\n"
  NG+="\tupstream all {\n"
  for i in $N_list; do
    NG+="\t\tserver $i:8080;\n"
  done
  NG+="\t}\n"
  NG+="\tserver {\n"
  NG+="\t\tlisten 8080;\n"
  NG+="\t\tlocation / {\n"
  NG+="\t\t\tproxy_pass http://all/;\n"
  NG+="\t\t}\n"
  NG+="\t}\n"
  NG+="}\n"

  echo -e $NG >nginx.conf
}

run() {
  docker stop load_balancer
  docker rm load_balancer
  create_nginx_conf
  docker build -t lb_nginx -f Dockerfile.lb .
  rm nginx.conf
  docker run -d --name load_balancer --network synergia -p 8080:8080 lb_nginx
  docker update --memory=100m --memory-swap=100m --cpuset-cpus=1 load_balancer
}

reload() {
  create_nginx_conf
  docker cp nginx.conf load_balancer:/etc/nginx/nginx.conf
  docker exec -it load_balancer nginx -s reload
  rm nginx.conf
}

case "$1" in
"run")
  run
  ;;
"reload")
  reload
  ;;
*)
  echo "Usage: $0 {run|add|reset} [arguments...]"
  exit 1
  ;;
esac
