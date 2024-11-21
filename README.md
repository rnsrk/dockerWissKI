# Docker WissKI

## Prerequisites

### Get the data
Clone the repository. In case of problems with large files just download the zip.

### Linux
Install [Docker](https://docs.docker.com/get-docker/). You may want to apply some [post-installation steps](https://docs.docker.com/engine/install/linux-postinstall/). 

### Windows
Install [Docker Desktop](https://docs.docker.com/get-docker/). You may need to install the [WSL 2 Linux kernel](https://docs.microsoft.com/de-de/windows/wsl/install-win10).  

**Beware if you are using Virtualization software like VirtualBox, they may conflict with your Docker-Software in Windows.**

You need a GraphDB standalone server zip file. Apply on the [GraphDB free downloadpage](https://www.ontotext.com/products/graphdb/graphdb-free/), they will send you an email with a link to the stand alone server; safe the file as `graphdb.zip` in the `graphdb_context` folder. 

## Setup
Open `.env.sample` file, provide the credentials and ports according to your needs and save it as `.env`.

## Start
Run `docker compose up -d` to start containers in background.

## Logs
You can check the logs of each container by typing `docker compose logs -f <service-name>`, i.e. `docker compose logs -f drupal`.

## Docker compose environment

### Services
There are five services corresponding to four containers
- `drupal` (Default port: `80`)
- `graphdb` (Defa `3306`)
- `adminer` (Default port: `8081`)
- `solr` (Default port: `8983`)

To browse your services enter your domain and the port of the service (i.e. `localhost:7200` if you installed it on your local machine and left the default graphdb port).

### Editing
If you want to jump into a container, open a console and type
```sh
docker compose exec -it <service> bash
```
for example 
```sh
docker compose exec -it drupal bash
```
gets you into the drupal container.

### Volumes
- drupal-data: Contains the Drupal root directory /opt/drupal
- private_files: Contains Drupal private files under /var/www/private_files
- mariadb-data: Contains /var/lib/mysql
- solr-data: Contains SORL root dir /var/solr
- graphdb-data: Contains /graphdb


You find these volumes under `/var/lib/docker/volumes/<compose-prefix>_<volume-name>/_data` (Linux - you have to be root to access) or at the location shown in your Docker Desktop settings (Premium Feature). Please check the right permissions, if you copy or alter files and folders.

