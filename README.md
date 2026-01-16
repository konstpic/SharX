<div align="center">

<!-- Liquid Glass Hero Section -->
<img src="https://capsule-render.vercel.app/api?type=waving&color=gradient&customColorList=0,2,3,5,30&height=300&section=header&text=3X-UI%20NEW&fontSize=70&fontAlignY=40&animation=fadeIn&fontColor=gradient&desc=Next%20Generation%20Panel%20%7C%20Multi-Node%20Management&descSize=25&descAlignY=60" width="100%"/>

</div>

<div align="center">

[English](README_EN.md) | [Русский](README_RU.md)

</div>

## Welcome to the New 3x-ui / Добро пожаловать в новую 3x-ui

Welcome to the next generation of 3x-ui! This version brings significant improvements, a modern architecture, and a streamlined installation process using Docker containers.

Добро пожаловать в новое поколение 3x-ui! Эта версия приносит значительные улучшения, современную архитектуру и упрощенный процесс установки с использованием Docker-контейнеров.

## Quick Start / Быстрый старт

### 🚀 One-Line Install / Установка одной командой

```bash
bash <(curl -Ls https://raw.githubusercontent.com/konstpic/3x-ui-new/main/install.sh)
```

Or clone and run / Или клонируйте и запустите:

```bash
git clone https://github.com/konstpic/3x-ui-new.git
cd 3x-ui-new
sudo bash install.sh
```

---

<details>
<summary><b>📜 Script Installation (Recommended) / Установка через скрипт (Рекомендуется)</b></summary>

### Automatic Installation / Автоматическая установка

