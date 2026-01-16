# 3x-ui Panel API Documentation

Complete API reference for the 3x-ui panel. This documentation covers all endpoints with descriptions, parameters, and example payloads.

---

## Table of Contents

- [Notes](#notes)
- [Base URL Configuration](#base-url-configuration)
- [Authentication](#authentication)
- [Standard Response Format](#standard-response-format)
- [1. Login & Session](#1-login--session)
- [2. Inbounds API](#2-inbounds-api)
- [3. Server API](#3-server-api)
- [4. Settings](#4-settings)
- [5. Migration](#5-migration)
- [6. Xray Settings](#6-xray-settings)
- [7. Nodes (Multi-Node Mode)](#7-nodes-multi-node-mode)
- [8. Clients](#8-clients)
- [9. Client HWID](#9-client-hwid)
- [10. Hosts](#10-hosts)
- [11. Node Push API](#11-node-push-api)
- [12. Subscription Server](#12-subscription-server)
- [13. WebSocket](#13-websocket)

---

## Notes

- Most unsafe operations (POST/PUT/PATCH/DELETE) include mock/example payloads—adjust to your deployment.
- Safe methods (GET/HEAD/OPTIONS) may have saved examples from live responses.
- Replace path variables (e.g., `{id}`, `{email}`, `{clientId}`, `{count}`, `{bucket}`) before sending.
- Some endpoints are hardcoded with localhost in examples; adapt `HOST`/`PORT`/`WEBBASEPATH` for your environment.
- Expected success responses are typically `200 OK` unless otherwise documented.
- All authenticated endpoints require a valid session cookie obtained from `/login`.

---

## Base URL Configuration

```
BASE_URL = http://{HOST}:{PORT}{WEBBASEPATH}
```

Default configuration:
- `HOST`: `localhost` or your server IP
- `PORT`: `2053` (default panel port)
- `WEBBASEPATH`: `/` (can be customized in settings)

Example: `http://192.168.1.100:2053/`

---

## Authentication

The API uses session-based authentication. After successful login, a session cookie is set that must be included in all subsequent requests.

### Session Cookie
- Cookie name: `3x-ui` (or custom based on configuration)
- Obtained via: `POST /login`
- Expires: Based on `sessionMaxAge` setting (default: 60 minutes)

### Unauthenticated Access
- API endpoints return `404 Not Found` for unauthenticated requests (to hide API existence)
- HTML pages redirect to login page

---

## Standard Response Format

All API responses follow this JSON structure:

```json
{
  "success": true,
  "msg": "Operation successful",
  "obj": { /* response data */ }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `success` | boolean | `true` if operation succeeded, `false` otherwise |
| `msg` | string | Human-readable message (may be localized) |
| `obj` | any | Response data (object, array, string, or null) |

### Error Response Example

```json
{
  "success": false,
  "msg": "Something went wrong: invalid parameter",
  "obj": null
}
```

---

## 1. Login & Session

### POST `/login`

Authenticate user and create session.

**Request Body** (form-urlencoded or JSON):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `username` | string | Yes | Username |
| `password` | string | Yes | Password |
| `twoFactorCode` | string | No | 2FA code if enabled |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/login" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin&password=admin" \
  -c cookies.txt
```

**Success Response:**

```json
{
  "success": true,
  "msg": "Login successful"
}
```

**Error Response:**

```json
{
  "success": false,
  "msg": "Wrong username or password"
}
```

---

### GET `/logout`

Logout and clear session.

**Example Request:**

```bash
curl -X GET "http://localhost:2053/logout" \
  -b cookies.txt
```

**Response:** Redirects to login page (302)

---

### POST `/getTwoFactorEnable`

Check if two-factor authentication is enabled.

**Example Request:**

```bash
curl -X POST "http://localhost:2053/getTwoFactorEnable" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": true
}
```

---

## 2. Inbounds API

Base path: `/panel/api/inbounds`

### GET `/panel/api/inbounds/list`

Get all inbounds for the logged-in user.

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/api/inbounds/list" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": [
    {
      "id": 1,
      "up": 1234567890,
      "down": 9876543210,
      "total": 107374182400,
      "remark": "My VLESS Inbound",
      "enable": true,
      "expiryTime": 0,
      "listen": "",
      "port": 443,
      "protocol": "vless",
      "settings": "{\"clients\":[...],\"decryption\":\"none\",\"fallbacks\":[]}",
      "streamSettings": "{\"network\":\"tcp\",\"security\":\"tls\",...}",
      "tag": "inbound-443",
      "sniffing": "{\"enabled\":true,\"destOverride\":[\"http\",\"tls\"]}",
      "clientStats": [
        {
          "id": 1,
          "inboundId": 1,
          "enable": true,
          "email": "user1@example.com",
          "up": 123456,
          "down": 654321,
          "expiryTime": 1735689600000,
          "total": 10737418240
        }
      ]
    }
  ]
}
```

---

### GET `/panel/api/inbounds/get/{id}`

Get a specific inbound by ID.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Inbound ID |

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/api/inbounds/get/1" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": {
    "id": 1,
    "up": 1234567890,
    "down": 9876543210,
    "total": 107374182400,
    "remark": "My VLESS Inbound",
    "enable": true,
    "expiryTime": 0,
    "listen": "",
    "port": 443,
    "protocol": "vless",
    "settings": "...",
    "streamSettings": "...",
    "tag": "inbound-443",
    "sniffing": "...",
    "clientStats": [...]
  }
}
```

---

### GET `/panel/api/inbounds/getClientTraffics/{email}`

Get client traffic statistics by email.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `email` | string | Client email |

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/api/inbounds/getClientTraffics/user1@example.com" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": {
    "id": 1,
    "inboundId": 1,
    "enable": true,
    "email": "user1@example.com",
    "up": 123456789,
    "down": 987654321,
    "expiryTime": 1735689600000,
    "total": 107374182400
  }
}
```

---

### GET `/panel/api/inbounds/getClientTrafficsById/{id}`

Get client traffic statistics by client traffic ID.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | string | Client traffic ID |

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/api/inbounds/getClientTrafficsById/1" \
  -b cookies.txt
```

---

### POST `/panel/api/inbounds/add`

Create a new inbound.

**Request Body** (form-urlencoded or JSON):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `up` | integer | No | Initial upload bytes (default: 0) |
| `down` | integer | No | Initial download bytes (default: 0) |
| `total` | integer | No | Total traffic limit in bytes (0 = unlimited) |
| `remark` | string | No | Human-readable name |
| `enable` | boolean | No | Enable inbound (default: true) |
| `expiryTime` | integer | No | Expiration timestamp in ms (0 = never) |
| `listen` | string | No | Listen IP (empty = all interfaces) |
| `port` | integer | Yes | Port number |
| `protocol` | string | Yes | Protocol: `vmess`, `vless`, `trojan`, `shadowsocks`, `http`, `mixed` |
| `settings` | string | Yes | JSON string with protocol settings |
| `streamSettings` | string | Yes | JSON string with stream settings |
| `sniffing` | string | No | JSON string with sniffing settings |
| `nodeIds` | array | No | Node IDs to assign (multi-node mode) |

**Example Request (VLESS + Reality):**

```bash
curl -X POST "http://localhost:2053/panel/api/inbounds/add" \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{
    "remark": "VLESS-Reality",
    "enable": true,
    "expiryTime": 0,
    "listen": "",
    "port": 443,
    "protocol": "vless",
    "settings": "{\"clients\":[{\"id\":\"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx\",\"flow\":\"xtls-rprx-vision\",\"email\":\"user1\",\"limitIp\":0,\"totalGB\":0,\"expiryTime\":0,\"enable\":true}],\"decryption\":\"none\",\"fallbacks\":[]}",
    "streamSettings": "{\"network\":\"tcp\",\"security\":\"reality\",\"realitySettings\":{\"show\":false,\"dest\":\"www.google.com:443\",\"xver\":0,\"serverNames\":[\"www.google.com\"],\"privateKey\":\"...\",\"shortIds\":[\"...\"]}}",
    "sniffing": "{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\"]}"
  }'
```

**Response:**

```json
{
  "success": true,
  "msg": "Inbound created successfully",
  "obj": {
    "id": 2,
    "remark": "VLESS-Reality",
    "port": 443,
    "protocol": "vless",
    ...
  }
}
```

---

### POST `/panel/api/inbounds/del/{id}`

Delete an inbound.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Inbound ID to delete |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/inbounds/del/2" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "Inbound deleted successfully",
  "obj": 2
}
```

---

### POST `/panel/api/inbounds/update/{id}`

Update an existing inbound.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Inbound ID to update |

**Request Body:** Same as `add` endpoint. Only provided fields will be updated.

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/inbounds/update/1" \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{
    "remark": "Updated Name",
    "enable": false
  }'
```

**Response:**

```json
{
  "success": true,
  "msg": "Inbound updated successfully",
  "obj": { ... }
}
```

---

### POST `/panel/api/inbounds/clientIps/{email}`

Get IP addresses associated with a client.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `email` | string | Client email |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/inbounds/clientIps/user1@example.com" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": "192.168.1.100,10.0.0.50"
}
```

Or if no records:

```json
{
  "success": true,
  "msg": "",
  "obj": "No IP Record"
}
```

---

### POST `/panel/api/inbounds/clearClientIps/{email}`

Clear IP address records for a client.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `email` | string | Client email |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/inbounds/clearClientIps/user1@example.com" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "IP logs cleared successfully"
}
```

---

### POST `/panel/api/inbounds/addClient`

Add a new client to an existing inbound.

**Request Body:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | integer | Yes | Inbound ID |
| `settings` | string | Yes | JSON string with client settings |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/inbounds/addClient" \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{
    "id": 1,
    "settings": "{\"clients\":[{\"id\":\"new-uuid-here\",\"flow\":\"xtls-rprx-vision\",\"email\":\"newuser@example.com\",\"limitIp\":2,\"totalGB\":10737418240,\"expiryTime\":1735689600000,\"enable\":true,\"tgId\":\"\",\"subId\":\"random-sub-id\"}]}"
  }'
```

**Response:**

```json
{
  "success": true,
  "msg": "Client added successfully"
}
```

---

### POST `/panel/api/inbounds/{id}/delClient/{clientId}`

Delete a client from an inbound by client ID (UUID).

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Inbound ID |
| `clientId` | string | Client UUID |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/inbounds/1/delClient/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "Client deleted successfully"
}
```

---

### POST `/panel/api/inbounds/{id}/delClientByEmail/{email}`

Delete a client from an inbound by email.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Inbound ID |
| `email` | string | Client email |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/inbounds/1/delClientByEmail/user1@example.com" \
  -b cookies.txt
```

---

### POST `/panel/api/inbounds/updateClient/{clientId}`

Update a client's configuration.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `clientId` | string | Client UUID |

**Request Body:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | integer | Yes | Inbound ID |
| `settings` | string | Yes | JSON string with updated client settings |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/inbounds/updateClient/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{
    "id": 1,
    "settings": "{\"clients\":[{\"id\":\"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx\",\"flow\":\"xtls-rprx-vision\",\"email\":\"user1@example.com\",\"limitIp\":5,\"totalGB\":53687091200,\"expiryTime\":1767225600000,\"enable\":true}]}"
  }'
```

---

### POST `/panel/api/inbounds/{id}/resetClientTraffic/{email}`

Reset traffic counter for a specific client.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Inbound ID |
| `email` | string | Client email |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/inbounds/1/resetClientTraffic/user1@example.com" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "Client traffic reset successfully"
}
```

---

### POST `/panel/api/inbounds/resetAllTraffics`

Reset traffic counters for all inbounds and clients.

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/inbounds/resetAllTraffics" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "All traffic reset successfully"
}
```

---

### POST `/panel/api/inbounds/resetAllClientTraffics/{id}`

Reset traffic counters for all clients in a specific inbound.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Inbound ID |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/inbounds/resetAllClientTraffics/1" \
  -b cookies.txt
```

---

### POST `/panel/api/inbounds/delDepletedClients/{id}`

Delete clients who have exhausted their traffic limits.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Inbound ID |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/inbounds/delDepletedClients/1" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "Depleted clients deleted successfully"
}
```

---

### POST `/panel/api/inbounds/import`

Import an inbound configuration.

**Request Body** (form-urlencoded):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `data` | string | Yes | JSON string with full inbound configuration |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/inbounds/import" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -b cookies.txt \
  -d 'data={"remark":"Imported","port":8443,"protocol":"vless",...}'
```

---

### POST `/panel/api/inbounds/onlines`

Get list of currently online clients.

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/inbounds/onlines" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": ["user1@example.com", "user2@example.com"]
}
```

---

### POST `/panel/api/inbounds/lastOnline`

Get last online timestamps for all clients.

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/inbounds/lastOnline" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": {
    "user1@example.com": 1704067200000,
    "user2@example.com": 1704153600000
  }
}
```

---

### POST `/panel/api/inbounds/updateClientTraffic/{email}`

Update traffic statistics for a client.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `email` | string | Client email |

**Request Body** (JSON):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `upload` | integer | Yes | Upload bytes to add |
| `download` | integer | Yes | Download bytes to add |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/inbounds/updateClientTraffic/user1@example.com" \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{"upload": 1000000, "download": 5000000}'
```

---

## 3. Server API

Base path: `/panel/api/server`

### GET `/panel/api/server/status`

Get current server status including CPU, memory, disk usage, and Xray status.

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/api/server/status" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": {
    "cpu": 15.5,
    "cpuCores": 4,
    "cpuSpeedMhz": 2400,
    "mem": {
      "current": 2147483648,
      "total": 8589934592
    },
    "swap": {
      "current": 0,
      "total": 2147483648
    },
    "disk": {
      "current": 53687091200,
      "total": 107374182400
    },
    "xray": {
      "state": "running",
      "errorMsg": "",
      "version": "24.12.18"
    },
    "uptime": 86400,
    "loads": [0.5, 0.3, 0.2],
    "tcpCount": 150,
    "udpCount": 25,
    "netIO": {
      "up": 1234567890,
      "down": 9876543210
    },
    "netTraffic": {
      "sent": 12345678900,
      "recv": 98765432100
    },
    "publicIP": {
      "ipv4": "203.0.113.1",
      "ipv6": "2001:db8::1"
    },
    "appStats": {
      "threads": 20,
      "mem": 104857600,
      "uptime": 86000
    }
  }
}
```

---

### GET `/panel/api/server/cpuHistory/{bucket}`

Get aggregated CPU usage history.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `bucket` | integer | Aggregation interval in seconds. Allowed: `2`, `30`, `60`, `120`, `180`, `300` |

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/api/server/cpuHistory/60" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": [
    {"time": 1704067200, "cpu": 12.5},
    {"time": 1704067260, "cpu": 15.2},
    {"time": 1704067320, "cpu": 10.8}
  ]
}
```

---

### GET `/panel/api/server/getXrayVersion`

Get available Xray versions for installation.

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/api/server/getXrayVersion" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": ["24.12.18", "24.11.30", "24.11.21", "24.10.31"]
}
```

---

### GET `/panel/api/server/getConfigJson`

Get the current Xray configuration as JSON.

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/api/server/getConfigJson" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": {
    "log": {...},
    "api": {...},
    "inbounds": [...],
    "outbounds": [...],
    "routing": {...}
  }
}
```

---

### GET `/panel/api/server/getDb`

Download the database backup file.

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/api/server/getDb" \
  -b cookies.txt \
  -o x-ui-db-backup.sql
```

**Response:** Binary SQL file download with headers:
- `Content-Type: application/sql`
- `Content-Disposition: attachment; filename=x-ui-db-backup.sql`

---

### GET `/panel/api/server/getNewUUID`

Generate a new UUID.

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/api/server/getNewUUID" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": "550e8400-e29b-41d4-a716-446655440000"
}
```

---

### GET `/panel/api/server/getNewX25519Cert`

Generate a new X25519 key pair for Reality protocol.

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/api/server/getNewX25519Cert" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": {
    "privateKey": "base64-encoded-private-key",
    "publicKey": "base64-encoded-public-key"
  }
}
```

---

### GET `/panel/api/server/getNewmldsa65`

Generate a new ML-DSA-65 (Dilithium) key pair.

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/api/server/getNewmldsa65" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": {
    "privateKey": "base64-encoded-private-key",
    "publicKey": "base64-encoded-public-key"
  }
}
```

---

### GET `/panel/api/server/getNewmlkem768`

Generate a new ML-KEM-768 key pair.

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/api/server/getNewmlkem768" \
  -b cookies.txt
```

---

### GET `/panel/api/server/getNewVlessEnc`

Generate a new VLESS encryption key.

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/api/server/getNewVlessEnc" \
  -b cookies.txt
```

---

### POST `/panel/api/server/stopXrayService`

Stop the Xray service.

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/server/stopXrayService" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "Xray stopped successfully"
}
```

---

### POST `/panel/api/server/restartXrayService`

Restart the Xray service.

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/server/restartXrayService" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "Xray restarted successfully"
}
```

---

### POST `/panel/api/server/installXray/{version}`

Install a specific Xray version.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `version` | string | Xray version to install (e.g., `24.12.18`) |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/server/installXray/24.12.18" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "Xray version switched successfully"
}
```

---

### POST `/panel/api/server/installXrayOnNodes/{version}`

Install Xray version on selected nodes (multi-node mode).

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `version` | string | Xray version to install |

**Request Body** (JSON or form-urlencoded):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `nodeIds` | array | Yes | Array of node IDs |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/server/installXrayOnNodes/24.12.18" \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{"nodeIds": [1, 2, 3]}'
```

---

### POST `/panel/api/server/updateGeofile`

Update all geo files (geoip.dat, geosite.dat).

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/server/updateGeofile" \
  -b cookies.txt
```

---

### POST `/panel/api/server/updateGeofile/{fileName}`

Update a specific geo file.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `fileName` | string | File name: `geoip.dat` or `geosite.dat` |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/server/updateGeofile/geoip.dat" \
  -b cookies.txt
```

---

### POST `/panel/api/server/logs/{count}`

Get application logs.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `count` | integer | Number of log lines to retrieve |

**Request Body** (form-urlencoded):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `level` | string | No | Log level filter: `debug`, `info`, `warning`, `error` |
| `syslog` | string | No | Include system logs: `true` or `false` |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/server/logs/100" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -b cookies.txt \
  -d "level=info&syslog=false"
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": [
    "2024-01-01 12:00:00 INFO - Server started",
    "2024-01-01 12:00:01 INFO - Xray started successfully"
  ]
}
```

---

### POST `/panel/api/server/xraylogs/{count}`

Get Xray access logs with filtering options.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `count` | integer | Number of log entries to retrieve |

**Request Body** (form-urlencoded):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `filter` | string | No | Text filter for logs |
| `showDirect` | string | No | Show direct traffic: `true`/`false` |
| `showBlocked` | string | No | Show blocked traffic: `true`/`false` |
| `showProxy` | string | No | Show proxied traffic: `true`/`false` |
| `nodeId` | string | No | Filter by node ID (multi-node mode) |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/server/xraylogs/100" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -b cookies.txt \
  -d "showDirect=true&showBlocked=true&showProxy=true"
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": [
    {
      "DateTime": "2024-01-01T12:00:00Z",
      "FromAddress": "192.168.1.100:54321",
      "ToAddress": "google.com:443",
      "Inbound": "inbound-443",
      "Outbound": "direct",
      "Email": "user1@example.com",
      "Event": 0
    }
  ]
}
```

Event types: `0` = Direct, `1` = Blocked, `2` = Proxied

---

### POST `/panel/api/server/importDB`

Import a database file.

**Request Body** (multipart/form-data):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | file | Yes | Database file to import |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/server/importDB" \
  -b cookies.txt \
  -F "db=@/path/to/backup.db"
```

**Response:**

```json
{
  "success": true,
  "msg": "Database imported successfully"
}
```

---

### POST `/panel/api/server/getNewEchCert`

Generate a new ECH (Encrypted Client Hello) certificate.

**Request Body** (form-urlencoded):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `sni` | string | Yes | Server Name Indication |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/server/getNewEchCert" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -b cookies.txt \
  -d "sni=example.com"
```

---

## 4. Settings

Base path: `/panel/setting`

### POST `/panel/setting/all`

Get all panel settings.

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/setting/all" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": {
    "webListen": "",
    "webDomain": "",
    "webPort": 2053,
    "webCertFile": "",
    "webKeyFile": "",
    "webBasePath": "/",
    "sessionMaxAge": 60,
    "pageSize": 50,
    "expireDiff": 0,
    "trafficDiff": 0,
    "remarkModel": "",
    "datepicker": "gregorian",
    "tgBotEnable": false,
    "tgBotToken": "",
    "tgBotProxy": "",
    "tgBotAPIServer": "",
    "tgBotChatId": "",
    "tgRunTime": "@daily",
    "tgBotBackup": false,
    "tgBotLoginNotify": false,
    "tgCpu": 80,
    "tgLang": "en-US",
    "timeLocation": "UTC",
    "twoFactorEnable": false,
    "subEnable": true,
    "subJsonEnable": true,
    "subTitle": "3x-ui",
    "subListen": "",
    "subPort": 2096,
    "subPath": "/sub/",
    "subDomain": "",
    "subUpdates": 12,
    "subEncrypt": true,
    "subShowInfo": true,
    "subJsonPath": "/json/",
    "multiNodeMode": false,
    "hwidMode": "client_header"
  }
}
```

---

### POST `/panel/setting/defaultSettings`

Get default settings for initial setup.

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/setting/defaultSettings" \
  -b cookies.txt
```

---

### POST `/panel/setting/update`

Update panel settings.

**Request Body** (form-urlencoded or JSON): Any fields from the settings object.

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/setting/update" \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{
    "webPort": 2053,
    "sessionMaxAge": 120,
    "tgBotEnable": true,
    "tgBotToken": "your-bot-token",
    "tgBotChatId": "123456789"
  }'
```

**Response:**

```json
{
  "success": true,
  "msg": "Settings updated successfully"
}
```

---

### POST `/panel/setting/updateUser`

Update current user's username and password.

**Request Body** (form-urlencoded or JSON):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `oldUsername` | string | Yes | Current username |
| `oldPassword` | string | Yes | Current password |
| `newUsername` | string | Yes | New username |
| `newPassword` | string | Yes | New password |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/setting/updateUser" \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{
    "oldUsername": "admin",
    "oldPassword": "oldpassword",
    "newUsername": "admin",
    "newPassword": "newSecurePassword123"
  }'
```

---

### POST `/panel/setting/restartPanel`

Restart the panel service (takes effect after 3 seconds).

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/setting/restartPanel" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "Panel restart initiated"
}
```

---

### GET `/panel/setting/getDefaultJsonConfig`

Get the default Xray configuration template.

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/setting/getDefaultJsonConfig" \
  -b cookies.txt
```

