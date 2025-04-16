#!/bin/bash

echo "=== REINICIANDO CLUSTER POSTGRESQL CON PATRONI ==="

# Detener todos los contenedores
echo "Deteniendo contenedores..."
docker compose down

# Iniciar los contenedores en secuencia
echo "Iniciando Consul..."
docker compose up -d consul
sleep 10

echo "Iniciando nodo primario (pg1)..."
docker compose up -d pg1
sleep 45

echo "Iniciando nodos réplica (pg2, pg3) y HAProxy..."
docker compose up -d
sleep 45

echo "Cluster reiniciado."
echo "Usa ./monitor-cluster.sh para verificar el estado."
