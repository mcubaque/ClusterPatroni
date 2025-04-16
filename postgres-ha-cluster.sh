#!/bin/bash

# === PostgreSQL HA: Configuración de Cluster con Patroni ===
# Este script configura un cluster PostgreSQL de alta disponibilidad
# con un nodo maestro y dos réplicas, usando Patroni y Consul

if [ "$EUID" -ne 0 ]; then
  echo "Este script debe ejecutarse con sudo. Por favor ejecuta: sudo $0"
  exit 1
fi

echo "===================================================================="
echo "  CONFIGURANDO CLUSTER POSTGRESQL CON ALTA DISPONIBILIDAD (PATRONI)"
echo "===================================================================="

# Arreglar permisos de Docker
chmod 666 /var/run/docker.sock

# Detener y eliminar contenedores existentes
echo "[1/8] Limpiando entorno anterior..."
docker rm -f pg1 pg2 pg3 consul haproxy etcd 2>/dev/null || true
docker compose down --remove-orphans 2>/dev/null || true

# Limpiar directorios completamente
echo "[2/8] Preparando directorios..."
rm -rf data configs
mkdir -p configs/haproxy configs/init

# Script de inicialización para configurar correctamente los nodos
cat > configs/init/init.sh << 'EOF'
#!/bin/bash
set -e

# Crear directorios con permisos correctos
mkdir -p /home/postgres/pgdata
chown postgres:postgres /home/postgres/pgdata
chmod 700 /home/postgres/pgdata

# Crear archivo de configuración para Patroni
cat > /home/postgres/patroni.yml << EOFCONF
scope: postgres
namespace: /service/
name: ${PATRONI_NAME}

restapi:
  listen: 0.0.0.0:8008
  connect_address: ${PATRONI_RESTAPI_CONNECT_ADDRESS}

consul:
  host: consul:8500

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        max_connections: 100
        shared_buffers: 256MB
        wal_level: replica
        hot_standby: "on"
        wal_keep_size: 128MB
        max_wal_senders: 10
        max_replication_slots: 10
        wal_log_hints: "on"
        log_timezone: 'UTC'
        timezone: 'UTC'
        listen_addresses: '*'

  initdb:
    - encoding: UTF8
    - data-checksums
    - locale: en_US.UTF8

postgresql:
  listen: 0.0.0.0:5432
  connect_address: ${PATRONI_POSTGRESQL_CONNECT_ADDRESS}
  data_dir: /home/postgres/pgdata
  bin_dir: /usr/lib/postgresql/15/bin
  pgpass: /tmp/pgpass
  authentication:
    replication:
      username: replicator
      password: replicatorpassword
    superuser:
      username: postgres
      password: postgres
  pg_hba:
    - host replication replicator 0.0.0.0/0 md5
    - host all postgres 0.0.0.0/0 md5
    - host all all 0.0.0.0/0 md5

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOFCONF

# Asegurar permisos del archivo de configuración
chown postgres:postgres /home/postgres/patroni.yml
chmod 600 /home/postgres/patroni.yml

# Crear archivo .pgpass para conexiones sin contraseña
cat > /tmp/pgpass << EOFPGPASS
*:*:*:postgres:postgres
*:*:*:replicator:replicatorpassword
EOFPGPASS
chmod 600 /tmp/pgpass
chown postgres:postgres /tmp/pgpass

# Configurar variables de entorno para evitar solicitud de contraseña
export PGPASSWORD=postgres

# Iniciar Patroni como el usuario postgres
exec su - postgres -c "patroni /home/postgres/patroni.yml"
EOF

chmod +x configs/init/init.sh

# Crear configuración HAProxy
echo "[3/8] Creando configuración HAProxy..."
cat > configs/haproxy/haproxy.cfg << EOF
global
    maxconn 100
    log stdout format raw local0

defaults
    log global
    mode tcp
    retries 2
    timeout client 30m
    timeout connect 4s
    timeout server 30m
    timeout check 5s

listen stats
    mode http
    bind *:5000
    stats enable
    stats uri /
    stats refresh 5s

listen primary
    bind *:5432
    option httpchk GET /master
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server pg1 pg1:5432 maxconn 100 check port 8008 inter 5s rise 1 fall 1
    server pg2 pg2:5432 maxconn 100 check port 8008 inter 5s rise 1 fall 1 backup
    server pg3 pg3:5432 maxconn 100 check port 8008 inter 5s rise 1 fall 1 backup

listen replicas
    bind *:5433
    option httpchk GET /replica
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server pg1 pg1:5432 maxconn 100 check port 8008 inter 5s rise 1 fall 1
    server pg2 pg2:5432 maxconn 100 check port 8008 inter 5s rise 1 fall 1
    server pg3 pg3:5432 maxconn 100 check port 8008 inter 5s rise 1 fall 1
EOF

# Crear configuración para PostgreSQL sin solicitud de contraseña
cat > configs/init/psql.conf << 'EOF'
*:*:*:postgres:postgres
EOF

