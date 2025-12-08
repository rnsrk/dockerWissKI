# Docker WissKI Stack

## About

### Introduction

This repository provides a complete, production-ready Docker environment for **WissKI** (Wissenschaftliche Kommunikations-Infrastruktur - Scientific Communication Infrastructure), a specialized Drupal distribution designed for managing and publishing scientific knowledge in the humanities and cultural heritage sectors.

WissKI extends Drupal with semantic web capabilities, enabling you to:
- Store and manage structured data using RDF/OWL ontologies
- Connect to triplestore databases for semantic queries and reasoning
- Build knowledge graphs and interconnected data networks
- Publish linked open data compliant with CIDOC-CRM and other ontologies
- Manage complex relationships between entities, concepts, and resources

This Docker stack provides a fully integrated environment with all necessary services preconfigured and ready to use, including the semantic infrastructure components required for WissKI's operation.

## Repository Contents

```
dockerWissKI/
├── docker-compose.yml          # Main orchestration file (7 services)
├── varnish/
│   └── default.vcl            # Varnish HTTP cache configuration
├── rdf4j/
│   ├── Dockerfile             # Custom RDF4J triplestore image
│   ├── entrypoint.sh          # RDF4J initialization script
│   └── default_repository.ttl # Default repository configuration
├── test-performance.sh         # Performance benchmarking script
├── example-env                 # Environment variables template
├── CHANGELOG.md                # Changelog documenting changes
└── LICENSE
```

## Infrastructure Stack

This environment orchestrates **7 Docker containers** that work together to provide a complete WissKI installation:

### Core Services

| Service | Version | Purpose | Integration |
|---------|---------|---------|-------------|
| **Drupal + WissKI** | 11.2.4 | Main application server with semantic web capabilities | Connects to MariaDB, Redis, RDF4J, and Solr |
| **MariaDB** | 11.5 | Relational database for Drupal content and configuration | Primary data store for Drupal entities, users, and configuration |
| **RDF4J** | Latest | Triplestore for RDF/semantic data storage | Stores semantic data, handles SPARQL queries, provides reasoning capabilities |
| **Solr** | 9.7 | Full-text search engine | Indexes and searches WissKI entities and content |
| **Redis** | 7.4 | Object cache and session storage | Caches Drupal data, stores user sessions |
| **Varnish** | 7.6 | HTTP reverse proxy and page cache | Sits in front of Drupal, caches anonymous page requests |
| **Adminer** | Latest | Web-based database management tool | Provides web UI for MariaDB administration |

### Service Integration

The services are integrated as follows:

1. **Varnish → Drupal**: Varnish acts as the entry point, caching and serving requests. It forwards uncached requests to Drupal.
2. **Drupal → MariaDB**: Drupal stores all content, configuration, users, and system data in MariaDB.
3. **Drupal → RDF4J**: WissKI stores semantic data (RDF triples) in RDF4J via SPARQL endpoints. The triplestore handles ontology reasoning and semantic queries.
4. **Drupal → Solr**: Drupal indexes content in Solr for full-text search capabilities.
5. **Drupal → Redis**: Drupal uses Redis for caching rendered content, database queries, and storing user sessions.

All services communicate over Docker's internal network, with health checks ensuring proper startup order and service availability.

## Preconfiguration

This stack comes with extensive preconfiguration to minimize setup time and provide a production-ready environment:

### WissKI Default Data Model

