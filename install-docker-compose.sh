#!/bin/bash
# Script para instalar Docker Compose en Ubuntu Server

echo "Instalando Docker Compose..."
sudo apt update

# Para Ubuntu 20.04 o superior - instala usando el paquete docker-compose-plugin
sudo apt install -y docker-compose-plugin

# Verificamos la instalación
echo "Verificando la instalación de Docker Compose..."
docker compose version

echo "Instalación de Docker Compose completada."