---

## 5. Migration

Base path: `/panel/setting/migration`

### POST `/panel/setting/migration/preview`

Preview migration data from an SQLite database file.

**Request Body** (multipart/form-data):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `file` | file | Yes | SQLite database file (max 100MB) |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/setting/migration/preview" \
  -b cookies.txt \
  -F "file=@/path/to/x-ui.db"
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": {
    "users": 5,
    "inbounds": 10,
    "clientStats": 50,
    "settings": 25
  }
}
```

---

### POST `/panel/setting/migration/execute`

Execute migration from SQLite to PostgreSQL.

**Request Body** (multipart/form-data):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `file` | file | Yes | SQLite database file (max 100MB) |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/setting/migration/execute" \
  -b cookies.txt \
  -F "file=@/path/to/x-ui.db"
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": {
    "success": true,
    "migratedUsers": 5,
    "migratedInbounds": 10,
    "migratedClientStats": 50,
    "warnings": []
  }
}
```

---

## 6. Xray Settings

Base path: `/panel/xray`

### GET `/panel/xray/getDefaultJsonConfig`

Get default Xray configuration.

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/xray/getDefaultJsonConfig" \
  -b cookies.txt
```

---

### GET `/panel/xray/getOutboundsTraffic`

Get traffic statistics for all outbounds.

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/xray/getOutboundsTraffic" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": [
    {
      "id": 1,
      "tag": "direct",
      "up": 123456789,
      "down": 987654321,
      "total": 1111111110
    },
    {
      "id": 2,
      "tag": "blocked",
      "up": 0,
      "down": 1234567,
      "total": 1234567
    }
  ]
}
```