# Crear docker-compose.yml
echo "[4/8] Creando docker-compose.yml..."
cat > docker-compose.yml << EOF
services:
  consul:
    container_name: consul
    image: hashicorp/consul:latest
    ports:
      - "8500:8500"
    command: agent -server -bootstrap-expect=1 -client=0.0.0.0 -ui
    networks:
      - postgres-network

  pg1:
    container_name: pg1
    image: registry.opensource.zalan.do/acid/spilo-15:3.0-p1
    environment:
      - SCOPE=postgres
      - PGVERSION=15
      - PATRONI_NAME=pg1
      - PATRONI_POSTGRESQL_CONNECT_ADDRESS=pg1:5432
      - PATRONI_RESTAPI_CONNECT_ADDRESS=pg1:8008
      - PGPASSWORD=postgres
    volumes:
      - ./configs/init/init.sh:/init.sh
      - ./configs/init/psql.conf:/root/.pgpass
    command: ["/init.sh"]
    ports:
      - "5432:5432"
      - "8008:8008"
    networks:
      - postgres-network
    depends_on:
      - consul

  pg2:
    container_name: pg2
    image: registry.opensource.zalan.do/acid/spilo-15:3.0-p1
    environment:
      - SCOPE=postgres
      - PGVERSION=15
      - PATRONI_NAME=pg2
      - PATRONI_POSTGRESQL_CONNECT_ADDRESS=pg2:5432
      - PATRONI_RESTAPI_CONNECT_ADDRESS=pg2:8008
      - PGPASSWORD=postgres
    volumes:
      - ./configs/init/init.sh:/init.sh
      - ./configs/init/psql.conf:/root/.pgpass
    command: ["/init.sh"]
    ports:
      - "5433:5432"
      - "8009:8008"
    networks:
      - postgres-network
    depends_on:
      - consul
      - pg1

  pg3:
    container_name: pg3
    image: registry.opensource.zalan.do/acid/spilo-15:3.0-p1
    environment:
      - SCOPE=postgres
      - PGVERSION=15
      - PATRONI_NAME=pg3
      - PATRONI_POSTGRESQL_CONNECT_ADDRESS=pg3:5432
      - PATRONI_RESTAPI_CONNECT_ADDRESS=pg3:8008
      - PGPASSWORD=postgres
    volumes:
      - ./configs/init/init.sh:/init.sh
      - ./configs/init/psql.conf:/root/.pgpass
    command: ["/init.sh"]
    ports:
      - "5434:5432"
      - "8010:8008"
    networks:
      - postgres-network
    depends_on:
      - consul
      - pg1

  haproxy:
    container_name: haproxy
    image: haproxy:latest
    volumes:
      - ./configs/haproxy:/usr/local/etc/haproxy
    ports:
      - "5000:5000"   # Stats
      - "5435:5432"   # Write
      - "5436:5433"   # Read
    networks:
      - postgres-network
    depends_on:
      - pg1
      - pg2
      - pg3

networks:
  postgres-network:
    driver: bridge
EOF

# Ajustar permisos
chmod -R 777 configs
chmod 600 configs/init/psql.conf

# Iniciar los contenedores en secuencia
echo "[5/8] Iniciando Consul..."
docker compose up -d consul
sleep 10

# Crear scripts de verificación para usar en los comandos
cat > psql-cmd.sh << 'EOF'
#!/bin/bash
PGPASSWORD=postgres psql -h localhost -U postgres "$@"
EOF
chmod +x psql-cmd.sh

echo "[6/8] Iniciando nodo primario (pg1)..."
docker compose up -d pg1
sleep 60  # Tiempo suficiente para inicialización completa

# Verificar que el nodo primario está funcionando
echo "Verificando que el nodo primario (pg1) está en funcionamiento..."
MAX_RETRY=10
RETRY=0
PG1_READY=false

while [ $RETRY -lt $MAX_RETRY ]; do
  if docker exec -i pg1 curl -s http://localhost:8008 | grep -q "role"; then
    echo "✅ Nodo primario pg1 está listo"
    PG1_READY=true
    break
  else
    RETRY=$((RETRY+1))
    echo "⏳ Esperando a que el nodo primario esté listo (intento $RETRY/$MAX_RETRY)..."
    sleep 15
  fi
done

if [ "$PG1_READY" = false ]; then
  echo "❌ El nodo primario no pudo iniciarse correctamente después de varios intentos."
  echo "Revisa los logs con: docker logs pg1"
  exit 1
fi

echo "[7/8] Iniciando nodos réplica (pg2, pg3) y HAProxy..."
docker compose up -d
sleep 60  # Tiempo suficiente para inicialización completa

# Verificar que el cluster está funcionando
echo "[8/8] Verificando estado del cluster..."
echo "Estado de los contenedores:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Verificar estado de Patroni en cada nodo
echo -e "\nVerificando estado de Patroni en cada nodo:"
for node in pg1 pg2 pg3; do
  echo -n "$node: "
  docker exec -i $node curl -s http://localhost:8008 | grep role || echo "No disponible"
done

