# 🚀 Smokeping Master + Slave Deployment Script

This script automates the deployment and management of **Smokeping** master and slave containers using Docker and MacVLAN networking.
It supports **multi-slave deployments**, **colored log monitoring**, and **secure configuration handling**.

---

## 📦 Features

* Deploys **one master** and configurable number of **slaves**
* Uses **MacVLAN networking** with static IP assignments
* **Automatically detects network interface** (suggests Docker’s default parent)
* **Automatically assigns Master IP** based on subnet (`.100`)
* **Randomly generates secure shared secret**
* Auto-generates `slavesecrets.conf` and `Slaves` configuration
* Secure handling of shared secrets (`chmod 600`)
* Supports **real-time colored log monitoring**
* Reload, restart, stop, and remove containers with one command
* Clean **log process management** and safe cleanup
* Master exposed on **port 80**, slaves run without external exposure

---

## ⚙️ Requirements

* **OS:** Ubuntu 20.04 / 22.04 / 24.04
* **Dependencies:**

  * Docker & Docker Compose
  * Bash (v4+)
  * `openssl` (for random secret generation)
* **Network:** MacVLAN supported interface

---

## 📑 Configuration

The script will now **auto-detect most settings**:

* **Parent Interface** – Shows all physical interfaces, suggests the one used by Docker by default
* **Master IP** – Automatically set to `.100` of the detected subnet
* **Shared Secret** – Securely randomized using `openssl rand -base64 16`

You only need to edit the following if you want custom values:

```bash
NETWORK_NAME="smokeping_macvlan"   # Docker network name
IMAGE="lscr.io/linuxserver/smokeping:latest"
CONFIG_BASE="/root/smokeping"      # Base directory for configs/data
TZ="Asia/Manila"                   # Timezone
CIDR_SUFFIX="24"                   # Subnet mask
MASTER_NAME="MAIN"                 # Master container name
SLAVE_BASE="ISP"                   # Slave name prefix
START_OFFSET=101                   # First slave IP offset
```

---

## 🚀 Usage


One-liner install:
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Kintoyyy/smokeping-multi-docker/main/install-containers.sh)"
```

Make the script executable:

```bash
chmod +x install-containers.sh
```

### Start deployment

```bash
./install-containers.sh start
```

You will be prompted for:

* Parent interface (default: Docker’s detected interface)
* Number of slave containers to create

### Start with debugging & colored log monitoring

```bash
./install-containers.sh start --debug
```

### Stop all containers

```bash
./install-containers.sh stop
```

### Remove all containers and network

```bash
./install-containers.sh remove
```

### Reload configuration

```bash
./install-containers.sh reload
```

### Restart containers

```bash
./install-containers.sh restart
```

---

## 📊 Debugging & Log Monitoring

In debug mode (`--debug`), the script shows real-time logs from all containers with color coding:

* 🟢 **MASTER** – Main Smokeping server (port 80 open)
* 🔵 **SLAVE1** – First slave container
* 🟣 **SLAVE2+** – Additional slaves, fallback colors used
* ⚪ **SYSTEM** – Deployment/system messages
* 🌫️ **MONITOR** – Log monitoring events

Example log format:

```
[2025-08-22 21:35:11] [MASTER:MAIN:10.15.0.100] Smokeping starting...
[2025-08-22 21:35:11] [SLAVE:ISP1:10.15.0.101] Slave connected to master
```

---

## 🔐 Security Notes

* Master container has **port 80 exposed** for the web interface
* Slave containers are **not exposed** (no port mapping)
* Shared secrets are stored securely (`chmod 600`)
* Secret is **randomized on every deployment**
* MacVLAN isolates containers from the Docker host for additional security
* Consider adding **iptables firewall rules** for stricter access

---

## 🧹 Cleanup

* **Stop only:**

  ```bash
  ./install-containers.sh stop
  ```
* **Remove everything (containers + network):**

  ```bash
  ./install-containers.sh remove
  ```

All background log monitoring processes are cleaned up automatically.

---

## 📖 Example Deployment Flow

```bash
$ ./install-containers.sh start
Available physical interfaces:
 - ens18
 - docker0
Enter the parent interface to use [default: ens18]:
How many slave containers to create? 3
[+] Using parent interface: ens18
[+] Master URL automatically set to: http://10.15.0.100/smokeping/smokeping.cgi
[+] Generated random shared secret: kPz3M7F9xLh2NcV8==

[+] Starting deployment of 1 master + 3 slave containers
[+] Creating macvlan network: smokeping_macvlan (subnet: 10.15.0.0/24, gateway: 10.15.0.1)
[+] Deploying Smokeping Master at 10.15.0.100
[+] Deploying Slave 1 (ISP1) at 10.15.0.101
[+] Deploying Slave 2 (ISP2) at 10.15.0.102
[+] Deploying Slave 3 (ISP3) at 10.15.0.103
[+] Deployment completed successfully!
```