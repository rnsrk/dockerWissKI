# Docker WissKI

This repository provides a ready-to-use Docker environment for WissKI, based on Drupal. It includes the following components:

- **[Drupal/WissKI](https://wiss-ki.eu/)**: The main content management system and WissKI extension for semantic data management.
  - Comes with preconfigured connection to MariaDB database and RDF4J triplestore (Solr integration has to be configured manually)
  - Has the [WissKI Default Data Model](https://www.drupal.org/project/wisski_default_data_model) included.
  - For Drupal/WissKI version and module setup, see [WissKI Base Image](https://github.com/soda-collections-objects-data-literacy/wisski-base-image)
- **[MariaDB](https://mariadb.org/)**: The relational database used by Drupal.
- **[RDF4J](https://rdf4j.org/)**: A triplestore for storing and querying semantic data (RDF).
- **[Adminer](https://www.adminer.org/)**: A lightweight database management tool for MariaDB.
- **[SOLR](https://solr.apache.org/)**: A powerful search server for indexing and searching site content.

## Prerequisites

### Get the data
Clone the repository. In case of problems with large files just download the zip.

### Linux
Install [Docker](https://docs.docker.com/get-docker/). You may want to apply some [post-installation steps](https://docs.docker.com/engine/install/linux-postinstall/).

### Windows
Install [Docker Desktop](https://docs.docker.com/get-docker/). You may need to install the [WSL 2 Linux kernel](https://docs.microsoft.com/de-de/windows/wsl/install-win10).

**Beware if you are using Virtualization software like VirtualBox, they may conflict with your Docker-Software in Windows.**

## Usage
To get started with Docker WissKI, follow these steps:

1. **Clone the repository**

   ```bash
   git clone https://github.com/rnsrk/dockerWissKI.git
   cd dockerWissKI
   ```

2. **Copy the example environment file**

   Copy the provided `.example-env` file to `.env`. This file contains all the environment variables needed for the Docker setup.

   ```bash
   cp .example-env .env
   ```

   You can edit the `.env` file to adjust settings such as database credentials, ports, and site name to fit your needs.

3. **Start the Docker Compose environment**

   Make sure Docker is running, then start all services with:

   ```bash
   docker compose up -d
   ```

   This will start all required containers (Drupal, MariaDB, SOLR, RDF4J, Adminer, etc.) in the background.

4. **Access the services**

   - **Drupal**: [http://localhost:3000](http://localhost:3000) (or the port you set in `.env`)
   - **Adminer** (database admin): [http://localhost:3001](http://localhost:3001)
   - **RDF4J**: [http://localhost:3002](http://localhost:3002)
   - **SOLR**: [http://localhost:3003](http://localhost:3003)

   Default credentials and other settings can be found or changed in your `.env` file.

5. **Stopping the environment**

   To stop all running containers, use:

   ```bash
   docker compose down
   ```

**Note:**
- The first startup may take a few minutes as Docker downloads the required images and initializes the services.
- For advanced configuration, review and adjust the `docker-compose.yml` and `.env` files as needed.
- If you encounter issues, ensure your Docker installation is up to date and that no other services are using the same ports.

## TODO

- [ ] SOLR preconfiguration for default model.
