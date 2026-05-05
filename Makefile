.PHONY: build up down logs test clean shell backup health

build:
	docker-compose build

up:
	docker-compose up -d

down:
	docker-compose down

logs:
	docker-compose logs -f api

test:
	@echo "Running health check..."
	@curl -sf http://localhost:$${APP_PORT:-8000}/health | python3 -m json.tool
	@echo "\nHealth check passed."

clean:
	docker-compose down --rmi all --volumes --remove-orphans

shell:
	docker-compose exec api bash

backup:
	bash scripts/backup.sh

health:
	bash scripts/health-monitor.sh