The install script supports multiple Linux distributions and automatically:
- Installs Docker and Docker Compose
- Configures network mode (host/bridge)
- Sets up SSL certificates (Let's Encrypt for domain or IP)
- Generates secure database password
- Creates and starts all services

Скрипт установки поддерживает множество дистрибутивов Linux и автоматически:
- Устанавливает Docker и Docker Compose
- Настраивает режим сети (host/bridge)
- Настраивает SSL сертификаты (Let's Encrypt для домена или IP)
- Генерирует безопасный пароль базы данных
- Создаёт и запускает все сервисы

#### Supported Systems / Поддерживаемые системы

| Distribution | Package Manager |
|--------------|-----------------|
| Ubuntu/Debian | apt |
| Fedora | dnf |
| CentOS/RHEL | yum |
| Arch Linux | pacman |
| Alpine | apk |
| openSUSE | zypper |

#### Panel Installation / Установка панели

```bash
sudo bash install.sh
# Select: 1) Install Panel
```

#### Node Installation / Установка узла

```bash
sudo bash install.sh
# Select: 2) Install Node
```

#### Management Menu / Меню управления

After installation, run the script again to access the management menu:

После установки запустите скрипт снова для доступа к меню управления:

```bash
sudo bash install.sh
```

**Menu options / Опции меню:**
- Update Panel/Node
- Start/Stop/Restart services
- Change ports
- Renew SSL certificates
- View logs and status

</details>

---

<details>
<summary><b>🔧 Manual Installation / Ручная установка</b></summary>

### Panel Installation / Установка панели

1. **Clone the repository / Клонируйте репозиторий:**
   ```bash
   git clone https://github.com/konstpic/3x-ui-new.git
   cd 3x-ui-new
   ```

2. **Configure `docker-compose.yml` / Настройте `docker-compose.yml`:**
   - Change `change_this_password` to a secure password
   - Измените `change_this_password` на надёжный пароль
   ```yaml
   XUI_DB_PASSWORD: your_secure_password
   POSTGRES_PASSWORD: your_secure_password
   ```

3. **Prepare SSL certificates / Подготовьте SSL сертификаты:**
   ```bash
   mkdir -p cert
   cp /path/to/fullchain.pem cert/fullchain.pem
   cp /path/to/privkey.pem cert/privkey.pem
   ```

4. **Start services / Запустите сервисы:**
   ```bash
   docker compose up -d
   ```

5. **Access the panel / Откройте панель:**
   ```
   http://your-server-ip:2053
   ```

6. **Configure TLS in panel settings / Настройте TLS в панели:**
   - Certificate: `/app/cert/fullchain.pem`
   - Private Key: `/app/cert/privkey.pem`

### Node Installation / Установка узла

1. **Navigate to node directory / Перейдите в папку узла:**
   ```bash
   cd node
   ```

2. **Prepare certificates / Подготовьте сертификаты:**
   ```bash
   mkdir -p cert
   cp /path/to/fullchain.pem cert/fullchain.pem
   cp /path/to/privkey.pem cert/privkey.pem
   ```

3. **Start the node / Запустите узел:**
   ```bash
   docker compose up -d
   ```

4. **Connect to panel / Подключите к панели:**
   - Add new node in panel's Node Management
   - Добавьте новый узел в управлении узлами панели

</details>

---

## Key Features / Основные возможности

- **Node Mode**: One panel manages multiple nodes
- **PostgreSQL**: Full migration from SQLite
- **Redis Integration**: Enhanced performance with caching
- **Modern UI**: Glass Morphism design
- **Docker-Based**: Easy deployment with pre-built images
- **HWID Protection**: Device identification (Beta, Happ & V2RayTun)
- **Auto SSL**: Let's Encrypt certificates with auto-renewal

- **Режим узлов**: Одна панель управляет несколькими узлами
- **PostgreSQL**: Полная миграция с SQLite
- **Интеграция Redis**: Повышенная производительность с кэшированием
- **Современный интерфейс**: Дизайн Glass Morphism
- **На основе Docker**: Легкое развертывание с предварительно собранными образами
- **Защита HWID**: Идентификация устройств (Бета, Happ & V2RayTun)
- **Авто SSL**: Let's Encrypt сертификаты с автопродлением

## Documentation / Документация

For detailed installation instructions, configuration, and migration guide, please see:

Для подробных инструкций по установке, настройке и миграции, пожалуйста, смотрите:

- **[Full English Documentation](README_EN.md)** - Complete guide in English
- **[Полная русская документация](README_RU.md)** - Полное руководство на русском языке

## Requirements / Требования

- Linux server (Ubuntu, Debian, CentOS, Fedora, Arch, Alpine, openSUSE)
- Root access
- Domain name (optional, for TLS with domain)
- Port 80 open (for SSL certificate issuance)

- Linux сервер (Ubuntu, Debian, CentOS, Fedora, Arch, Alpine, openSUSE)
- Root доступ
- Доменное имя (опционально, для TLS с доменом)
- Открытый порт 80 (для выпуска SSL сертификата)

## Support / Поддержка

For issues, questions, or contributions, please refer to the project repository.

По вопросам, проблемам или вкладу в проект обращайтесь в репозиторий проекта.

## Authors / Авторы

**Project Authors / Авторы проекта:**
- @konspic
- @alireza0
- @MHSanaei

## Donate / Донаты 💵

**Crypto / Криптовалюта:**
- [Donate via NowPayments - MHSanaei](https://nowpayments.io/donation/hsanaei)
- [Donate via NowPayments - Alireza7](https://nowpayments.io/donation/alireza7)
- [Donate via Tribute - konspic](https://t.me/tribute/app?startapp=dDMW)

**Fiat (Card, Bank, Cash App Pay, G Pay, Link) / Фиат (Карта, Банк, Cash App Pay, G Pay, Link):**
- [Buy Me a Coffee - MHSanaei](https://buymeacoffee.com/mhsanaei)
- [Buy Me a Coffee - Alireza7](https://buymeacoffee.com/alireza7)
- [Donate via Tribute - konspic](https://t.me/tribute/app?startapp=dDMW)

---

**Note**: This version uses Docker containers for easy deployment. All images are pre-built and ready to use.

**Примечание**: Эта версия использует Docker-контейнеры для легкого развертывания. Все образы предварительно собраны и готовы к использованию.

<div align="center">

<!-- Liquid Glass Footer Section -->
<img src="https://capsule-render.vercel.app/api?type=waving&color=gradient&customColorList=0,2,3,5,30&height=300&section=footer&animation=fadeIn" width="100%"/>

</div>
