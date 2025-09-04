# Makefile cho realtime-log-analytics

# file compose chính cho InfluxDB
COMPOSE_DON = docker-compose.don.yml
# file compose Nginx web giả lập
COMPOSE_NGINX = docker-compose.nginx.yml

.PHONY: up-don down-don up-nginx down-nginx ps logs-don

## Start InfluxDB stack (don)
up-don:
	docker compose -f $(COMPOSE_DON) up -d

## Stop InfluxDB stack (don)
down-don:
	docker compose -f $(COMPOSE_DON) down

## Start Nginx web servers
up-nginx:
	docker compose -f $(COMPOSE_NGINX) up -d

## Stop Nginx web servers
down-nginx:
	docker compose -f $(COMPOSE_NGINX) down

## Show container status
ps:
	docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

## Tail logs của InfluxDB
logs-don:
	docker compose -f $(COMPOSE_DON) logs -f


