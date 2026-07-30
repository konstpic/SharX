# SharX

[English](README_EN.md) | [Русский](README_RU.md) | [فارسی](README_FA.md)

## Welcome to SharX

**SharX** is a modern multi-node Xray management platform with Docker-first deployment, observability hooks, and a visual subscription page builder.

This version brings a modern, Docker-first architecture, **multi-node** workers, a **visual subscription page builder**, **encrypted cookie web sessions** (`web/web.go`), and **optional observability**: Prometheus text metrics at `{basePath}panel/metrics`, optional Loki / VictoriaMetrics endpoints in panel settings, and a downloadable Grafana dashboard JSON for your own stack.

## What's New

### Node Mode (1 panel – multiple nodes)
- **Centralized management**: one panel manages several worker nodes
- **Enable multi-node** in the panel settings first
- **Add node from the UI**: under **Nodes**, the modal gives a ready **`docker-compose.yml`** with **`PANEL_URL`** and **`SECRET_KEY`** (base64 **pairing** bundle for TLS, mTLS, and JWT when the panel talks to the node). You do **not** paste a legacy **`NODE_API_KEY`**
- **On the worker host**: save the file (e.g. `docker-compose.yml`) and run **`docker compose up -d --build`**
- **Scalable architecture**: add or remove nodes as you grow

### Client and Inbound Entities Separation
- **Flexible Client Assignment**: A client can now be assigned to multiple inbounds
- **Multi-Inbound Subscriptions**: All assigned inbounds are displayed in the subscription
- **Node Flexibility**: Multiple nodes can be assigned to the same inbound
- **Better Resource Management**: More efficient use of server resources

### Hosts Tab
- **Address Override**: Override node addresses in subscriptions
- **Proxy Support**: Perfect for nodes hidden behind a proxy or load balancer
- **Flexible Routing**: Configure different host addresses for different use cases

### Web sessions
- **Cookie-based sessions**: Admin login sessions use Gin's encrypted cookie store (`web/web.go`).
- **Live data paths**: Client lists, traffic, and online state are served from PostgreSQL and backend services (see e.g. client service notes on real-time data).

### PostgreSQL database
- **Production datastore**: The panel runtime uses **PostgreSQL** (GORM + SQL migrations in `database/`).
- **Legacy import**: A built-in **SQLite → PostgreSQL** migration tool is available for importing legacy panel SQLite dumps (`web/service/migration.go`).

### Observability (optional; not a bundled Grafana stack)
- **Prometheus scrape**: Metrics are exposed in Prometheus text format at `{basePath}panel/metrics` (`web/web.go`, `web/service/metrics.go`).
- **Loki logging**: Optional push logging when *Grafana integration* is enabled in settings (`logger/loki.go`, `web/entity/entity.go`).
- **VictoriaMetrics**: Optional remote ingest URL in settings for metric forwarding.
- **Grafana dashboard JSON**: Export from the panel (settings API) to import into **your** Grafana; the default `docker-compose` does **not** ship Grafana/Prometheus/Loki containers.

### New Distribution Model
- **Docker-Based**: Pre-built Docker images for easy deployment
- **Cross-Platform**: Works on any OS and CPU architecture
- **Fast Installation**: Download ready images in 5–10 seconds
- **No Compilation**: No need to compile code on weak servers
- **Easy Migration**: Simple container-based migration and scaling

### Device HWID (Beta)
- **Hardware Identification**: Device identification by unique hardware ID for enhanced security
- **Client Protection**: Protect against unauthorized access and subscription leaks
- **Device Control**: Limit and monitor which devices can use a client's subscription
- **Individual Configuration**: Disabled by default, can be enabled individually per client
- **Client Support**: Currently supported in Happ and V2RayTun clients
- **Leak Prevention**: If a subscription is leaked, only registered devices can access it
- **Usage Monitoring**: Track which devices are using each account
- **Flexible Security**: Enable HWID protection only for clients that need it

## Installation

### Prerequisites
- Linux server (Ubuntu, Debian, CentOS, Fedora, Arch, Alpine, openSUSE)
- Root access
- Ports available: 2053 (Web UI), 2096 (Subscriptions), 80 (for SSL certificate)

---

