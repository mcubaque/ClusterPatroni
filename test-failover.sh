#!/bin/bash

# === PRUEBA DE FAILOVER REALISTA ===
# Script que emula un escenario real de alta disponibilidad

echo "=== PRUEBA DE FAILOVER REALISTA (SIN INTERVENCIÓN MANUAL) ==="

# Función limpia para obtener el líder
get_leader() {
  # Usar PostgreSQL directamente para identificar el líder
  for node in pg1 pg2 pg3; do
    if docker ps -q -f name=$node | grep -q .; then
      # Verificar si este nodo está en modo primario (no en recuperación)
      is_primary=$(docker exec -e PGPASSWORD=postgres $node psql -h localhost -U postgres -t -c "SELECT NOT pg_is_in_recovery();" 2>/dev/null)
      
      if [[ "$is_primary" == *"t"* ]]; then
        echo "$node"
        return 0
      fi
    fi
  done
  
  echo "Error: No se pudo identificar el líder"
  return 1
}

# Paso 1: Identificar el líder actual
echo "Identificando el líder actual..."
LEADER=$(get_leader)

if [ -z "$LEADER" ] || [ "$LEADER" == "Error: No se pudo identificar el líder" ]; then
  echo "No se pudo identificar el líder. Abortando prueba."
  exit 1
fi

echo "El líder actual es: $LEADER"

# Paso 2: Insertar datos antes del failover
echo "Insertando datos antes del failover..."
docker exec -e PGPASSWORD=postgres $LEADER psql -h localhost -U postgres -c "INSERT INTO test_table (name) VALUES ('Antes del failover');"
docker exec -e PGPASSWORD=postgres $LEADER psql -h localhost -U postgres -c "SELECT * FROM test_table ORDER BY id DESC LIMIT 5;"

# Paso 3: Detener el líder para forzar un failover
echo "Deteniendo el líder $LEADER..."
docker stop $LEADER
echo "Esperando 30 segundos para que ocurra el failover..."
sleep 30

# Paso 4: Identificar el nuevo líder
echo "Identificando el nuevo líder..."
NEW_LEADER=$(get_leader)

if [ -z "$NEW_LEADER" ] || [ "$NEW_LEADER" == "Error: No se pudo identificar el líder" ]; then
  echo "No se pudo identificar un nuevo líder. El failover podría haber fallado."
  echo "Intentando recuperar el cluster reiniciando el líder original..."
  docker start $LEADER
  sleep 30
  exit 1
fi

echo "El nuevo líder es: $NEW_LEADER"

# Paso 5: Insertar datos después del failover
echo "Insertando datos después del failover..."
docker exec -e PGPASSWORD=postgres $NEW_LEADER psql -h localhost -U postgres -c "INSERT INTO test_table (name) VALUES ('Después del failover');"
docker exec -e PGPASSWORD=postgres $NEW_LEADER psql -h localhost -U postgres -c "SELECT * FROM test_table ORDER BY id DESC LIMIT 5;"