The stack automatically installs and applies the **[WissKI Default Data Model](https://drupal.org/project/wisski_default_data_model)** recipe during first startup. This provides:

- **Pre-configured content types** tailored for research data and cultural heritage
- **Semantic field structures** following best practices
- **Default ontologies** including CIDOC-CRM support
- **Menu structures** and navigation optimized for WissKI workflows
- **Entity relationships** and field configurations

**Configuration**: The version can be controlled via `WISSKI_DEFAULT_DATA_MODEL_VERSION` environment variable (default: `^1.3`).

### WissKI Starter Recipe

The **[WissKI Starter](https://drupal.org/project/wisski_starter)** recipe is automatically applied, providing:

- Base WissKI installation with essential modules
- Default adapter configuration for the triplestore
- Core WissKI functionality and workflows

**Configuration**: Version controlled via `WISSKI_STARTER_VERSION` environment variable (default: `^1.1`).

### Redis Integration

Redis is **automatically configured** during container startup:

- Drupal Redis module is installed and enabled
- Redis connection settings are automatically added to `settings.php`
- Cache backend is configured for optimal performance
- Session storage is configured to use Redis

No manual configuration required—the entrypoint script handles everything.

### RDF4J Triplestore

The RDF4J triplestore is preconfigured with:

- Default repository created automatically
- SPARQL endpoints configured for read and write operations
- Connection settings integrated with WissKI
- Default graph URI configured via `DEFAULT_GRAPH` environment variable

### Database Configuration

MariaDB is preconfigured with:

- Optimized settings for Drupal workloads
- UTF8MB4 character set for full Unicode support
- Transaction isolation set to READ-COMMITTED
- Connection pooling and query optimization

### Varnish Cache

Varnish is preconfigured with:

- Drupal-specific caching rules in `default.vcl`
- Smart bypass rules for admin, user, and AJAX paths
- Cookie handling for anonymous vs authenticated users
- Grace period configuration for high availability

### Development Modules

The following development and utility modules are automatically installed:

- **Devel**: Development tools and debugging
- **Health Check**: System health monitoring
- **Project Browser**: Module discovery and installation UI
- **Automatic Updates**: Security update management
- **OpenID Connect**: SSO integration (if configured)
- **SSO Bouncer**: Single sign-on enforcement

## Quick Start

```bash
# 1. Copy and configure environment variables
cp example-env .env
nano .env  # Edit your settings (at minimum: passwords and domain)

# 2. Start all services
docker compose up -d

# 3. Check service status
docker compose ps

# 4. View Drupal installation logs
docker compose logs -f drupal

# 5. Access your site
# Main site (via Varnish): http://localhost:8000
# Direct Drupal access: http://localhost:80
# Adminer (database): http://localhost:8081
# RDF4J workbench: http://localhost:8080
# Solr admin: http://localhost:8983
```

The first startup will take several minutes as Drupal is installed, modules are downloaded, and recipes are applied. Monitor the logs to track progress.

## Access Points

| Service | URL | Purpose | Credentials |
|---------|-----|---------|-------------|
| **Drupal (via Varnish)** | http://localhost:${VARNISH_PORT:-8000} | **Main site - use this for best performance** | Set in `.env` |
| Drupal (direct) | http://localhost:${DRUPAL_PORT:-80} | Direct Apache access (bypasses cache) | Set in `.env` |
| Adminer | http://localhost:${ADMINER_PORT:-8081} | Database administration UI | MariaDB credentials from `.env` |
| RDF4J Workbench | http://localhost:${RDF4J_PORT:-8080} | Triplestore management and SPARQL queries | Optional auth in `.env` |
| Solr Admin | http://localhost:${SOLR_PORT:-8983} | Search index administration | None by default |

> **Note:** Always access Drupal through Varnish (port 8000 by default) in production for optimal performance and caching.

## Configuration

### Environment Variables

The `example-env` file contains all configurable environment variables. Copy it to `.env` and customize for your needs:

#### WissKI/Drupal Settings

- `DRUPAL_DOMAIN` - Main domain name for your site (default: `localhost`)
- `DRUPAL_USER` / `DRUPAL_PASSWORD` - Administrator account credentials (default: `admin` / `admin`)
- `SITE_NAME` - Site name displayed in headers (default: `My WissKI`)
- `DRUPAL_TRUSTED_HOST` - Allowed HTTP Host headers (default: `'^localhost$','^127\.0\.0\.1$'`)
- `DRUPAL_LOCALE` - Site language/locale
- `WISSKI_DEFAULT_DATA_MODEL_VERSION` - Version of default data model recipe (default: `1.3.0`)
- `WISSKI_STARTER_VERSION` - Version of WissKI starter recipe (default: `1.1.0`)

#### Triplestore & RDF Settings

- `TS_REPOSITORY` - RDF4J repository name (default: `default`)
- `DEFAULT_GRAPH` - Default named graph URI for triples (default: `https://my.wiss-ki.eu/`)
- `TS_USERNAME` / `TS_PASSWORD` - Optional RDF4J authentication
- `TS_READ_URL` - SPARQL read endpoint (auto-configured)
- `TS_WRITE_URL` - SPARQL write endpoint (auto-configured)

#### Database Settings

- `DB_NAME` - MariaDB database name (default: `DATABASE`)
- `DB_USER` / `DB_PASSWORD` - MariaDB user credentials (default: `DBUSER` / `USERPW`)
- `DB_ROOT_PASSWORD` - MariaDB root password (default: `ROOTPW`)

#### Service Ports

- `DRUPAL_PORT` - Drupal HTTP port (default: `80`)
- `VARNISH_PORT` - Varnish HTTP port (default: `8000`)
- `ADMINER_PORT` - Adminer port (default: `8081`)
- `RDF4J_PORT` - RDF4J port (default: `8080`)
- `SOLR_PORT` - Solr port (default: `8983`)
- `REDIS_PORT` - Redis port (default: `6379`)

See `example-env` for the complete list with detailed documentation.

## Performance Optimizations

This stack includes performance optimizations for production use:

### Caching Layers

1. **Varnish HTTP Cache**: Full-page caching for anonymous users, serving pages in 20-50ms
2. **Redis Object Cache**: Caches rendered blocks, database queries, and user sessions
3. **PHP OPcache**: Bytecode caching with JIT compilation for 40-60% performance improvement
4. **MariaDB Query Cache**: Reduces database load for repeated queries

### Database Optimizations

- **InnoDB Buffer Pool**: 1GB (vs 128MB default) for better memory utilization
- **Connection Pooling**: Optimized connection limits and timeouts
- **Query Optimization**: Indexes and query cache configured for Drupal workloads

### Resource Management

All services have defined resource limits to prevent resource contention:

- **Drupal**: 2 CPU, 2GB RAM
- **MariaDB**: 2 CPU, 2GB RAM
- **RDF4J**: 2 CPU, 5GB RAM
- **Solr**: 1 CPU, 1.5GB RAM
- **Redis**: 1 CPU, 768MB RAM
- **Varnish**: 1 CPU, 512MB RAM

**Total recommended**: 8GB+ RAM, 4+ CPU cores

## Verification

Verify that all services are working correctly:

```bash
# Check Varnish cache
curl -I http://localhost:8000
# Look for: X-Varnish-Cache: HIT or MISS

# Check Redis connection
docker exec wisski--redis redis-cli ping
# Should return: PONG

# Check Redis module in Drupal
docker exec wisski--drupal drush pm:list --status=enabled | grep redis
# Should show: redis (Enabled)

# Check RDF4J connectivity
curl http://localhost:8080/rdf4j-server/repositories/default
# Should return repository information

# Check Solr
curl http://localhost:8983/solr/admin/info/system
# Should return system information
```

## Maintenance

### Common Tasks

```bash
# Rebuild containers after configuration changes
docker compose up -d --build

# Clear Drupal cache
docker exec wisski--drupal drush cr

# Clear Redis cache
docker exec wisski--redis redis-cli FLUSHALL

# View service logs
docker compose logs -f [service-name]

# View resource usage
docker stats

# Backup volumes
docker compose down
tar -czf backup.tar.gz \
  -C /var/lib/docker/volumes \
  drupal-data \
  mariadb-data \
  private-files \
  rdf4j-data \
  solr-data \
  redis-data
```

## Troubleshooting

### Redis Not Working

```bash
# Check if Redis module is enabled
docker exec wisski--drupal drush pm:enable redis -y
docker exec wisski--drupal drush cr

# Verify Redis connection in settings.php
docker exec wisski--drupal cat /opt/drupal/web/sites/default/settings.php | grep redis
```

### Varnish Not Caching

- Ensure you're accessing via Varnish port (8000 by default), not direct Drupal port
- Verify you're not logged in (Varnish only caches anonymous users)
- Check Varnish logs: `docker compose logs varnish`

### Services Not Starting

- Check health status: `docker compose ps`
- View service logs: `docker compose logs [service-name]`
- Verify environment variables are set correctly in `.env`
- Ensure sufficient system resources (RAM, CPU)

### High Memory Usage

This is expected for a production-tuned environment:
- **Minimal setup**: ~4GB total
- **Tuned setup**: ~8-10GB total

To reduce memory usage, adjust resource limits in `docker-compose.yml` or reduce buffer pool sizes.

## Documentation

- **[CHANGELOG.md](CHANGELOG.md)** - Detailed changelog of changes and improvements
- **[varnish/default.vcl](varnish/default.vcl)** - Varnish configuration with Drupal-specific rules
- **[test-performance.sh](test-performance.sh)** - Automated performance testing script

## License

See [LICENSE](LICENSE) file.

## Credits

This stack integrates:
- [Drupal](https://www.drupal.org/) - Content management framework
- [WissKI](https://wiss-ki.eu/) - Semantic web extension for Drupal
- [RDF4J](https://rdf4j.org/) - Java framework for working with RDF data
- [Solr](https://solr.apache.org/) - Enterprise search platform
- [Varnish](https://varnish-cache.org/) - HTTP accelerator
- [Redis](https://redis.io/) - In-memory data store
- [MariaDB](https://mariadb.org/) - Database server

---

**Last Updated:** December 8, 2025