---

### GET `/panel/xray/getXrayResult`

Get the current Xray service status/result.

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/xray/getXrayResult" \
  -b cookies.txt
```

---

### POST `/panel/xray/`

Get Xray settings template and inbound tags.

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/xray/" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": "{ \"xraySetting\": {...}, \"inboundTags\": [\"inbound-443\", \"inbound-80\"] }"
}
```

---

### POST `/panel/xray/warp/{action}`

Manage Cloudflare WARP integration.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `action` | string | Action: `data`, `del`, `config`, `reg`, `license` |

**Actions:**

- `data` - Get WARP data
- `del` - Delete WARP configuration
- `config` - Get WARP config
- `reg` - Register WARP (requires `privateKey` and `publicKey` in body)
- `license` - Set WARP license (requires `license` in body)

**Example Request (Register WARP):**

```bash
curl -X POST "http://localhost:2053/panel/xray/warp/reg" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -b cookies.txt \
  -d "privateKey=xxx&publicKey=yyy"
```

---

### POST `/panel/xray/update`

Update Xray settings.

**Request Body** (form-urlencoded):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `xraySetting` | string | Yes | Full Xray configuration JSON string |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/xray/update" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -b cookies.txt \
  -d "xraySetting={...}"
```

---

### POST `/panel/xray/resetOutboundsTraffic`

Reset traffic statistics for an outbound.

**Request Body** (form-urlencoded):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `tag` | string | Yes | Outbound tag to reset |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/xray/resetOutboundsTraffic" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -b cookies.txt \
  -d "tag=direct"
```

