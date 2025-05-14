#!/bin/bash
# Script para instalar Docker en Ubuntu Server

echo "Actualizando los repositorios..."
sudo apt update

echo "Instalando paquetes necesarios..."
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common

echo "Añadiendo la clave GPG oficial de Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "Configurando el repositorio estable de Docker..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "Actualizando los repositorios con Docker..."
sudo apt update

echo "Instalando Docker..."
sudo apt install -y docker-ce docker-ce-cli containerd.io

echo "Habilitando e iniciando el servicio Docker..."
sudo systemctl enable docker
sudo systemctl start docker

echo "Añadiendo el usuario actual al grupo docker..."
sudo usermod -aG docker $USER

echo "Verificando la instalación de Docker..."
sudo docker --version

echo "Instalación de Docker completada. Necesitarás cerrar sesión y volver a iniciarla para usar Docker sin sudo."
