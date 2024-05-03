# Synergia

Synergia is a docker orchestrator, which runs a LEADER container, a LOAD_BALANCER container, and multiple FOLLOWER containers. 
All these containers are in a network named `synergia`.

The entire setup acts as a counter service, accessible through an NGINX-based loader balancer.

## Pre-Requisites

```bash
sudo apt install python3-aiohttp python3-matplotlib curl apache2-utils -y
```

---

## Instructions

To run the orchestrator,

```bash
./orchestrator.sh run
```

To stop and delete the running containers and remove the created networks,

```bash
./orchestrator.sh reset
```

The URL for the service is `http://localhost:8080`.
```bash
curl http://localhost:8080
```

## Scaling

To scale the containers horizontally (to say `20` containers)
```bash
./orchestrator.sh scale --hor 20
```

To scale the containers vertically (to say `200MB` of memory, `200MB` of swap memory, and `2` CPU cores)
```bash
./orchestrator.sh scale --vert --memory=200m --memory-swap=200m --cpuset-cpus=2
```

## Testing

To manually test the service, run the following command
```bash
# ./orchestrator.sh test --num-request=1000
ab -n 1000 -c 10 http://localhost:8080/
```

## Benchmarking

To benchmark the service, run the following command
```bash
python3 benchmark.py
```