---

## 7. Nodes (Multi-Node Mode)

Base path: `/panel/node`

### GET `/panel/node/list`

Get all nodes with their assigned inbounds.

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/node/list" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": [
    {
      "id": 1,
      "name": "Node-1",
      "address": "http://192.168.1.100:8080",
      "apiKey": "xxxxx",
      "status": "online",
      "lastCheck": 1704067200,
      "responseTime": 50,
      "useTls": false,
      "insecureTls": false,
      "createdAt": 1703980800,
      "updatedAt": 1704067200,
      "inbounds": [
        {"id": 1, "remark": "VLESS-443", "port": 443}
      ]
    }
  ]
}
```

---

### GET `/panel/node/get/{id}`

Get a specific node by ID.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Node ID |

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/node/get/1" \
  -b cookies.txt
```

---

### POST `/panel/node/add`

Add a new node (automatically registers with the panel).

**Request Body** (form-urlencoded or JSON):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | Yes | Node name |
| `address` | string | Yes | Node API address (e.g., `http://192.168.1.100:8080`) |
| `useTls` | boolean | No | Use HTTPS for API calls |
| `certPath` | string | No | Path to CA certificate (for custom CA) |
| `keyPath` | string | No | Path to private key |
| `insecureTls` | boolean | No | Skip certificate verification |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/node/add" \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{
    "name": "Node-2",
    "address": "http://192.168.1.101:8080",
    "useTls": false
  }'
