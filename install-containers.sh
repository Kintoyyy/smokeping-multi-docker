#!/bin/bash

set -e

# chmod +x install-containers.sh
# ./install-containers.sh start --debug
# ./install-containers.sh remove
# ./install-containers.sh reload

# --- CONFIG --- #
NETWORK_NAME="smokeping_macvlan"
IMAGE="lscr.io/linuxserver/smokeping:latest"
CONFIG_BASE="/root/smokeping"
TZ="Asia/Manila"
CIDR_SUFFIX="24"
MASTER_NAME="MAIN"
SLAVE_BASE="SLAVE"
MASTER_IP_OFFSET=200
DEBUG=false

# --- COLOR DEFINITIONS --- #
declare -A COLORS=(
    ["RESET"]="\033[0m"
    ["BOLD"]="\033[1m"
    ["RED"]="\033[31m"
    ["GREEN"]="\033[32m"
    ["YELLOW"]="\033[33m"
    ["BLUE"]="\033[34m"
    ["MAGENTA"]="\033[35m"
    ["CYAN"]="\033[36m"
    ["WHITE"]="\033[37m"
    ["BRIGHT_RED"]="\033[91m"
    ["BRIGHT_GREEN"]="\033[92m"
    ["BRIGHT_YELLOW"]="\033[93m"
    ["BRIGHT_BLUE"]="\033[94m"
    ["BRIGHT_MAGENTA"]="\033[95m"
    ["BRIGHT_CYAN"]="\033[96m"
    ["GRAY"]="\033[90m"
)

# Color assignment for containers
declare -A CONTAINER_COLORS=(
    ["MASTER"]="${COLORS[BRIGHT_GREEN]}"
    ["MONITOR"]="${COLORS[GRAY]}"
    ["SYSTEM"]="${COLORS[WHITE]}"
)

FALLBACK_COLORS=("${COLORS[RED]}" "${COLORS[GREEN]}" "${COLORS[YELLOW]}" "${COLORS[BLUE]}" "${COLORS[MAGENTA]}" "${COLORS[CYAN]}")

# --- PARSE FLAGS --- #
for arg in "$@"; do
  case "$arg" in
    --debug|-debug) DEBUG=true ;;
  esac
done

# Store slave names entered by user
declare -a SLAVE_NAMES