## Option 1: Automatic Installation (Recommended)

### One-Line Install

```bash
bash <(curl -Ls https://raw.githubusercontent.com/konstpic/SharX/main/install.sh)
```

Or clone and run:

```bash
git clone https://github.com/konstpic/SharX.git
cd SharX
sudo bash install.sh
```

### What the Script Does

The install script automatically:
- Detects your Linux distribution
- Installs Docker and Docker Compose
- Configures network mode (host or bridge with port mapping)
- Sets up SSL certificates via Let's Encrypt (acme.sh)
  - For domains: 90-day certificates with auto-renewal
  - For IP addresses: 6-day certificates with auto-renewal
- Generates secure database password
- Creates and starts all services

### Supported Systems

| Distribution | Package Manager |
|--------------|-----------------|
| Ubuntu/Debian | apt |
| Fedora | dnf |
| Arch Linux | pacman |
| Alpine | apk |
| openSUSE | zypper |

### Panel Installation via Script

```bash
sudo bash install.sh
```

Select **1) Install Panel** and follow the prompts:
1. Choose network mode (host/bridge)
2. Set ports for panel and subscriptions
3. Generate or enter database password
4. Choose SSL certificate type (domain/IP/skip)

### Management Menu

After installation, run the script again to access the management menu:

```bash
sudo bash install.sh
```

**Available options:**
- **Panel**: Install, Update, Start, Stop, Restart, Status, Logs
- **Panel Settings**: Change ports, Change DB password, Renew/Setup certificates
- **Uninstall**

### Update Panel

**Watchtower** (`sharx_watchtower`) runs in the same `docker compose` stack. The panel uses `XUI_DOCKER_UPDATER_URL` and `XUI_DOCKER_UPDATER_TOKEN` to call its HTTP API (no public port) and pull a new `sharx` image with `com.centurylinklabs.watchtower.enable: "true"`. The **in-panel update button** usually goes through this path. For production, set `WATCHTOWER_HTTP_API_TOKEN` in `.env` (e.g. `openssl rand -hex 24`).

**Note:** if the panel image was built with `build:` in compose, the image name looks like `sharx-code-sharx` — that is **not** a registry path. Watchtower will `docker pull` that name, Docker Hub will be queried (`library/...`) and the pull fails with 401 or “does not exist”. For production, set a **published image** in `docker-compose.yml`, e.g. `image: harbor.sharxconnect.app/sharx/sharx:1.1.2` (and remove/comment the `build` for the panel), run `docker login harbor.sharxconnect.app`, and recreate the container. Then the UI update path and Watchtower can pull new builds.

You can also:

- **With Docker Compose**:
  ```bash
  docker compose pull
  docker compose up -d
  ```
- **Via the SharX install script** (if you use that distribution):
  ```bash
  sudo bash install.sh
  # 2) Update Panel
  ```

The panel container is recreated with a new image; your **PostgreSQL** data on the volume is usually **preserved**.

---

## Option 2: Manual Installation

### Panel Installation

1. **Clone or download this repository**
   ```bash
   git clone https://github.com/konstpic/SharX.git
   cd SharX
   ```

2. **Configure Docker Compose**
   
   Edit `docker-compose.yml` and update the following settings:
   
   **Database Configuration:**
   - Change `change_this_password` to a secure password in both `XUI_DB_PASSWORD` and `POSTGRES_PASSWORD`
   - These passwords must match for the panel to connect to PostgreSQL
   - Example:
     ```yaml
     XUI_DB_PASSWORD: your_secure_password_here
     POSTGRES_PASSWORD: your_secure_password_here
     ```
   
   **Port Configuration:**
   - Default ports: 2053 (Web UI), 2096 (Subscriptions), 5432 (PostgreSQL)
   - Adjust port mappings if needed:
     ```yaml
     ports:
       - "2053:2053"   # Web UI
       - "2096:2096"   # Subscriptions
       - "5432:5432"   # PostgreSQL (optional, for external access)
     ```
   
   **Hostname (Optional):**
   - Uncomment and set `hostname` if you want to specify a hostname for the container:
     ```yaml
     hostname: yourhostname
     ```
   
   **Network Mode (Optional):**
   - For better performance, you can use host networking mode
   - Uncomment `network_mode: host`:
     ```yaml
     network_mode: host
     ```
   - When using host mode, remove the `ports` section as ports will be directly exposed on the host