```

**Response:**

```json
{
  "success": true,
  "msg": "Node added and registered successfully",
  "obj": {
    "id": 2,
    "name": "Node-2",
    "address": "http://192.168.1.101:8080",
    "apiKey": "generated-api-key",
    "status": "unknown"
  }
}
```

---

### POST `/panel/node/update/{id}`

Update an existing node.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Node ID |

**Request Body:** Same as `add` endpoint. Only provided fields will be updated.

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/node/update/1" \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{"name": "Updated-Node-Name"}'
```

---

### POST `/panel/node/del/{id}`

Delete a node.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Node ID |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/node/del/1" \
  -b cookies.txt
```

---

### POST `/panel/node/check/{id}`

Check the health of a specific node.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Node ID |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/node/check/1" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "Node health check completed",
  "obj": {
    "id": 1,
    "status": "online",
    "responseTime": 45
  }
}
```

---

### POST `/panel/node/checkAll`

Check the health of all nodes.

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/node/checkAll" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "Health check initiated for all nodes"
}
```

---

### GET `/panel/node/status/{id}`

Get detailed status of a node.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Node ID |

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/node/status/1" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": {
    "status": "online",
    "xray": {
      "state": "running",
      "version": "24.12.18"
    },
    "cpu": 15.5,
    "mem": {
      "current": 1073741824,
      "total": 4294967296
    },
    "uptime": 86400
  }
}
```