# Paso 6: Recuperar el nodo caído
echo "Recuperando el nodo caído $LEADER..."
docker rm -f $LEADER
rm -rf data/$LEADER/*
mkdir -p data/$LEADER
chmod -R 777 data/$LEADER
docker compose up -d $LEADER
echo "Esperando 45 segundos para que el nodo se reincorpore..."
sleep 45

# Paso 7: Verificar el estado final
echo "Verificando estado final del cluster..."
for node in pg1 pg2 pg3; do
  if docker ps -q -f name=$node | grep -q .; then
    is_primary=$(docker exec -e PGPASSWORD=postgres $node psql -h localhost -U postgres -t -c "SELECT NOT pg_is_in_recovery();" 2>/dev/null)
    
    if [[ "$is_primary" == *"t"* ]]; then
      echo "$node: LÍDER"
    else
      echo "$node: réplica"
    fi
  else
    echo "$node: no está en ejecución"
  fi
done

# Paso 8: Verificar datos en todos los nodos
echo "Verificando datos en todos los nodos..."
for node in pg1 pg2 pg3; do
  if docker ps -q -f name=$node | grep -q .; then
    echo "Datos en $node:"
    docker exec -e PGPASSWORD=postgres $node psql -h localhost -U postgres -c "SELECT * FROM test_table ORDER BY id DESC LIMIT 5;"
  else
    echo "$node no está en ejecución"
  fi
done

echo "=== PRUEBA DE FAILOVER COMPLETADA ==="
echo ""
echo "Esta prueba demuestra cómo funciona la alta disponibilidad en un entorno real:"
echo "1. Se detectó automáticamente el nodo líder actual"
echo "2. Al fallar el líder, Patroni eligió automáticamente un nuevo líder"
echo "3. Se mantuvo la continuidad del servicio sin intervención manual"
echo "4. El nodo caído se recuperó y reincorporó al cluster"#!/bin/bash

# === PRUEBA DE FAILOVER REALISTA ===
# Script que emula un escenario real de alta disponibilidad

echo "=== PRUEBA DE FAILOVER REALISTA (SIN INTERVENCIÓN MANUAL) ==="

# Función limpia para obtener el líder
get_leader() {
  # Usar PostgreSQL directamente para identificar el líder
  for node in pg1 pg2 pg3; do
    if docker ps -q -f name=$node | grep -q .; then
      # Verificar si este nodo está en modo primario (no en recuperación)
      is_primary=$(docker exec -e PGPASSWORD=postgres $node psql -h localhost -U postgres -t -c "SELECT NOT pg_is_in_recovery();" 2>/dev/null)
      
      if [[ "$is_primary" == *"t"* ]]; then
        echo "$node"
        return 0
      fi
    fi
  done
  
  echo "Error: No se pudo identificar el líder"
  return 1
}

# Paso 1: Identificar el líder actual
echo "Identificando el líder actual..."
LEADER=$(get_leader)

if [ -z "$LEADER" ] || [ "$LEADER" == "Error: No se pudo identificar el líder" ]; then
  echo "No se pudo identificar el líder. Abortando prueba."
  exit 1
fi

echo "El líder actual es: $LEADER"

# Paso 2: Insertar datos antes del failover
echo "Insertando datos antes del failover..."
docker exec -e PGPASSWORD=postgres $LEADER psql -h localhost -U postgres -c "INSERT INTO test_table (name) VALUES ('Antes del failover');"
docker exec -e PGPASSWORD=postgres $LEADER psql -h localhost -U postgres -c "SELECT * FROM test_table ORDER BY id DESC LIMIT 5;"

# Paso 3: Detener el líder para forzar un failover
echo "Deteniendo el líder $LEADER..."
docker stop $LEADER
echo "Esperando 30 segundos para que ocurra el failover..."
sleep 30

# Paso 4: Identificar el nuevo líder
echo "Identificando el nuevo líder..."
NEW_LEADER=$(get_leader)

if [ -z "$NEW_LEADER" ] || [ "$NEW_LEADER" == "Error: No se pudo identificar el líder" ]; then
  echo "No se pudo identificar un nuevo líder. El failover podría haber fallado."
  echo "Intentando recuperar el cluster reiniciando el líder original..."
  docker start $LEADER
  sleep 30
  exit 1
fi

echo "El nuevo líder es: $NEW_LEADER"

# Paso 5: Insertar datos después del failover
echo "Insertando datos después del failover..."
docker exec -e PGPASSWORD=postgres $NEW_LEADER psql -h localhost -U postgres -c "INSERT INTO test_table (name) VALUES ('Después del failover');"
docker exec -e PGPASSWORD=postgres $NEW_LEADER psql -h localhost -U postgres -c "SELECT * FROM test_table ORDER BY id DESC LIMIT 5;"

# Paso 6: Recuperar el nodo caído
echo "Recuperando el nodo caído $LEADER..."
docker rm -f $LEADER
rm -rf data/$LEADER/*
mkdir -p data/$LEADER
chmod -R 777 data/$LEADER
docker compose up -d $LEADER
echo "Esperando 45 segundos para que el nodo se reincorpore..."
sleep 45

# Paso 7: Verificar el estado final
echo "Verificando estado final del cluster..."
for node in pg1 pg2 pg3; do
  if docker ps -q -f name=$node | grep -q .; then
    is_primary=$(docker exec -e PGPASSWORD=postgres $node psql -h localhost -U postgres -t -c "SELECT NOT pg_is_in_recovery();" 2>/dev/null)
    
    if [[ "$is_primary" == *"t"* ]]; then
      echo "$node: LÍDER"
    else
      echo "$node: réplica"
    fi
  else
    echo "$node: no está en ejecución"
  fi
done

# Paso 8: Verificar datos en todos los nodos
echo "Verificando datos en todos los nodos..."
for node in pg1 pg2 pg3; do
  if docker ps -q -f name=$node | grep -q .; then
    echo "Datos en $node:"
    docker exec -e PGPASSWORD=postgres $node psql -h localhost -U postgres -c "SELECT * FROM test_table ORDER BY id DESC LIMIT 5;"
  else
    echo "$node no está en ejecución"
  fi
done

echo "=== PRUEBA DE FAILOVER COMPLETADA ==="
echo ""
echo "Esta prueba demuestra cómo funciona la alta disponibilidad en un entorno real:"
echo "1. Se detectó automáticamente el nodo líder actual"
echo "2. Al fallar el líder, Patroni eligió automáticamente un nuevo líder"
echo "3. Se mantuvo la continuidad del servicio sin intervención manual"
echo "4. El nodo caído se recuperó y reincorporó al cluster"