3. **Prepare SSL Certificates for TLS**
   
   **Important**: For TLS/HTTPS connection, you need:
   - A domain name pointing to your server
   - SSL certificates (certificate file and private key)
   
   **Step 1: Create certificates directory**
   ```bash
   mkdir -p cert
   ```
   
   **Step 2: Copy your SSL certificates**
   
   Copy your SSL certificate files to the `cert` directory. You need:
   - Certificate file (usually `cert.pem` or `fullchain.pem`)
   - Private key file (usually `privkey.pem` or `key.pem`)
   
   Example:
   ```bash
   # Copy certificate file
   cp /path/to/your/certificate.pem cert/cert.pem
   
   # Copy private key file
   cp /path/to/your/private.key cert/privkey.pem
   ```
   
   **Note**: The certificates will be mounted to `/root/cert/` inside the container, but in the panel settings you should use `/app/cert/` paths.
   
   **Certificate Requirements:**
   - Certificate file must be named `cert.pem`
   - Private key file must be named `privkey.pem`
   - Both files must be in the `cert/` directory
   - Ensure proper file permissions (readable by the container)

4. **Start the services**
   ```bash
   docker-compose up -d
   ```

5. **Access the Web UI**
   
   Open your browser and navigate to:
   ```
   http://your-server-ip:2053
   ```
   
   Or if using HTTPS:
   ```
   https://your-server-ip:2053
   ```

6. **Initial Setup**
   - Complete the initial setup wizard
   - Set up your admin account
   - Optionally add and manage remote nodes in the web UI (**Nodes** / **Geography**)

7. **Configure TLS in Panel Settings**
   
   After accessing the panel, configure TLS for secure connections:
   
   **In the Panel Settings:**
   - Navigate to Settings/Configuration
   - **Domain Name**: Enter your domain name (e.g., `panel.example.com`)
     - This must be the domain name that points to your server
     - The domain must have valid DNS records pointing to your server's IP
   
   **Certificate Paths:**
   - **Certificate Path**: `/app/cert/cert.pem`
     - This is the path inside the container where your certificate file is located
     - The file `cert.pem` should be in the `cert/` directory on your host
   
   - **Private Key Path**: `/app/cert/privkey.pem`
     - This is the path inside the container where your private key file is located
     - The file `privkey.pem` should be in the `cert/` directory on your host
   
   **Important Notes:**
   - The paths `/app/cert/` are internal container paths
   - Your actual files are in the `cert/` directory on the host
   - Docker Compose mounts `$PWD/cert/` to `/root/cert/` in the container
   - The panel uses `/app/cert/` paths, which should map to your mounted certificates
   - Ensure both `cert.pem` and `privkey.pem` exist in your `cert/` directory
   
   **Verify TLS Configuration:**
   - After saving settings, restart the container:
     ```bash
     docker-compose restart sharx
     ```
   - Access the panel via HTTPS: `https://your-domain.com:2053`
   - Check that the browser shows a valid SSL certificate

### Remote nodes (multi-node)

1. Install the **panel**, then enable **multi-node** mode in settings.
2. In **Nodes**, use **add node** — copy the **`docker-compose.yml`** snippet from the modal (already filled with **`PANEL_URL`** and **`SECRET_KEY`** from pairing).
3. On the **worker server**, save it (e.g. `docker-compose.yml`) and run **`docker compose up -d --build`**.
4. Bind nodes to inbounds, geography, and operations remain **in the web UI** (**Nodes**, **Geography**). The SharX install script only deploys the panel and database, not workers.

Details: [node/README.md](node/README.md).

### Advanced Configuration

#### Using Host Network Mode

If you want to use host networking (recommended for better performance), uncomment the `network_mode: host` line in `docker-compose.yml`:

```yaml
network_mode: host
```

When using host mode, remove the `ports` section as ports will be directly exposed on the host.

#### PostgreSQL Configuration

The default PostgreSQL configuration uses:
- **User**: `xui_user`
- **Database**: `xui_db`
- **Port**: `5432` (exposed for external access if needed)