---

### POST `/panel/node/reload/{id}`

Reload Xray configuration on a specific node.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Node ID |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/node/reload/1" \
  -b cookies.txt
```

---

### POST `/panel/node/reloadAll`

Reload Xray configuration on all nodes.

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/node/reloadAll" \
  -b cookies.txt
```

---

### POST `/panel/node/logs/{id}`

Get Xray logs from a specific node.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Node ID |

**Request Body** (form-urlencoded):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `count` | string | No | Number of log entries (default: 100) |
| `filter` | string | No | Text filter |
| `showDirect` | string | No | Show direct traffic: `true`/`false` |
| `showBlocked` | string | No | Show blocked traffic: `true`/`false` |
| `showProxy` | string | No | Show proxied traffic: `true`/`false` |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/node/logs/1" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -b cookies.txt \
  -d "count=100&showDirect=true&showBlocked=true&showProxy=true"
```

---

### POST `/panel/node/check-connection`

Check if a node is reachable (no API key required, for pre-registration check).

**Request Body** (form-urlencoded or JSON):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `address` | string | Yes | Node address to check |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/node/check-connection" \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{"address": "http://192.168.1.100:8080"}'
```

**Response:**

```json
{
  "success": true,
  "msg": "Node is reachable (response time: 45 ms)",
  "obj": {
    "responseTime": 45
  }
}
```

---

## 8. Clients

Base path: `/panel/client`

Client entities are separate from inbound clients and can be assigned to multiple inbounds.

### GET `/panel/client/list`

Get all clients for the current user.

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/client/list" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": [
    {
      "id": 1,
      "userId": 1,
      "email": "user1@example.com",
      "uuid": "550e8400-e29b-41d4-a716-446655440000",
      "security": "auto",
      "password": "",
      "flow": "xtls-rprx-vision",
      "limitIp": 2,
      "totalGB": 10.5,
      "expiryTime": 1735689600000,
      "enable": true,
      "status": "active",
      "tgId": 0,
      "subId": "random-sub-id",
      "comment": "Test user",
      "reset": 0,
      "createdAt": 1703980800,
      "updatedAt": 1704067200,
      "inboundIds": [1, 2],
      "up": 123456789,
      "down": 987654321,
      "allTime": 1111111110,
      "lastOnline": 1704067200,
      "hwidEnabled": false,
      "maxHwid": 1
    }
  ]
}
```

---

### GET `/panel/client/get/{id}`

Get a specific client by ID.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Client ID |

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/client/get/1" \
  -b cookies.txt
```

---

### POST `/panel/client/add`

Create a new client entity.

**Request Body** (form-urlencoded or JSON):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `email` | string | Yes | Client email (unique per user) |
| `uuid` | string | No | UUID for VMESS/VLESS (auto-generated if empty) |
| `security` | string | No | Security method |
| `password` | string | No | Password for Trojan/Shadowsocks |
| `flow` | string | No | Flow control for XTLS |
| `limitIp` | integer | No | IP limit (0 = unlimited) |
| `totalGB` | float | No | Traffic limit in GB (0 = unlimited) |
| `expiryTime` | integer | No | Expiration timestamp in ms (0 = never) |
| `enable` | boolean | No | Enable client (default: true) |
| `tgId` | integer | No | Telegram user ID |
| `subId` | string | No | Subscription ID |
| `comment` | string | No | Comment |
| `reset` | integer | No | Traffic reset period in days |
| `hwidEnabled` | boolean | No | Enable HWID tracking |
| `maxHwid` | integer | No | Max HWID devices (0 = unlimited) |
| `inboundIds` | array | No | Array of inbound IDs to assign |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/client/add" \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{
    "email": "newuser@example.com",
    "uuid": "550e8400-e29b-41d4-a716-446655440000",
    "flow": "xtls-rprx-vision",
    "limitIp": 2,
    "totalGB": 50,
    "expiryTime": 1767225600000,
    "enable": true,
    "inboundIds": [1, 2]
  }'
```

---

### POST `/panel/client/update/{id}`

Update an existing client.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Client ID |

**Request Body:** Same as `add` endpoint. Only provided fields will be updated.

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/client/update/1" \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{
    "totalGB": 100,
    "enable": true,
    "inboundIds": [1, 2, 3]
  }'
```

---

### POST `/panel/client/del/{id}`

Delete a client.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Client ID |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/client/del/1" \
  -b cookies.txt
```

---

### POST `/panel/client/resetAllTraffics`

Reset traffic counters for all clients of the current user.

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/client/resetAllTraffics" \
  -b cookies.txt
```

---

### POST `/panel/client/resetTraffic/{id}`

Reset traffic counter for a specific client.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Client ID |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/client/resetTraffic/1" \
  -b cookies.txt
```

---

### POST `/panel/client/delDepletedClients`

Delete clients that have exhausted their traffic limits or expired.

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/client/delDepletedClients" \
  -b cookies.txt
```

---

## 9. Client HWID

Base path: `/panel/client/hwid`

Hardware ID tracking for device management.

### GET `/panel/client/hwid/list/{clientId}`

Get all HWIDs registered for a client.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `clientId` | integer | Client ID |

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/client/hwid/list/1" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": [
    {
      "id": 1,
      "clientId": 1,
      "hwid": "device-hardware-id-hash",
      "deviceOs": "Android",
      "deviceModel": "Samsung Galaxy S21",
      "osVersion": "14",
      "firstSeenAt": 1703980800,
      "lastSeenAt": 1704067200,
      "firstSeenIp": "192.168.1.100",
      "isActive": true,
      "ipAddress": "192.168.1.100",
      "userAgent": "v2rayNG/1.8.0"
    }
  ]
}
```

---

### POST `/panel/client/hwid/add`

Manually add a HWID for a client.

**Request Body** (form-urlencoded or JSON):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `clientId` | integer | Yes | Client ID |
| `hwid` | string | Yes | Hardware ID |
| `deviceOs` | string | No | Device OS |
| `deviceModel` | string | No | Device model |
| `osVersion` | string | No | OS version |
| `ipAddress` | string | No | IP address |
| `userAgent` | string | No | User agent |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/client/hwid/add" \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{
    "clientId": 1,
    "hwid": "custom-device-id",
    "deviceOs": "iOS",
    "deviceModel": "iPhone 15"
  }'
```