# Crear tabla de prueba en el nodo primario
echo -e "\nCreando tabla de prueba en el nodo primario..."
docker exec -i -e PGPASSWORD=postgres pg1 psql -h localhost -U postgres -c "CREATE TABLE IF NOT EXISTS test_table (id serial PRIMARY KEY, name VARCHAR(50));"
docker exec -i -e PGPASSWORD=postgres pg1 psql -h localhost -U postgres -c "INSERT INTO test_table (name) VALUES ('Test inicial'), ('Test secundario');"

# Verificar que los datos se han creado en el nodo primario
echo -e "\nVerificando datos en el nodo primario:"
docker exec -i -e PGPASSWORD=postgres pg1 psql -h localhost -U postgres -c "SELECT * FROM test_table;"

# Esperar para que la replicación ocurra
echo -e "\nEsperando a que la replicación ocurra (20 segundos)..."
sleep 20

# Verificar replicación en los nodos secundarios
echo -e "\nVerificando replicación en nodos secundarios:"
for node in pg2 pg3; do
  echo "$node:"
  docker exec -i -e PGPASSWORD=postgres $node psql -h localhost -U postgres -c "SELECT * FROM test_table;" || echo "La replicación aún no está completa en $node"
done

# Crear scripts adicionales para administración
echo "Creando scripts adicionales para administración..."

# Script para probar failover
cat > test-failover.sh << 'EOF'
#!/bin/bash

echo "=== PRUEBA DE FAILOVER DEL CLUSTER POSTGRESQL CON PATRONI ==="

# Verificar el estado inicial del cluster
echo "Estado inicial del cluster:"
docker exec -i pg1 curl -s http://localhost:8008/cluster || echo "No se puede obtener el estado del cluster"

# Identificar el nodo líder actual
echo "Identificando el nodo líder actual..."
LEADER=""
for node in pg1 pg2 pg3; do
  if docker exec -i $node curl -s http://localhost:8008 | grep -q '"role":"master"'; then
    LEADER=$node
    echo "El líder actual es: $LEADER"
    break
  fi
done

if [ -z "$LEADER" ]; then
  echo "No se pudo identificar un líder. Abortando prueba."
  exit 1
fi

# Insertar datos antes del failover
echo "Insertando datos antes del failover..."
docker exec -i -e PGPASSWORD=postgres $LEADER psql -h localhost -U postgres -c "INSERT INTO test_table (name) VALUES ('Antes del failover');"
docker exec -i -e PGPASSWORD=postgres $LEADER psql -h localhost -U postgres -c "SELECT * FROM test_table;"

# Detener el nodo líder
echo "Deteniendo el nodo líder ($LEADER)..."
docker stop $LEADER
echo "Esperando 30 segundos para el failover..."
sleep 30

# Identificar el nuevo líder
NEW_LEADER=""
for node in pg1 pg2 pg3; do
  if [ "$node" != "$LEADER" ] && docker ps -q -f name=$node | grep -q .; then
    if docker exec -i $node curl -s http://localhost:8008 | grep -q '"role":"master"'; then
      NEW_LEADER=$node
      echo "El nuevo líder es: $NEW_LEADER"
      break
    fi
  fi
done

if [ -z "$NEW_LEADER" ]; then
  echo "No se pudo identificar un nuevo líder. Revisar el estado del cluster."
  exit 1
fi

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
for node in pg1 pg2 pg3; do
  if docker ps -q -f name=$node | grep -q .; then
    echo "Verificando datos en $node:"
    docker exec -i -e PGPASSWORD=postgres $node psql -h localhost -U postgres -c "SELECT * FROM test_table;" || echo "No se pueden leer los datos en $node."
  fi
done

echo "=== PRUEBA DE FAILOVER COMPLETADA ==="
EOF

chmod +x test-failover.sh

# Script de monitoreo
cat > monitor-cluster.sh << 'EOF'
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
EOF

chmod +x monitor-cluster.sh

# Script para reiniciar el cluster
cat > restart-cluster.sh << 'EOF'
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
EOF

chmod +x restart-cluster.sh

echo -e "\n===================================================================="
echo "       CLUSTER POSTGRESQL HA CONFIGURADO Y LISTO PARA USAR"
echo "===================================================================="
echo "✅ Cluster PostgreSQL con alta disponibilidad (Patroni) configurado:"
echo "- Conexión escritura (siempre al líder): localhost:5435"
echo "- Conexión lectura (balanceada entre nodos): localhost:5436"
echo "- Panel de estadísticas HAProxy: http://localhost:5000"
echo "- Interfaz de Consul: http://localhost:8500"
echo "- Usuario: postgres, Contraseña: postgres"
echo -e "\nHerramientas de administración:"
echo "- ./test-failover.sh - Prueba la funcionalidad de alta disponibilidad"
echo "- ./monitor-cluster.sh - Muestra el estado del cluster en tiempo real"
echo "- ./restart-cluster.sh - Reinicia el cluster completo"
echo -e "\n⚠️ NOTA: La inicialización completa puede tardar varios minutos."
echo "Si los nodos réplica no se sincronizan inmediatamente, espera unos minutos"
echo "más antes de preocuparte. La replicación debería establecerse eventualmente."
echo "===================================================================="