To change these settings, update the environment variables in `docker-compose.yml`.

#### Sessions & observability

- **Sessions**: Encrypted cookie store only; protect browser/session cookies like any admin app.
- **Metrics / logs**: Configure optional Loki and VictoriaMetrics URLs in the panel **Settings** UI if you run those services yourself. Protect `/panel/metrics` at the network or reverse-proxy layer if you scrape it.

#### Environment Variables Configuration

SharX supports comprehensive configuration through environment variables. These settings are **only available via environment variables** and cannot be changed through the web UI.

**Web Panel Settings:**

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `XUI_WEB_PORT` | Web panel port | `2053` | `2053` |
| `XUI_WEB_LISTEN` | IP address to listen on | - | `0.0.0.0` |
| `XUI_WEB_DOMAIN` | Web panel domain | - | `panel.example.com` |
| `XUI_WEB_BASE_PATH` | Base URL path | `/` | `/` |
| `XUI_WEB_CERT_FILE` | SSL certificate path | - | `/app/cert/fullchain.pem` |
| `XUI_WEB_KEY_FILE` | SSL private key path | - | `/app/cert/privkey.pem` |

**Subscription Service Settings:**

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `XUI_SUB_PORT` | Subscription service port | `2096` | `2096` |
| `XUI_SUB_PATH` | Subscription URI path | `/sub/` | `/sub/` |
| `XUI_SUB_DOMAIN` | Subscription domain | - | `sub.example.com` |
| `XUI_SUB_CERT_FILE` | SSL certificate path for subscription | - | `/app/cert/sub-fullchain.pem` |
| `XUI_SUB_KEY_FILE` | SSL private key path for subscription | - | `/app/cert/sub-privkey.pem` |

**PostgreSQL Database Settings:**

| Variable | Description | Default | Required | Example |
|----------|-------------|---------|----------|---------|
| `XUI_DB_HOST` | PostgreSQL host | `localhost` | No | `postgres` |
| `XUI_DB_PORT` | PostgreSQL port | `5432` | No | `5432` |
| `XUI_DB_USER` | PostgreSQL user | - | **Yes** | `xui_user` |
| `XUI_DB_PASSWORD` | PostgreSQL password | - | **Yes** | `change_this_password` |
| `XUI_DB_NAME` | Database name | App name | No | `xui_db` |
| `XUI_DB_SSLMODE` | SSL mode | `disable` | No | `disable`, `require`, `verify-ca`, `verify-full` |

**Logging and Debugging:**

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `XUI_LOG_LEVEL` | Logging level | `info` | `debug`, `info`, `notice`, `warning`, `error` |
| `XUI_DEBUG` | Debug mode | `false` | `true`, `false` |
| `XUI_LOG_FOLDER` | Log folder | Platform dependent | `/var/log/xui` |

**Xray Settings:**

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `XRAY_VMESS_AEAD_FORCED` | Force VMESS AEAD | `false` | `true`, `false` |

**Security:**

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `XUI_ENABLE_FAIL2BAN` | Enable fail2ban | `true` | `true`, `false` |

**Worker node (not the panel):** the default path is **pairing** via **`SECRET_KEY`** + **`PANEL_URL`** from the panel modal; see [node/README.md](node/README.md).

**Example docker-compose.yml configuration:**

```yaml
services:
  sharx:
    environment:
      # Xray settings
      XRAY_VMESS_AEAD_FORCED: "false"
      XUI_ENABLE_FAIL2BAN: "true"
      
      # Web Panel settings (only via env, not available in UI)
      XUI_WEB_PORT: 2053
      XUI_WEB_LISTEN: 0.0.0.0
      XUI_WEB_DOMAIN: panel.example.com
      XUI_WEB_BASE_PATH: /
      XUI_WEB_CERT_FILE: /app/cert/fullchain.pem
      XUI_WEB_KEY_FILE: /app/cert/privkey.pem
      
      # Subscription settings (only via env, not available in UI)
      XUI_SUB_PORT: 2096
      XUI_SUB_PATH: /sub/
      XUI_SUB_DOMAIN: sub.example.com
      XUI_SUB_CERT_FILE: /app/cert/sub-fullchain.pem
      XUI_SUB_KEY_FILE: /app/cert/sub-privkey.pem
      
      # PostgreSQL settings
      XUI_DB_HOST: postgres
      XUI_DB_PORT: 5432
      XUI_DB_USER: xui_user
      XUI_DB_PASSWORD: change_this_password
      XUI_DB_NAME: xui_db
      XUI_DB_SSLMODE: disable
```