get_container_color() {
    local container_type="$1"
    local container_name="$2"
    
    if [[ "$container_type" == "MASTER" ]]; then
        echo "${CONTAINER_COLORS[MASTER]}"
    elif [[ "$container_type" == "MONITOR" ]]; then
        echo "${CONTAINER_COLORS[MONITOR]}"
    elif [[ "$container_name" =~ ${SLAVE_BASE}([0-9]+) ]]; then
        local slave_num="${BASH_REMATCH[1]}"
        local color_key="SLAVE${slave_num}"
        
        if [[ -n "${CONTAINER_COLORS[$color_key]}" ]]; then
            echo "${CONTAINER_COLORS[$color_key]}"
        else
            # Use fallback colors for slaves beyond predefined ones
            local color_index=$(( (slave_num - 6) % ${#FALLBACK_COLORS[@]} ))
            echo "${FALLBACK_COLORS[$color_index]}"
        fi
    else
        echo "${CONTAINER_COLORS[SYSTEM]}"
    fi
}

colored_echo() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${COLORS[RESET]}"
}

system_log() {
    local message="$1"
    colored_echo "${CONTAINER_COLORS[SYSTEM]}" "$message"
}

get_subnet() {
  echo "$MASTER_URL" | grep -oP '(?<=http://)([0-9]{1,3}\.){3}' | sed "s/\.$/.0\/${CIDR_SUFFIX}/"
}

get_gateway() {
  echo "$MASTER_URL" | grep -oP '(?<=http://)([0-9]{1,3}\.){3}' | sed 's/\.$/.1/'
}

get_base_ip() {
  echo "$MASTER_URL" | grep -oP '(?<=http://)([0-9]{1,3}\.){3}[0-9]+' | cut -d. -f1-3
}

ensure_network_exists() {
  if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "[+] Network $NETWORK_NAME not found, creating..."
    create_macvlan_network
  else
    echo "[+] Network $NETWORK_NAME already exists"
  fi
}


create_macvlan_network() {
  local subnet=$(get_subnet)
  local gateway=$(get_gateway)

  system_log "[+] Creating macvlan network: $NETWORK_NAME (subnet: $subnet, gateway: $gateway)"
  docker network create -d macvlan \
    --subnet="$subnet" \
    --gateway="$gateway" \
    -o parent="$PARENT_IFACE" \
    "$NETWORK_NAME" || system_log "[i] Network already exists"
}

remove_network() {
  docker network rm "$NETWORK_NAME" 2>/dev/null || true
}

# Function to follow logs with container identification and colored output
follow_container_logs() {
  local container_name="$1"
  local container_type="$2"
  local container_ip="$3"
  
  local color=$(get_container_color "$container_type" "$container_name")
  local monitor_color="${CONTAINER_COLORS[MONITOR]}"
  
  colored_echo "$monitor_color" "[+] Starting log monitoring for $container_type: $container_name ($container_ip)"
  
  # Follow logs in background with container identification and error handling
  (
    # Check if container exists before starting
    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
      timestamp=$(date '+%Y-%m-%d %H:%M:%S')
      colored_echo "$monitor_color" "[$timestamp] [MONITOR:$container_name:$container_ip] Container not running, skipping log monitoring"
      exit 0
    fi
    
    # Follow logs until container stops
    docker logs -f "$container_name" 2>&1 | while IFS= read -r line; do
      timestamp=$(date '+%Y-%m-%d %H:%M:%S')
      colored_echo "$color" "[$timestamp] [$container_type:$container_name:$container_ip] $line"
    done
    
    # When we reach here, the container has stopped
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    colored_echo "$monitor_color" "[$timestamp] [MONITOR:$container_name:$container_ip] Container stopped, ending log monitoring"
  ) &
  
  # Store the background process PID for potential cleanup
  echo $! >> /tmp/smokeping_log_pids.tmp
}

deploy_master() {
  local master_ip=$(echo "$MASTER_URL" | grep -oP '(\d+\.\d+\.\d+\.\d+)' | head -1)
  system_log "[+] Deploying Smokeping Master at $master_ip (with port 80 access)"

  mkdir -p "$CONFIG_BASE/master/config" "$CONFIG_BASE/master/data"

  system_log "[+] Writing slavesecrets.conf"
  : > "$CONFIG_BASE/master/config/slavesecrets.conf"
  for i in $(seq 1 "$SLAVE_COUNT"); do
    local safe_name=$(sanitize_name "${SLAVE_NAMES[$((i-1))]}")
    echo "${safe_name}:${SHARED_SECRET}" >> "$CONFIG_BASE/master/config/slavesecrets.conf"
  done
  chmod 600 "$CONFIG_BASE/master/config/slavesecrets.conf"

  system_log "[+] Writing Slaves configuration file"
  cat > "$CONFIG_BASE/master/config/Slaves" << EOF
*** Slaves ***
secrets=/config/slavesecrets.conf 
EOF

  # Define colors for each slave
  local colors=("00ff00" "ff0000" "0000ff" "ffff00" "ff00ff" "00ffff" "ffa500" "800080")
  
  for i in $(seq 1 "$SLAVE_COUNT"); do
    local cname=$(sanitize_name "${SLAVE_NAMES[$((i-1))]}")
    local dname="${SLAVE_NAMES[$((i-1))]}"   # keep original for UI
    local color_index=$((i - 1))
    local color=${colors[$color_index % ${#colors[@]}]}
    cat >> "$CONFIG_BASE/master/config/Slaves" << EOF

+${cname}
display_name=${dname}
color=${color}
EOF
  done

system_log "[+] Updating Targets file with slaves configuration"
# Generate slaves list dynamically using actual sanitized slave names
local slaves_list=""
for i in $(seq 1 "$SLAVE_COUNT"); do
  local sname=$(sanitize_name "${SLAVE_NAMES[$((i-1))]}")
  if [ $i -eq 1 ]; then
    slaves_list="$sname"
  else
    slaves_list="$slaves_list $sname"
  fi
done

TARGETS_TEMPLATE="$(dirname "$0")/Targets.txt"
TARGETS_FILE="$CONFIG_BASE/master/config/Targets"

system_log "[+] Preparing Targets file"

if [ -f "$TARGETS_TEMPLATE" ]; then
  # Copy template into config dir
  cp "$TARGETS_TEMPLATE" "$TARGETS_FILE"

  # Insert slaves line after *** Targets *** header
  awk -v slaves_line="slaves = ${slaves_list}" '
    /^\*\*\* Targets \*\*\*/ {
      print
      print slaves_line
      next
    }
    { print }
  ' "$TARGETS_FILE" > "$TARGETS_FILE.tmp" && mv "$TARGETS_FILE.tmp" "$TARGETS_FILE"

  system_log "[+] Applied Targets from template and injected slaves"
else
  system_log "[!] Targets template not found, creating minimal file"
  cat > "$TARGETS_FILE" << EOF
*** Targets ***
menu = Top
title = Network Latency Grapher
remark = Generated by install-containers.sh

slaves = ${slaves_list}
EOF
fi

  system_log "[+] Writing apache2.conf to suppress FQDN warning"
  echo "ServerName $master_ip" > "$CONFIG_BASE/master/config/apache2.conf"

  docker run -d \
    --name="$MASTER_NAME" \
    --network="$NETWORK_NAME" \
    --ip="$master_ip" \
    --hostname="$MASTER_NAME" \
    -e TZ="$TZ" \
    -v "$CONFIG_BASE/master/config:/config" \
    -v "$CONFIG_BASE/master/data:/data" \
    -p 80:80 \
    --label role=smokeping-master \
    --label project=smokeping \
    --restart unless-stopped \
    "$IMAGE"

  colored_echo "${CONTAINER_COLORS[MASTER]}" "[+] Master container '$MASTER_NAME' deployed successfully with port 80 exposed"
  
  if $DEBUG; then
    follow_container_logs "$MASTER_NAME" "MASTER" "$master_ip"
  fi
}

deploy_slaves() {
  local base_ip=$(get_base_ip)

  for i in $(seq 1 "$SLAVE_COUNT"); do
    local ip="${base_ip}.$((MASTER_IP_OFFSET + i))"   # master is .200, slaves start at .201
    local cname="${SLAVE_NAMES[$((i-1))]}"
    local sconfig="$CONFIG_BASE/slaves/$cname"

    echo "[+] Preparing Slave $i ($cname) at $ip"

    # Check if IP is already in use
    existing_container=$(docker ps -a --format '{{.Names}} {{.Networks}}' \
      --filter "network=$NETWORK_NAME" | grep "$ip" | awk '{print $1}')

    if [[ -n "$existing_container" ]]; then
      echo "[!] IP $ip already in use by container $existing_container — removing it..."
      docker rm -f "$existing_container" >/dev/null 2>&1 || true
    fi

    rm -rf "$sconfig"
    mkdir -p "$sconfig"

    echo "$SHARED_SECRET" > "$sconfig/secret.txt"
    chmod 600 "$sconfig/secret.txt"
    echo "ServerName $ip" > "$sconfig/apache2.conf"

    docker run -d \
      --name="$cname" \
      --network="$NETWORK_NAME" \
      --ip="$ip" \
      --hostname="$cname" \
      -e TZ="$TZ" \
      -e MASTER_URL="$MASTER_URL" \
      -e SHARED_SECRET="$SHARED_SECRET" \
      -e CACHE_DIR="/tmp" \
      -e SLAVE_NAME="$cname" \
      -v "$sconfig:/var/smokeping" \
      --label role=smokeping-slave \
      --label project=smokeping \
      --label display_name="$sname" \
      --restart unless-stopped \
      "$IMAGE"

echo "[+] Slave container '$cname' deployed successfully at $ip"

    if $DEBUG; then
      follow_container_logs "$cname" "SLAVE" "$ip"
    fi


  done
}


reload_all() {
  system_log "[+] Reloading smokeping configuration on all containers..."
  
  local reloaded_count=0
  
  # Reload master
  local master_containers=$(docker ps --filter "label=role=smokeping-master" --format '{{.Names}}')
  if [[ -n "$master_containers" ]]; then
    while IFS= read -r container_name; do
      colored_echo "${CONTAINER_COLORS[MASTER]}" "[+] Sending reload signal to master container: $container_name"
      docker exec "$container_name" smokeping --reload 2>/dev/null || \
      docker exec "$container_name" bash -c "pkill -HUP smokeping" 2>/dev/null || \
      colored_echo "${COLORS[YELLOW]}" "[!] Failed to reload $container_name (container might not support reload)"
      ((reloaded_count++))
    done <<< "$master_containers"
  else
    colored_echo "${COLORS[RED]}" "[!] No master containers are currently running"
  fi
  
  # Reload slaves
  local slave_containers=$(docker ps --filter "label=role=smokeping-slave" --format '{{.Names}}' | sort)
  if [[ -n "$slave_containers" ]]; then
    while IFS= read -r container_name; do
      local slave_color=$(get_container_color "SLAVE" "$container_name")
      colored_echo "$slave_color" "[+] Sending reload signal to slave container: $container_name"
      docker exec "$container_name" smokeping --reload 2>/dev/null || \
      docker exec "$container_name" bash -c "pkill -HUP smokeping" 2>/dev/null || \
      colored_echo "${COLORS[YELLOW]}" "[!] Failed to reload $container_name (container might not support reload)"
      ((reloaded_count++))
    done <<< "$slave_containers"
  else
    colored_echo "${COLORS[YELLOW]}" "[!] No slave containers are currently running"
  fi
  
  if [[ $reloaded_count -gt 0 ]]; then
    system_log "[+] Reload command sent to $reloaded_count container(s)"
    system_log "[+] Check container logs to verify configuration reload"
  else
    colored_echo "${COLORS[RED]}" "[!] No containers were available for reload"
  fi
}

stop_all() {
  system_log "[+] Stopping all containers..."
  cleanup_log_processes
  docker ps -a --filter "label=role=smokeping-slave" --format '{{.Names}}' | xargs -r docker stop
  docker ps -a --filter "label=role=smokeping-master" --format '{{.Names}}' | xargs -r docker stop
  system_log "[+] All containers stopped"
}

remove_all() {
  system_log "[+] Removing all containers, firewall rules, and network..."
  cleanup_log_processes
  docker ps -a --filter "label=role=smokeping-slave" --format '{{.Names}}' | xargs -r docker rm -f
  docker ps -a --filter "label=role=smokeping-master" --format '{{.Names}}' | xargs -r docker rm -f
  remove_network
  system_log "[+] Cleanup completed"
}

restart_containers() {
  system_log "[+] Restarting all Smokeping containers..."
  docker ps -a --filter "label=role=smokeping-master" --format '{{.Names}}' | xargs -r docker restart
  docker ps -a --filter "label=role=smokeping-slave" --format '{{.Names}}' | xargs -r docker restart
  system_log "[+] Restart command issued to all matching containers"
}

cleanup_log_processes() {
  if [[ -f /tmp/smokeping_log_pids.tmp ]]; then
    while IFS= read -r pid; do
      if kill -0 "$pid" >/dev/null 2>&1; then
        kill "$pid" >/dev/null 2>&1 || true
      fi
    done < /tmp/smokeping_log_pids.tmp
    rm -f /tmp/smokeping_log_pids.tmp
  fi
}

purge_all() {
  echo -e "${COLORS[BRIGHT_RED]}[!] WARNING: This will remove ALL Smokeping containers, configs, and data permanently!${COLORS[RESET]}"
  read -p "Are you sure you want to continue? (y/N): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    system_log "[!] Purge aborted by user"
    return
  fi

  system_log "[+] Performing full cleanup of all Smokeping containers, configs, data, and networks..."

  cleanup_log_processes

  # Kill any container running the smokeping image (regardless of name/label)
  docker ps -a --filter "ancestor=$IMAGE" --format '{{.ID}}' | xargs -r docker rm -f

  # Remove custom network if it exists
  docker network rm "$NETWORK_NAME" 2>/dev/null || true

  # Optionally prune dangling networks to release reserved IPs
  docker network prune -f >/dev/null 2>&1 || true

  # Remove config + data base directory completely
  if [[ -d "$CONFIG_BASE" ]]; then
    rm -rf "$CONFIG_BASE"
    system_log "[+] Removed full directory $CONFIG_BASE (configs + data)"
  fi

  system_log "[+] Full cleanup completed"
}


show_color_legend() {
  echo ""
  colored_echo "${COLORS[BOLD]}" "=== COLOR LEGEND ==="
  colored_echo "${CONTAINER_COLORS[MASTER]}" "■ MASTER - Main smokeping server (port 80 accessible)"
  
  # Show colors for defined slaves
  for i in {1..5}; do
    local color_key="SLAVE${i}"
    local color="${CONTAINER_COLORS[$color_key]}"
    colored_echo "$color" "■ SLAVE$i - Slave container $i (port 80 blocked)"
  done
  
  # Show fallback colors if more than 5 slaves
  if [[ -n "$SLAVE_COUNT" ]] && [[ "$SLAVE_COUNT" -gt 5 ]]; then
    for i in $(seq 6 "$SLAVE_COUNT"); do
      local color_index=$(( (i - 6) % ${#FALLBACK_COLORS[@]} ))
      local color="${FALLBACK_COLORS[$color_index]}"
      colored_echo "$color" "■ SLAVE$i - Slave container $i (port 80 blocked)"
    done
  fi
  
  colored_echo "${CONTAINER_COLORS[MONITOR]}" "■ MONITOR - System monitoring messages"
  colored_echo "${CONTAINER_COLORS[SYSTEM]}" "■ SYSTEM - Deployment and system messages"
  echo ""
}

sanitize_name() {
  local raw="$1"
  local safe="${raw// /_}"
  safe=$(echo "$safe" | sed 's/[^a-zA-Z0-9_.-]//g')
  if [[ -z "$safe" ]]; then
    safe="SLAVE$(date +%s)"
  fi
  echo "$safe"
}

# Trap to cleanup background processes on script exit
trap cleanup_log_processes EXIT INT TERM

# --- MAIN --- #
case "$1" in
  start)
 # Initialize log PID tracking file
  > /tmp/smokeping_log_pids.tmp

  echo "Available physical interfaces:"
  ip -o link show | awk -F': ' '{print " - "$2}' | grep -v "lo"

  DOCKER_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)

  echo ""
  read -p "Enter the parent interface to use [default: ${DOCKER_IFACE}]: " USER_IFACE
  if [[ -z "$USER_IFACE" ]]; then
    PARENT_IFACE="$DOCKER_IFACE"
  else
    PARENT_IFACE="$USER_IFACE"
  fi

  # validate interface
  if ! ip link show "$PARENT_IFACE" >/dev/null 2>&1; then
    echo "[!] ERROR: Interface '$PARENT_IFACE' not found. Aborting."
    exit 1
  fi

  echo "[+] Using parent interface: $PARENT_IFACE"

  # --- ASK MASTER IP OFFSET --- #
  read -p "Enter the last octet for Master IP [default: ${MASTER_IP_OFFSET}]: " USER_MASTER_IP
  if [[ -n "$USER_MASTER_IP" ]]; then
    MASTER_IP_OFFSET="$USER_MASTER_IP"
  fi

  # --- AUTO MASTER IP BASED ON SUBNET --- #
  SUBNET_BASE=$(ip -o -f inet addr show "$PARENT_IFACE" | awk '{print $4}' | cut -d/ -f1 | cut -d. -f1-3)
  MASTER_IP="${SUBNET_BASE}.${MASTER_IP_OFFSET}"
  MASTER_URL="http://${MASTER_IP}/smokeping/smokeping.cgi"

  echo "[+] Master URL automatically set to: $MASTER_URL"

  # --- RANDOMIZE SECRET --- #
  SHARED_SECRET=$(openssl rand -base64 16)
  echo "[+] Generated random shared secret: $SHARED_SECRET"

    read -p "How many slave containers to create? " SLAVE_COUNT
    
    # Ask user for custom names
    SLAVE_NAMES=()
    for i in $(seq 1 "$SLAVE_COUNT"); do
      read -p "Enter name for Slave $i [default: Slave$i]: " sname
      if [[ -z "$sname" ]]; then
        sname="Slave$i"
      fi
      safe_name=$(sanitize_name "$sname")
      echo "[*] Using sanitized name: $safe_name"
      SLAVE_NAMES+=("$safe_name")
    done

    echo "[+] Starting deployment of 1 master + $SLAVE_COUNT slaves"
    stop_all
    remove_all
    create_macvlan_network
    ensure_network_exists
    deploy_master
    sleep 5
    deploy_slaves
    
    if $DEBUG; then
      show_color_legend
      echo ""
      colored_echo "${COLORS[BOLD]}" "=== DEBUG MODE ACTIVE ==="
      system_log "[+] Monitoring logs from all containers (CTRL+C to stop monitoring)"
      system_log "[+] Log format: [timestamp] [TYPE:container_name:ip_address] log_message"
      colored_echo "${CONTAINER_COLORS[MONITOR]}" "[+] Monitor messages: [timestamp] [MONITOR:container_name:ip_address] status_message"
      colored_echo "${COLORS[BOLD]}" "======================="
      echo ""
      
      # Keep the script running and monitor log processes
      system_log "[+] Press CTRL+C to stop monitoring and exit"
      
      # Wait indefinitely, allowing background log processes to run
      while true; do
        sleep 10
        
        # Check if any containers are still running
        running_containers=$(docker ps --filter "name=$SLAVE_BASE" --filter "name=$MASTER_NAME" --format '{{.Names}}' | wc -l)
        if [[ $running_containers -eq 0 ]]; then
          echo ""
          colored_echo "${COLORS[RED]}" "[!] All containers have stopped. Exiting monitoring mode."
          break
        fi
      done
    else
      echo ""
      system_log "[+] Deployment completed successfully!"
      system_log "[+] Master available at: $MASTER_URL"
      system_log "[+] Slaves deployed without port 80 access for security"
      system_log "[+] Use './install-containers.sh start --debug' to monitor container logs"
      docker ps
    fi
    ;;
  stop)
    stop_all
    ;;
  remove)
    stop_all
    remove_all
    ;;
  reload)
    reload_all
    ;;
  restart)
    restart_containers
    ;;
  purge)
    purge_all
    ;;
  *)    
    system_log "Usage: $0 {start|stop|remove|reload|restart} [--debug]"
    echo ""
    system_log "Options:"
    system_log "  start         Deploy master and slave containers"
    system_log "  start --debug Deploy with real-time log monitoring (colored output)"
    system_log "  stop          Stop all containers"
    system_log "  remove        Stop and remove all containers and network"
    system_log "  reload        Send reload signal to all running containers"
    system_log "  restart       Stop and then start all containers"
    echo ""
    system_log "Security:"
    system_log "  - Master container has port 80 exposed for web interface"
    system_log "  - Slave containers have NO port 80 access (blocked by default)"
    system_log "  - Optional iptables rules for additional security"
    ;;
esac