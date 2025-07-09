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
- [`drupal`](http://localhost) (Default port: `80`)
- [`solr`](http://localhost:8983) (Default port: `8983`)
- [`adminer`](http://localhost:8081) (Default port: `8081`)
- [`rdf4j`](http://localhost:7200) (Default port: `7200` )

To browse your services enter your domain and the port of the service (i.e. `localhost:7200`).

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
- `drupal-data`: Contains the Drupal root directory `/opt/drupal`
- `private_files`: Contains Drupal private files under `/var/www/private_files`
- `mariadb-data`: Contains `/var/lib/mysql`
- `solr-data`: Contains SOLR root dir `/var/solr`
- `rdf4j-data`: Contains rdf4j data under `/var/rdf4j`
- `rdf4j-logs`: Contains rdf4j logs `/usr/local/tomcat/logs`


You find these volumes under `/var/lib/docker/volumes/<compose-prefix>_<volume-name>/_data` (Linux - you have to be root to access) or at the location shown in your Docker Desktop settings (Premium Feature). Please check the right permissions, if you copy or alter files and folders.

### Custom Drupal modules
In case you want to develop or install custom Drupal modules, the `docker-compose.yml` also mounts the `custom` directory in this repo to the `modules/custom` directroy in the Drupal container.
For installation just copy the module source code into `custom` and you should be able to install the module via the Drupal `Extend` Module interface under [`/admin/modules`](http://localhost/admin/modules), or via the `drush` CLI (`docker compose exec drupal drush en MY_MODULE`).

### WissKI development
In case you wish to do WissKI development, start the stack once with `docker compose up -d` and wait for the Drupal/WissKI installation to finish.
You can check on the progress with `docker compose logs -f drupal`.
Once the installation is finished, shut down the stack with `docker compose down`.
Now clone the [WissKI repository](https://git.drupalcode.org/project/wisski) into this repo: `git clone https://git.drupalcode.org/project/wisski.git`.
To use this clone you will have to mount the cloned repo into the `/modules/contrib` directory of the docker container.
To do this add the following line into the `volumes` section of the `drupal` service in the `docker-compose.yml`.
```yaml
services:
  drupal:
    volumes:
      - ./wisski:/opt/drupal/web/modules/contrib/wisski
```
This will overwrite the default WissKI installtion from the Docker image.


