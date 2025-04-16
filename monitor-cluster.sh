#!/bin/bash

# Script para monitorear el estado del cluster PostgreSQL con Patroni
clear
echo "=== MONITOR DEL CLUSTER POSTGRESQL CON PATRONI ==="
echo "Presiona Ctrl+C para salir"
echo ""

while true; do
  echo "Fecha y hora: $(date)"
  echo "Estado del cluster:"
  
  for node in pg1 pg2 pg3; do
    if docker ps -q -f name=$node | grep -q .; then
      echo -n "$node: "
      ROLE=$(docker exec -i $node curl -s http://localhost:8008 | grep role | sed 's/.*"role":"\([^"]*\)".*/\1/')
      if [ ! -z "$ROLE" ]; then
        echo "$ROLE"
      else
        echo "No disponible"
      fi
    else
      echo "$node: No está en ejecución"
    fi
  done
  
  echo ""
  echo "Estado de los contenedores:"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  
  echo ""
  echo "Actualizando en 5 segundos..."
  sleep 5
  clear
done