**Important Notes:**
- Web Panel and Subscription settings (`XUI_WEB_*` and `XUI_SUB_*`) are **only available through environment variables** and cannot be changed via the web interface
- Database credentials (`XUI_DB_USER`, `XUI_DB_PASSWORD`) are **required** for the application to work
- All certificate paths must be absolute paths inside the container (usually `/app/cert/*.pem`)
- Database is stored on the host via bind mount: `$PWD/postgres_data:/var/lib/postgresql/data`

#### SSL Certificates and TLS Configuration

**Certificate Setup:**

1. **Obtain SSL Certificates**
   - You need a domain name pointing to your server
   - Obtain SSL certificates (e.g., from Let's Encrypt, or use your own CA)
   - You need two files:
     - **For Panel**: Certificate file: `cert.pem` (or `fullchain.pem`)
     - Private key file: `privkey.pem`

2. **Place Certificates in cert/ Directory**
   ```bash
   # Ensure cert directory exists
   mkdir -p cert
   
   # Copy your certificate files
   cp /path/to/certificate.pem cert/cert.pem
   cp /path/to/private.key cert/privkey.pem
   
   # Set proper permissions
   chmod 644 cert/cert.pem
   chmod 600 cert/privkey.pem
   ```

3. **Configure in Panel**
   - Domain Name: Your domain (e.g., `panel.example.com`)
   - Certificate Path: `/app/cert/cert.pem`
   - Private Key Path: `/app/cert/privkey.pem`

**Certificate Path Mapping:**
- Host path: `./cert/` (relative to docker-compose.yml)
- Container mount: `/root/cert/` (as defined in volumes)
- Panel paths: `/app/cert/` (used in panel settings)

**TLS Verification:**
- After configuration, access via `https://your-domain.com:2053`
- Browser should show valid SSL certificate
- Check certificate expiration and renew as needed

### Migration from SQLite

If you're migrating from an older version using SQLite (version 2.8.5 and above):

1. **Export data from old panel**
   - Export your configuration from the old panel (version 2.8.5 or higher)
   - Save the backup file securely
   - This backup file will be used for migration

2. **Start the new panel**
   - Follow the installation steps above to set up the new panel
   - Access the new panel web interface
   - Complete the initial setup if required

3. **Important: Domain Configuration Warning**
   
   **⚠️ Critical**: If your old panel had a different domain name configured, it will overwrite the domain settings in the new panel during migration.
   
   **Before importing**, if you need to preserve the new panel's domain settings:
   - Connect to the PostgreSQL database
   - Clear the domain settings from the old panel's data in the database
   - This prevents the old domain from overwriting your new panel's domain configuration
   
   **Note**: Your login credentials (username and password) will remain unchanged after migration.

4. **Import your data**
   - Navigate to **Settings** menu in the new panel
   - Find the migration/import option
   - Upload the backup file from your old panel (version 2.8.5+)
   - The migration will process automatically
   - Verify all data has been migrated correctly
   - Check that your domain settings are correct (if you didn't clear them from the old data)

### Troubleshooting

#### Check container status
```bash
docker-compose ps
```

#### View logs
```bash
docker-compose logs -f
```

#### Restart services
```bash
docker-compose restart
```

#### Stop services
```bash
docker-compose down
```

#### Remove all data (⚠️ Warning: This will delete all data)
```bash
docker-compose down -v
```

### API Documentation

For integrating with SharX panel programmatically, see the complete API reference:

- **[API Documentation](docs/API.md)** - REST API endpoints, authentication, examples

### Support

For issues, questions, or contributions, please refer to the project repository.

### Donate

Support SharX development: **[donate.konstpic.ru](https://donate.konstpic.ru/)**

---

**Note**: This version uses Docker containers for easy deployment and management. All images are pre-built and ready to use, eliminating the need for compilation or complex setup procedures.
