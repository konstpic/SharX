# 3x-ui New

[English](README_EN.md) | [Русский](README_RU.md)

## Welcome to the New 3x-ui

Welcome to the next generation of 3x-ui! This version brings significant improvements, a modern architecture, and a streamlined installation process using Docker containers.

## What's New

### Node Mode (1 Panel – Multiple Nodes)
- **Centralized Management**: One panel can now manage multiple nodes
- **Registration Mode**: On first start, nodes run in registration mode and wait for connection from the panel
- **Secure Authentication**: The panel issues an API token, signs the node, and stores it for future use
- **Scalable Architecture**: Easily add or remove nodes as your infrastructure grows

### Client and Inbound Entities Separation
- **Flexible Client Assignment**: A client can now be assigned to multiple inbounds
- **Multi-Inbound Subscriptions**: All assigned inbounds are displayed in the subscription
- **Node Flexibility**: Multiple nodes can be assigned to the same inbound
- **Better Resource Management**: More efficient use of server resources

### Hosts Tab
- **Address Override**: Override node addresses in subscriptions
- **Proxy Support**: Perfect for nodes hidden behind a proxy or load balancer
- **Flexible Routing**: Configure different host addresses for different use cases

### Redis Integration
- **Performance Boost**: Significantly faster UI response times
- **Smart Caching**: Caches frequent database queries
- **Efficient Data Serving**: If request parameters haven't changed and cache is valid, data is served directly from Redis
- **Reduced Database Load**: Less stress on PostgreSQL database

### Full Migration to PostgreSQL
- **Reliable Database**: Complete migration from SQLite to PostgreSQL
- **Updated Import/Export**: Backup section has been updated for PostgreSQL
- **Migration Tool**: Built-in migration tool from SQLite to PostgreSQL supports existing users
- **Data Integrity**: Full and reliable data transfer during migration process

### New Modern UI Theme
- **Glass Morphism Design**: Beautiful, modern glass morphism-style interface
- **Improved User Experience**: Intuitive and responsive design
- **Better Visual Hierarchy**: Clear and organized interface elements

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
bash <(curl -Ls https://raw.githubusercontent.com/konstpic/3x-ui-new/main/install.sh)
```

Or clone and run:

```bash
git clone https://github.com/konstpic/3x-ui-new.git
cd 3x-ui-new
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
| CentOS/RHEL | yum |
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

### Node Installation via Script

```bash
sudo bash install.sh
```

Select **2) Install Node** and follow the prompts:
1. Choose network mode (host/bridge)
2. Set API port
3. Choose SSL certificate type

### Management Menu

After installation, run the script again to access the management menu:

```bash
sudo bash install.sh
```

**Available options:**
- **Panel**: Install, Update, Start, Stop, Restart, Status, Logs
- **Panel Settings**: Change ports, Change DB password, Renew/Setup certificates
- **Node**: Install, Update, Start, Stop, Restart, Status, Logs, Renew certificates
- **Uninstall**

### Update Panel/Node

```bash
sudo bash install.sh
# Select: 2) Update Panel or 21) Update Node
```

The update process:
1. Pulls new Docker image (while service is running)
2. Stops and removes old container
3. Starts new container with updated image
4. Database is NOT restarted (no data loss)

---

## Option 2: Manual Installation

### Panel Installation

1. **Clone or download this repository**
   ```bash
   git clone https://github.com/konstpic/3x-ui-new.git
   cd 3x-ui-new
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
   - Configure your first node connection

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
     docker-compose restart 3xui
     ```
   - Access the panel via HTTPS: `https://your-domain.com:2053`
   - Check that the browser shows a valid SSL certificate

### Node Installation

1. **Navigate to the node directory**
   ```bash
   cd node
   ```

2. **Configure the node**
   
   Edit `docker-compose.yml` and configure:
   - **Ports**: Set appropriate ports for your node
   - **Network Mode**: Choose between bridge or host networking
   - **Configuration**: Adjust `bin/config.json` if needed
   
   **SSL Certificates for Node (Recommended):**
   - Create `cert` directory in the node folder:
     ```bash
     mkdir -p cert
     ```
   - Copy your SSL certificates:
     - **Certificate file**: `fullchain.pem` (recommended for nodes)
     - **Private key file**: `privkey.pem`
     ```bash
     cp /path/to/fullchain.pem cert/fullchain.pem
     cp /path/to/privkey.pem cert/privkey.pem
     ```
   - The certificates will be mounted to `/app/cert/` inside the container
   - Environment variables in `docker-compose.yml` should point to:
     - `NODE_TLS_CERT_FILE=/app/cert/fullchain.pem`
     - `NODE_TLS_KEY_FILE=/app/cert/privkey.pem`

3. **Start the node**
   ```bash
   docker-compose up -d
   ```

4. **Connect to Panel**
   - The node will start in registration mode
   - In the panel, add a new node
   - The panel will issue an API token and connect to the node
   - The node will be signed and stored for future use

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

#### Redis Configuration

Redis is automatically configured and integrated. No additional setup is required.

#### SSL Certificates and TLS Configuration

**Certificate Setup:**

1. **Obtain SSL Certificates**
   - You need a domain name pointing to your server
   - Obtain SSL certificates (e.g., from Let's Encrypt, or use your own CA)
   - You need two files:
     - **For Panel**: Certificate file: `cert.pem` (or `fullchain.pem`)
     - **For Nodes** (recommended): Certificate file: `fullchain.pem`
     - Private key file: `privkey.pem` (for both panel and nodes)

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

**For Nodes:**
- **Recommended certificate format**: Use `fullchain.pem` for nodes
- Certificate file: `fullchain.pem`
- Private key file: `privkey.pem`
- These files should be placed in the `node/cert/` directory
- Environment variables in node's `docker-compose.yml`:
  - `NODE_TLS_CERT_FILE=/app/cert/fullchain.pem`
  - `NODE_TLS_KEY_FILE=/app/cert/privkey.pem`

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

### Support

For issues, questions, or contributions, please refer to the project repository.

---

**Note**: This version uses Docker containers for easy deployment and management. All images are pre-built and ready to use, eliminating the need for compilation or complex setup procedures.
