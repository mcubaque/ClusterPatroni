#!/bin/bash

echo "=== PRUEBA DE FAILOVER DEL CLUSTER POSTGRESQL CON PATRONI ==="

# Verificar el estado inicial del cluster
echo "Estado inicial del cluster:"
CLUSTER_STATE=$(docker exec -i pg1 curl -s http://localhost:8008/cluster)
echo "$CLUSTER_STATE"

# Identificar el nodo líder actual desde la respuesta de /cluster
echo "Identificando el nodo líder actual..."
LEADER=$(echo "$CLUSTER_STATE" | grep -o '"name":"[^"]*","role":"leader"' | head -1 | cut -d'"' -f4)

if [ -z "$LEADER" ]; then
  echo "No se pudo identificar un líder automáticamente."
  echo "Por favor, ingresa manualmente el nombre del nodo líder (pg1, pg2, pg3):"
  read -p "> " LEADER
  
  if [ -z "$LEADER" ]; then
    echo "No se proporcionó un líder. Abortando prueba."
    exit 1
  fi
  
  echo "Usando $LEADER como nodo líder."
fi

echo "El líder actual es: $LEADER"

# Insertar datos antes del failover
echo "Insertando datos antes del failover..."
docker exec -i -e PGPASSWORD=postgres $LEADER psql -h localhost -U postgres -c "INSERT INTO test_table (name) VALUES ('Antes del failover');"
docker exec -i -e PGPASSWORD=postgres $LEADER psql -h localhost -U postgres -c "SELECT * FROM test_table;"

# Detener el nodo líder
echo "Deteniendo el nodo líder ($LEADER)..."
docker stop $LEADER
echo "Esperando 30 segundos para el failover..."
sleep 30

# Lista de posibles réplicas que podrían convertirse en líder
OTHER_NODES=($(echo "pg1 pg2 pg3" | sed "s/$LEADER//"))

# Verificar si alguno de los otros nodos se ha convertido en líder
echo "Verificando cuál nodo se ha convertido en el nuevo líder..."
NEW_LEADER=""

# Verificar el estado actual del cluster con cualquier nodo disponible
for node in "${OTHER_NODES[@]}"; do
  CLUSTER_STATE=$(docker exec -i $node curl -s http://localhost:8008/cluster 2>/dev/null)
  if [ ! -z "$CLUSTER_STATE" ]; then
    NEW_LEADER=$(echo "$CLUSTER_STATE" | grep -o '"name":"[^"]*","role":"leader"' | head -1 | cut -d'"' -f4)
    if [ ! -z "$NEW_LEADER" ]; then
      break
    fi
  fi
done

if [ -z "$NEW_LEADER" ]; then
  echo "No se pudo identificar un nuevo líder automáticamente."
  echo "Por favor, ingresa manualmente el nombre del nuevo nodo líder (pg1, pg2, pg3):"
  read -p "> " NEW_LEADER
  
  if [ -z "$NEW_LEADER" ]; then
    echo "No se proporcionó un nuevo líder. Abortando prueba."
    exit 1
  fi
fi

echo "El nuevo líder es: $NEW_LEADER"

# Insertar datos después del failover
echo "Insertando datos después del failover..."
docker exec -i -e PGPASSWORD=postgres $NEW_LEADER psql -h localhost -U postgres -c "INSERT INTO test_table (name) VALUES ('Después del failover');"
docker exec -i -e PGPASSWORD=postgres $NEW_LEADER psql -h localhost -U postgres -c "SELECT * FROM test_table;"

# Reiniciar el nodo original
echo "Reiniciando el nodo original..."
docker start $LEADER
echo "Esperando 30 segundos para que el nodo se reincorpore..."
sleep 30

# Verificar que el nodo original se ha unido como réplica
echo "Verificando estado del cluster después de reiniciar el nodo original..."
docker exec -i $NEW_LEADER curl -s http://localhost:8008/cluster

# Verificar datos en todos los nodos
echo "Verificando datos en todos los nodos..."
for node in pg1 pg2 pg3; do
  if docker ps -q -f name=$node | grep -q .; then
    echo "Verificando datos en $node:"
    docker exec -i -e PGPASSWORD=postgres $node psql -h localhost -U postgres -c "SELECT * FROM test_table;" || echo "No se pueden leer los datos en $node."
  fi
done

echo "=== PRUEBA DE FAILOVER COMPLETADA ==="