---

### POST `/panel/client/hwid/del/{id}`

Remove a HWID.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | HWID record ID |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/client/hwid/del/1" \
  -b cookies.txt
```

---

### POST `/panel/client/hwid/deactivate/{id}`

Deactivate a HWID (mark as inactive without deleting).

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | HWID record ID |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/client/hwid/deactivate/1" \
  -b cookies.txt
```

---

### POST `/panel/client/hwid/check`

Check if a HWID is allowed for a client.

**Request Body** (form-urlencoded or JSON):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `clientId` | integer | Yes | Client ID |
| `hwid` | string | Yes | Hardware ID to check |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/client/hwid/check" \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{"clientId": 1, "hwid": "device-id-hash"}'
```

**Response:**

```json
{
  "success": true,
  "obj": {
    "allowed": true
  }
}
```

---

### POST `/panel/client/hwid/register`

Register a HWID from a client application.

**Request Body** (form-urlencoded or JSON):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `email` | string | Yes | Client email |

**Required Headers:**

| Header | Required | Description |
|--------|----------|-------------|
| `x-hwid` | Yes | Hardware ID |
| `x-device-os` | No | Device operating system |
| `x-device-model` | No | Device model |
| `x-ver-os` | No | OS version |
| `User-Agent` | No | User agent string |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/client/hwid/register" \
  -H "Content-Type: application/json" \
  -H "x-hwid: device-hardware-id" \
  -H "x-device-os: Android" \
  -H "x-device-model: Pixel 8" \
  -H "x-ver-os: 14" \
  -b cookies.txt \
  -d '{"email": "user1@example.com"}'
```

---

### POST `/panel/client/hwid/fix-timestamps`

Fix all HWID records with incorrect timestamps (migration utility).

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/client/hwid/fix-timestamps" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "Fixed timestamps for 15 HWID records",
  "obj": {
    "fixedCount": 15
  }
}
```

---

## 10. Hosts

Base path: `/panel/host`

Hosts are used to override node addresses when generating subscription links.

### GET `/panel/host/list`

Get all hosts for the current user.

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/host/list" \
  -b cookies.txt
```

**Response:**

```json
{
  "success": true,
  "msg": "",
  "obj": [
    {
      "id": 1,
      "userId": 1,
      "name": "CDN Host",
      "address": "cdn.example.com",
      "port": 443,
      "protocol": "",
      "remark": "Cloudflare CDN",
      "enable": true,
      "createdAt": 1703980800,
      "updatedAt": 1704067200,
      "inboundIds": [1, 2]
    }
  ]
}
```

---

### GET `/panel/host/get/{id}`

Get a specific host by ID.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Host ID |

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/host/get/1" \
  -b cookies.txt
```

---

### POST `/panel/host/add`

Create a new host.

**Request Body** (form-urlencoded or JSON):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | Yes | Host name |
| `address` | string | Yes | Host address (IP or domain) |
| `port` | integer | No | Port (0 = use inbound port) |
| `protocol` | string | No | Protocol override |
| `remark` | string | No | Description |
| `enable` | boolean | No | Enable host (default: true) |
| `inboundIds` | array | No | Array of inbound IDs |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/host/add" \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{
    "name": "CDN Host",
    "address": "cdn.example.com",
    "port": 443,
    "remark": "Cloudflare CDN endpoint",
    "enable": true,
    "inboundIds": [1, 2]
  }'
```

---

### POST `/panel/host/update/{id}`

Update an existing host.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Host ID |

**Request Body:** Same as `add` endpoint.

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/host/update/1" \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{"address": "new-cdn.example.com"}'
```

---

### POST `/panel/host/del/{id}`

Delete a host.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | integer | Host ID |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/host/del/1" \
  -b cookies.txt
```

---

## 11. Node Push API

Base path: `/panel/api/node`

This endpoint is used by nodes to push logs to the panel. It uses API key authentication instead of session authentication.

### POST `/panel/api/node/push-logs`

Receive logs from a node (called by node applications).

**Request Body** (JSON):

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `apiKey` | string | Yes | Node API key |
| `nodeAddress` | string | No | Node's own address (for identification when multiple nodes share API key) |
| `logs` | array | Yes | Array of log lines in format "timestamp level - message" |

**Example Request:**

```bash
curl -X POST "http://localhost:2053/panel/api/node/push-logs" \
  -H "Content-Type: application/json" \
  -d '{
    "apiKey": "node-api-key",
    "nodeAddress": "http://192.168.1.100:8080",
    "logs": [
      "2024-01-01 12:00:00 INFO - Connection established",
      "2024-01-01 12:00:01 DEBUG - Processing request"
    ]
  }'
```

**Response:**

```json
{
  "message": "Logs received"
}
```

---

## 12. Subscription Server

The subscription server runs on a separate port (default: 2096) and provides subscription links for proxy clients.

### GET `/{subPath}/{subId}`

Get subscription links in text format.

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `subPath` | string | Subscription path (default: `/sub/`) |
| `subId` | string | Client subscription ID |

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `html` | string | Set to `1` to get HTML page |
| `view` | string | Set to `html` to get HTML page |

**Request Headers (Optional, for HWID registration):**

| Header | Description |
|--------|-------------|
| `x-hwid` | Hardware ID |
| `x-device-os` | Device OS |
| `x-device-model` | Device model |
| `x-ver-os` | OS version |

**Example Request:**

```bash
curl -X GET "http://localhost:2096/sub/abcd1234" \
  -H "x-hwid: device-id"
```

**Response Headers:**

| Header | Description |
|--------|-------------|
| `Subscription-Userinfo` | Traffic info: `upload=X; download=Y; total=Z; expire=T` |
| `Profile-Update-Interval` | Update interval in hours |
| `Profile-Title` | Base64-encoded profile title |
| `X-Subscription-ID` | Subscription ID |

**Text Response:**

```
vless://uuid@host:port?type=tcp&security=reality&...#Remark
vmess://base64-encoded-config
trojan://password@host:port?...#Remark
```

**HTML Response (with `?html=1`):** Renders an information page with QR codes and subscription details.

---

### GET `/{subJsonPath}/{subId}`

Get subscription in JSON format (for sing-box, clash-meta, etc.).

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `subJsonPath` | string | JSON subscription path (default: `/json/`) |
| `subId` | string | Client subscription ID |

**Example Request:**

```bash
curl -X GET "http://localhost:2096/json/abcd1234"
```

**Response:** JSON configuration for the proxy client (format depends on client type).

---

## 13. WebSocket

Real-time updates via WebSocket connection.

### WS `/ws`

Connect to WebSocket for real-time updates.

**Authentication:** Requires valid session cookie.

**Example Connection (JavaScript):**

```javascript
const ws = new WebSocket('ws://localhost:2053/ws');

ws.onmessage = function(event) {
  const data = JSON.parse(event.data);
  console.log('Message type:', data.type);
  console.log('Data:', data.data);
};
```

**Message Types:**

| Type | Description |
|------|-------------|
| `status` | Server status update |
| `inbounds` | Inbounds list update |
| `nodes` | Nodes list update |
| `xray_state` | Xray service state change |
| `notification` | System notification |

**Example Message:**

```json
{
  "type": "status",
  "data": {
    "cpu": 15.5,
    "mem": {"current": 2147483648, "total": 8589934592},
    "xray": {"state": "running", "version": "24.12.18"}
  }
}
```

---

## 14. Backup Endpoint

### GET `/panel/api/backuptotgbot`

Trigger a backup to Telegram bot admins.

**Example Request:**

```bash
curl -X GET "http://localhost:2053/panel/api/backuptotgbot" \
  -b cookies.txt
```

---

## Appendix: Data Models

### Inbound

```json
{
  "id": 1,
  "up": 0,
  "down": 0,
  "total": 0,
  "allTime": 0,
  "remark": "string",
  "enable": true,
  "expiryTime": 0,
  "trafficReset": "never",
  "lastTrafficResetTime": 0,
  "listen": "",
  "port": 443,
  "protocol": "vless",
  "settings": "JSON string",
  "streamSettings": "JSON string",
  "tag": "inbound-443",
  "sniffing": "JSON string",
  "nodeIds": [1, 2],
  "clientStats": []
}
```

### ClientEntity

```json
{
  "id": 1,
  "userId": 1,
  "email": "string",
  "uuid": "UUID string",
  "security": "auto",
  "password": "",
  "flow": "xtls-rprx-vision",
  "limitIp": 0,
  "totalGB": 0,
  "expiryTime": 0,
  "enable": true,
  "status": "active",
  "tgId": 0,
  "subId": "string",
  "comment": "",
  "reset": 0,
  "createdAt": 0,
  "updatedAt": 0,
  "inboundIds": [],
  "up": 0,
  "down": 0,
  "allTime": 0,
  "lastOnline": 0,
  "hwidEnabled": false,
  "maxHwid": 1
}
```

### Node

```json
{
  "id": 1,
  "name": "string",
  "address": "http://host:port",
  "apiKey": "string",
  "status": "online",
  "lastCheck": 0,
  "responseTime": 0,
  "useTls": false,
  "certPath": "",
  "keyPath": "",
  "insecureTls": false,
  "createdAt": 0,
  "updatedAt": 0
}
```

### Host

```json
{
  "id": 1,
  "userId": 1,
  "name": "string",
  "address": "string",
  "port": 0,
  "protocol": "",
  "remark": "",
  "enable": true,
  "createdAt": 0,
  "updatedAt": 0,
  "inboundIds": []
}
```

### ClientHWID

```json
{
  "id": 1,
  "clientId": 1,
  "hwid": "string",
  "deviceOs": "string",
  "deviceModel": "string",
  "osVersion": "string",
  "firstSeenAt": 0,
  "lastSeenAt": 0,
  "firstSeenIp": "string",
  "isActive": true,
  "ipAddress": "string",
  "userAgent": "string",
  "blockedAt": null,
  "blockReason": ""
}
```

---

## Protocol Reference

### Supported Protocols

| Protocol | Description |
|----------|-------------|
| `vmess` | VMess protocol |
| `vless` | VLESS protocol |
| `trojan` | Trojan protocol |
| `shadowsocks` | Shadowsocks protocol |
| `http` | HTTP proxy |
| `mixed` | Mixed HTTP/SOCKS proxy |
| `wireguard` | WireGuard protocol |

### Flow Types (VLESS)

| Flow | Description |
|------|-------------|
| `xtls-rprx-vision` | XTLS Vision flow (recommended) |
| (empty) | No flow control |

### Security Types

| Security | Description |
|----------|-------------|
| `reality` | Reality security (recommended) |
| `tls` | Standard TLS |
| `none` | No encryption |

### Network Types

| Network | Description |
|---------|-------------|
| `tcp` | Raw TCP |
| `ws` | WebSocket |
| `grpc` | gRPC |
| `http` | HTTP/2 |
| `quic` | QUIC |
| `kcp` | mKCP |

---

*Documentation generated for 3x-ui panel. For more information, see the project repository.*
