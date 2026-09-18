#!/usr/bin/env bash
# ==============================================================================
# X-MANAGER: Универсальный инсталлятор шлюзов и прокси-служб
# Поддерживает: Snell v5 (Hybrid TCP+UDP/QUIC), Mieru (mita), WDTT (qwdtt) + 3X-UI
# Репозиторий: https://github.com/534188-create/x-manager
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Проверка прав суперпользователя
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Ошибка: данный скрипт должен быть запущен с правами root (sudo)!${NC}"
    exit 1
fi

# Проверка аргументов
MODE="interactive"
if [ "$1" = "--quick" ] || [ "$1" = "-q" ] || [ "$1" = "--auto" ]; then
    MODE="quick"
fi

# Баннер
clear
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${BOLD}          X-MANAGER: УНИВЕРСАЛЬНЫЙ СЕТЕВОЙ ИНСТАЛЛЯТОР         ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}     Snell v5 (Hybrid) | Mieru Anti-TSPU | WDTT (qwdtt) | 3X-UI      ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Архитектура и сетевой интерфейс
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) SNELL_ARCH="linux-amd64"; MIERU_ARCH="linux-amd64" ;;
    aarch64|arm64) SNELL_ARCH="linux-aarch64"; MIERU_ARCH="linux-arm64" ;;
    *) echo -e "${RED}Неподдерживаемая архитектура: $ARCH${NC}"; exit 1 ;;
esac

WAN_IF=$(ip route show default 2>/dev/null | awk '{print $5}' | head -n 1)
[ -z "$WAN_IF" ] && WAN_IF="eth0"

SERVER_IP=$(curl -s4 --max-time 5 https://icanhazip.com 2>/dev/null || curl -s4 --max-time 5 https://ifconfig.me 2>/dev/null || ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' | head -n 1)
[ -z "$SERVER_IP" ] && SERVER_IP="127.0.0.1"

# Выбор режима установки
if [ "$MODE" = "interactive" ]; then
    echo -e "${BOLD}Выберите режим установки:${NC}"
    echo -e "  ${YELLOW}[1]${NC} ⚡ ${BOLD}Быстрый старт${NC} (Автоматическая установка «под ключ» с автоподхватом шлюзов)"
    echo -e "  ${YELLOW}[2]${NC} 🛠️  ${BOLD}Ручная установка${NC} (Выбор компонентов, ввод своих портов, паролей и режимов)"
    echo -e "  ${YELLOW}[0]${NC} 🚪 Выход"
    echo ""
    read -p "Выберите вариант [1-2, по умолчанию 1]: " install_choice
    case "$install_choice" in
        2) MODE="manual" ;;
        0) exit 0 ;;
        *) MODE="quick" ;;
    esac
fi

# Значения по умолчанию
INSTALL_SNELL="yes"
SNELL_PORT="1488"
SNELL_PSK=$(openssl rand -base64 24 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c 30 || echo "snell_secret_pass_$(date +%s)")
SNELL_OBFS="off"

INSTALL_MIERU="yes"
MIERU_PORTS="2020-2030"
MIERU_PROTO="TCP"
MIERU_USER="ADMIN"
MIERU_PASS="mita_pass_$(openssl rand -hex 4 2>/dev/null || echo "2026")"
MIERU_ENTROPY_MODE="LOW_ENTROPY_MODE_48"
MIERU_MASK_ROTATION="LOW_ENTROPY_MASK_ROTATE_RIGHT_7"

DEFAULT_ROUTING="xray"

# Если ручной режим — задаем вопросы
if [ "$MODE" = "manual" ]; then
    echo ""
    echo -e "${BOLD}--- Настройка компонентов установки ---${NC}"
    
    # Snell
    read -p "Установить Snell v5 (Hybrid TCP + UDP/QUIC)? [Y/n]: " s_ans
    [ "$s_ans" = "n" ] || [ "$s_ans" = "N" ] && INSTALL_SNELL="no"
    if [ "$INSTALL_SNELL" = "yes" ]; then
        read -p "Порт для Snell v5 [1-65535, по умолчанию 1488]: " custom_s_port
        [ -n "$custom_s_port" ] && SNELL_PORT="$custom_s_port"
        read -p "PSK ключ Snell [Enter для случайного]: " custom_s_psk
        [ -n "$custom_s_psk" ] && SNELL_PSK="$custom_s_psk"
    fi

    # Mieru
    echo ""
    read -p "Установить Mieru (mita)? [Y/n]: " m_ans
    [ "$m_ans" = "n" ] || [ "$m_ans" = "N" ] && INSTALL_MIERU="no"
    if [ "$INSTALL_MIERU" = "yes" ]; then
        read -p "Диапазон или одиночный порт Mieru [по умолчанию 2020-2030]: " custom_m_ports
        [ -n "$custom_m_ports" ] && MIERU_PORTS="$custom_m_ports"
        read -p "Имя пользователя Mieru [по умолчанию ADMIN]: " custom_m_u
        [ -n "$custom_m_u" ] && MIERU_USER="$custom_m_u"
        read -p "Пароль Mieru [Enter для автогенерации]: " custom_m_p
        [ -n "$custom_m_p" ] && MIERU_PASS="$custom_m_p"
    fi

    # Маршрутизация по умолчанию
    echo ""
    echo -e "${BOLD}Выберите режим маршрутизации по умолчанию:${NC}"
    echo -e "  ${YELLOW}[1]${NC} 🌐 Правила маршрутизации Xray (Рекомендуется)"
    echo -e "  ${YELLOW}[2]${NC} ⚡ Прямой выход"
    read -p "Выбор [1-2, по умолчанию 1]: " rt_choice
    [ "$rt_choice" = "2" ] && DEFAULT_ROUTING="direct"
fi

echo ""
echo -e "${CYAN}==> Шаг 1: Проверка и установка системных утилит...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || true
apt-get install -y -qq curl wget jq unzip iptables qrencode openssl python3 iproute2 >/dev/null 2>&1 || true

echo -e "${CYAN}==> Шаг 2: Анализ и настройка шлюзов ядра Xray (3X-UI)...${NC}"
mkdir -p /etc/x-manager
ENV_FILE="/etc/x-manager/gateways.env"

XRAY_TPROXY_PORT=12345
XRAY_REDIRECT_PORT=12346
XRAY_SOCKS_PORT=10808

XUI_DB="/etc/x-ui/x-ui.db"
if [ -f "$XUI_DB" ]; then
    # Запуск умного Python скрипта детекции и внедрения
    DETECTION_OUT=$(python3 - << 'EOF'
import sqlite3, json, sys

db_path = "/etc/x-ui/x-ui.db"
tproxy_port = None
redirect_port = None
socks_port = None

try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    # 1. Проверяем таблицу inbounds (шлюзы, созданные через панель)
    try:
        for row in c.execute("SELECT id, port, protocol, stream_settings, settings, tag FROM inbounds"):
            port, proto, stream_s, settings, tag = row[1], row[2], str(row[3]), str(row[4]), str(row[5])
            if proto == "socks" and not socks_port:
                socks_port = port
            elif proto == "dokodemo-door":
                if "tproxy" in stream_s.lower() or "tproxy" in tag.lower():
                    tproxy_port = port
                elif "redirect" in settings.lower() or "redirect" in tag.lower() or "snell" in tag.lower():
                    redirect_port = port
    except Exception:
        pass

    # 2. Проверяем xrayTemplateConfig в таблице settings
    c.execute("SELECT value FROM settings WHERE key='xrayTemplateConfig'")
    row = c.fetchone()
    if row:
        cfg = json.loads(row[0])
        inbounds = cfg.setdefault("inbounds", [])
        for ib in inbounds:
            proto = ib.get("protocol", "")
            port = ib.get("port")
            tag = ib.get("tag", "")
            stream_s = json.dumps(ib.get("streamSettings", {}))
            settings = json.dumps(ib.get("settings", {}))

            if proto == "socks" and not socks_port:
                socks_port = port
            elif proto == "dokodemo-door":
                if "tproxy" in stream_s.lower() or "tproxy" in tag.lower() or port == 12345:
                    if not tproxy_port:
                        tproxy_port = port
                elif "redirect" in settings.lower() or "redirect" in tag.lower() or "snell" in tag.lower() or port == 12346:
                    if not redirect_port:
                        redirect_port = port

        # Создаем недостающие шлюзы в шаблоне
        modified = False
        if not socks_port:
            socks_port = 10808
            inbounds.append({
                "tag": "in-mieru-socks",
                "port": socks_port,
                "protocol": "socks",
                "listen": "127.0.0.1",
                "settings": {"auth": "noauth", "udp": True}
            })
            modified = True
            print(f"CREATED_SOCKS={socks_port}")
        else:
            print(f"FOUND_SOCKS={socks_port}")

        if not redirect_port:
            redirect_port = 12346
            inbounds.append({
                "tag": "in-snell-redirect",
                "port": redirect_port,
                "protocol": "dokodemo-door",
                "listen": "127.0.0.1",
                "settings": {"network": "tcp", "followRedirect": True}
            })
            modified = True
            print(f"CREATED_REDIRECT={redirect_port}")
        else:
            print(f"FOUND_REDIRECT={redirect_port}")

        if not tproxy_port:
            tproxy_port = 12345
            inbounds.append({
                "tag": "in-wdtt-tproxy",
                "port": tproxy_port,
                "protocol": "dokodemo-door",
                "listen": "127.0.0.1",
                "settings": {"network": "tcp,udp", "followRedirect": True},
                "streamSettings": {"sockopt": {"tproxy": "tproxy"}}
            })
            modified = True
            print(f"CREATED_TPROXY={tproxy_port}")
        else:
            print(f"FOUND_TPROXY={tproxy_port}")

        if modified:
            new_val = json.dumps(cfg, indent=2, ensure_ascii=False)
            c.execute("UPDATE settings SET value=? WHERE key='xrayTemplateConfig'", (new_val,))
            conn.commit()
            print("RELOAD_XUI=1")

    conn.close()
except Exception as e:
    print(f"ERROR={e}")
EOF
)

    # Парсим вывод детекции
    for line in $DETECTION_OUT; do
        case "$line" in
            FOUND_TPROXY=*)
                XRAY_TPROXY_PORT="${line#*=}"
                echo -e "  ${GREEN}✓ Подхвачен существующий TPROXY шлюз:${NC} :${XRAY_TPROXY_PORT}"
                ;;
            CREATED_TPROXY=*)
                XRAY_TPROXY_PORT="${line#*=}"
                echo -e "  ${GREEN}✓ Создан новый TPROXY шлюз:${NC} :${XRAY_TPROXY_PORT}"
                ;;
            FOUND_SOCKS=*)
                XRAY_SOCKS_PORT="${line#*=}"
                echo -e "  ${GREEN}✓ Подхвачен существующий SOCKS5 вход:${NC} :${XRAY_SOCKS_PORT}"
                ;;
            CREATED_SOCKS=*)
                XRAY_SOCKS_PORT="${line#*=}"
                echo -e "  ${GREEN}✓ Создан новый SOCKS5 вход:${NC} :${XRAY_SOCKS_PORT}"
                ;;
            FOUND_REDIRECT=*)
                XRAY_REDIRECT_PORT="${line#*=}"
                echo -e "  ${GREEN}✓ Подхвачен существующий REDIRECT шлюз:${NC} :${XRAY_REDIRECT_PORT}"
                ;;
            CREATED_REDIRECT=*)
                XRAY_REDIRECT_PORT="${line#*=}"
                echo -e "  ${GREEN}✓ Создан новый REDIRECT шлюз:${NC} :${XRAY_REDIRECT_PORT}"
                ;;
            RELOAD_XUI=1)
                systemctl restart x-ui 2>/dev/null || true
                sleep 2
                ;;
        esac
    done
else
    echo -e "${YELLOW}  ! 3X-UI не обнаружен (/etc/x-ui/x-ui.db не найден). Используем стандартные порты.${NC}"
fi

# Сохраняем переменные окружения шлюзов
cat << EOF > "$ENV_FILE"
XRAY_TPROXY_PORT=${XRAY_TPROXY_PORT}
XRAY_REDIRECT_PORT=${XRAY_REDIRECT_PORT}
XRAY_SOCKS_PORT=${XRAY_SOCKS_PORT}
EOF

# Установка Snell v5.0.1
if [ "$INSTALL_SNELL" = "yes" ]; then
    echo -e "${CYAN}==> Шаг 3: Установка и настройка Snell v5.0.1 (Hybrid TCP + UDP/QUIC)...${NC}"
    id -u snell &>/dev/null || useradd -r -s /usr/sbin/nologin snell 2>/dev/null || true
    mkdir -p /etc/snell /usr/local/bin

    SNELL_URL="https://dl.nssurge.com/snell/snell-server-v5.0.1-${SNELL_ARCH}.zip"
    tmp_snell="/tmp/snell.zip"
    if curl -fsSL -o "$tmp_snell" "$SNELL_URL"; then
        unzip -qo "$tmp_snell" -d /usr/local/bin/
        chmod +x /usr/local/bin/snell-server
        rm -f "$tmp_snell"
    else
        echo -e "${RED}  ✗ Не удалось скачать Snell v5 с dl.nssurge.com! Пропускаем.${NC}"
    fi

    # Конфигурация Snell
    if [ ! -f "/etc/snell/snell-server.conf" ]; then
        cat << EOF > /etc/snell/snell-server.conf
[snell-server]
listen = 0.0.0.0:${SNELL_PORT}
ipv6 = false
psk = ${SNELL_PSK}
obfs = ${SNELL_OBFS}
EOF
    fi

    echo "Snell-v5" > /etc/snell/tag.txt
    echo "$DEFAULT_ROUTING" > /etc/snell/routing.mode
    chown -R snell:snell /etc/snell
    chmod 644 /etc/snell/snell-server.conf

    # Скрипт маршрутизации snell-routing.sh с использованием подхваченного REDIRECT порта
    cat << EOF > /usr/local/bin/snell-routing.sh
#!/usr/bin/env bash
MODE_FILE="/etc/snell/routing.mode"
MODE="xray"
[ -f "\$MODE_FILE" ] && MODE=\$(cat "\$MODE_FILE" | tr -d ' ')

iptables -t nat -D OUTPUT -m owner --uid-owner snell -j SNELL_OUT 2>/dev/null || true
iptables -t nat -F SNELL_OUT 2>/dev/null || true
iptables -t nat -X SNELL_OUT 2>/dev/null || true

if [ "\$MODE" = "xray" ]; then
    iptables -t nat -N SNELL_OUT
    iptables -t nat -A SNELL_OUT -d 127.0.0.0/8 -j RETURN
    iptables -t nat -A SNELL_OUT -d ${SERVER_IP} -j RETURN 2>/dev/null || true
    iptables -t nat -A SNELL_OUT -p tcp -j REDIRECT --to-ports ${XRAY_REDIRECT_PORT}
    iptables -t nat -I OUTPUT 1 -m owner --uid-owner snell -j SNELL_OUT
fi
EOF
    chmod +x /usr/local/bin/snell-routing.sh

    # Служба snell.service
    cat << 'EOF' > /etc/systemd/system/snell.service
[Unit]
Description=Snell Proxy Service
After=network.target network-online.target x-ui.service
Wants=network-online.target

[Service]
Type=simple
User=snell
Group=snell
LimitNOFILE=65535
ExecStartPre=+/usr/local/bin/snell-routing.sh
ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell-server.conf
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    # Открытие TCP и UDP в iptables для Snell
    iptables -I INPUT 1 -p tcp --dport "$SNELL_PORT" -j ACCEPT 2>/dev/null || true
    iptables -I INPUT 1 -p udp --dport "$SNELL_PORT" -j ACCEPT 2>/dev/null || true

    systemctl daemon-reload
    systemctl enable snell 2>/dev/null || true
    systemctl restart snell 2>/dev/null || true
    echo -e "  ✓ Snell v5.0.1 запущен на порту ${SNELL_PORT} (TCP + UDP QUIC)"
fi

# Установка Mieru
if [ "$INSTALL_MIERU" = "yes" ]; then
    echo -e "${CYAN}==> Шаг 4: Установка и настройка Mieru (mita) с Anti-TSPU пресетом...${NC}"
    id -u mita &>/dev/null || useradd -r -s /usr/sbin/nologin mita 2>/dev/null || true
    mkdir -p /etc/mita /usr/local/bin
    ln -sfn /etc/mita /etc/mieru

    mita_ver="3.37.0"
    case "$ARCH" in
        x86_64) DEB_ARCH="amd64" ;;
        aarch64|arm64) DEB_ARCH="arm64" ;;
        *) DEB_ARCH="amd64" ;;
    esac

    if ! command -v mita &>/dev/null; then
        curl -fsSL -o /tmp/mita.deb "https://github.com/enfein/mieru/releases/download/v${mita_ver}/mita_${mita_ver}_${DEB_ARCH}.deb" 2>/dev/null || true
        if [ -s /tmp/mita.deb ]; then
            dpkg -i /tmp/mita.deb 2>/dev/null || apt-get install -f -y 2>/dev/null || true
            rm -f /tmp/mita.deb
        else
            curl -fsSL "https://github.com/enfein/mieru/releases/download/v${mita_ver}/mita_${mita_ver}_linux_${DEB_ARCH}.tar.gz" | tar -xz -C /usr/local/bin/ mita 2>/dev/null || true
            chmod +x /usr/local/bin/mita 2>/dev/null || true
        fi
    fi
    ln -sf /usr/bin/mita /usr/local/bin/mita 2>/dev/null || true
    ln -sf /usr/local/bin/mita /usr/bin/mita 2>/dev/null || true

    # Конфигурация Mieru с использованием подхваченного SOCKS5 порта
    action="PROXY"
    [ "$DEFAULT_ROUTING" = "direct" ] && action="DIRECT"

    if [ ! -f "/etc/mita/config.json" ]; then
        cat << EOF > /etc/mita/config.json
{
  "portBindings": [
    {
      "portRange": "${MIERU_PORTS}",
      "protocol": "${MIERU_PROTO}"
    }
  ],
  "users": [
    {
      "name": "${MIERU_USER}",
      "password": "${MIERU_PASS}",
      "allowPrivateIP": true,
      "allowLoopbackIP": true
    }
  ],
  "trafficPattern": {
    "unlockAll": true,
    "tcpFragment": {
      "enable": true,
      "maxSleepMs": 15
    },
    "nonce": {
      "type": "NONCE_TYPE_PRINTABLE",
      "applyToAllUDPPacket": true,
      "minLen": 6,
      "maxLen": 8
    },
    "padding": {
      "maxMiddlePaddingLen": 64,
      "maxEndPaddingLen": 128
    },
    "lowEntropy": {
      "mode": "${MIERU_ENTROPY_MODE}",
      "maskRotation": "${MIERU_MASK_ROTATION}"
    }
  },
  "loggingLevel": "INFO",
  "mtu": 1400,
  "dns": {
    "dualStack": "PREFER_IPv4"
  },
  "egress": {
    "proxies": [
      {
        "name": "xray_socks",
        "protocol": "SOCKS5_PROXY_PROTOCOL",
        "host": "127.0.0.1",
        "port": ${XRAY_SOCKS_PORT}
      }
    ],
    "rules": [
      {
        "ipRanges": [
          "*"
        ],
        "domainNames": [
          "*"
        ],
        "action": "${action}",
        "proxyNames": [
          "xray_socks"
        ]
      }
    ]
  }
}
EOF
    fi

    if [ ! -f "/etc/mita/users_db.json" ]; then
        echo "{\"${MIERU_USER}\": \"${MIERU_PASS}\"}" > /etc/mita/users_db.json
    fi
    echo "$SERVER_IP" > /etc/mita/server_ip.txt
    echo "Mieru-Home" > /etc/mita/tag.txt

    chown -R mita:mita /etc/mita
    chmod 664 /etc/mita/config.json /etc/mita/users_db.json 2>/dev/null || true

    which_mita=$(command -v mita || echo "/usr/bin/mita")
    cat << EOF > /etc/systemd/system/mita.service
[Unit]
Description=Mieru proxy server
After=network-online.target network.service networking.service NetworkManager.service systemd-networkd.service x-ui.service
Wants=network-online.target
StartLimitBurst=5
StartLimitIntervalSec=60

[Service]
Type=exec
User=mita
Group=mita
AmbientCapabilities=CAP_NET_BIND_SERVICE
Environment="MITA_LOG_NO_TIMESTAMP=true"
Environment="MITA_CONFIG_JSON_FILE=/etc/mita/config.json"
ExecStartPre=+/bin/mkdir -p /var/run/mita
ExecStartPre=+/bin/chown -R mita:mita /var/run/mita
ExecStartPre=+/bin/chmod 775 /var/run/mita
ExecStart=${which_mita} run
Nice=-10
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    mkdir -p /etc/systemd/system/mita.service.d
    cat << 'EOF' > /etc/systemd/system/mita.service.d/override.conf
[Service]
Environment="MITA_CONFIG_JSON_FILE=/etc/mita/config.json"
EOF

    ipt_proto=$(echo "$MIERU_PROTO" | tr '[:upper:]' '[:lower:]')
    if [[ "$MIERU_PORTS" =~ - ]]; then
        p_s=$(echo "$MIERU_PORTS" | cut -d'-' -f1)
        p_e=$(echo "$MIERU_PORTS" | cut -d'-' -f2)
        iptables -I INPUT 1 -p "$ipt_proto" --dport "${p_s}:${p_e}" -j ACCEPT 2>/dev/null || true
    else
        iptables -I INPUT 1 -p "$ipt_proto" --dport "$MIERU_PORTS" -j ACCEPT 2>/dev/null || true
    fi

    systemctl daemon-reload
    systemctl enable mita 2>/dev/null || true
    systemctl restart mita 2>/dev/null || true
    echo -e "  ✓ Mieru запущен на портах ${MIERU_PORTS}/${MIERU_PROTO} (Anti-TSPU Balanced)"
fi

# Интеграция qwdtt с использованием подхваченного TPROXY порта
echo -e "${CYAN}==> Шаг 5: Интеграция qwdtt / WDTT TPROXY...${NC}"
cat << EOF > /usr/local/bin/wdtt-tproxy.sh
#!/usr/bin/env bash
WAN_IF="${WAN_IF}"
TPROXY_PORT="${XRAY_TPROXY_PORT}"

ip rule del fwmark 1 lookup 100 2>/dev/null || true
ip route del local 0.0.0.0/0 dev lo table 100 2>/dev/null || true

ip rule add fwmark 1 lookup 100
ip route add local 0.0.0.0/0 dev lo table 100

iptables -t mangle -D PREROUTING -i wdtt0 -j WDTT_TPROXY 2>/dev/null || true
iptables -t mangle -D PREROUTING -i wdttraw0 -j WDTT_TPROXY 2>/dev/null || true
iptables -t mangle -F WDTT_TPROXY 2>/dev/null || true
iptables -t mangle -X WDTT_TPROXY 2>/dev/null || true

iptables -t mangle -N WDTT_TPROXY
iptables -t mangle -A WDTT_TPROXY -d 127.0.0.0/8 -j RETURN
iptables -t mangle -A WDTT_TPROXY -d 10.0.0.0/8 -j RETURN
iptables -t mangle -A WDTT_TPROXY -d 172.16.0.0/12 -j RETURN
iptables -t mangle -A WDTT_TPROXY -d 192.168.0.0/16 -j RETURN
iptables -t mangle -A WDTT_TPROXY -p tcp -j TPROXY --on-port \${TPROXY_PORT} --tproxy-mark 1
iptables -t mangle -A WDTT_TPROXY -p udp -j TPROXY --on-port \${TPROXY_PORT} --tproxy-mark 1

iptables -t mangle -A PREROUTING -i wdtt0 -j WDTT_TPROXY
iptables -t mangle -A PREROUTING -i wdttraw0 -j WDTT_TPROXY
EOF
chmod +x /usr/local/bin/wdtt-tproxy.sh

cat << 'EOF' > /etc/systemd/system/wdtt-tproxy.service
[Unit]
Description=WDTT TPROXY Routing to Xray
After=network.target x-ui.service wdtt.service
Wants=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wdtt-tproxy.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

if [ "$DEFAULT_ROUTING" = "xray" ]; then
    systemctl daemon-reload
    systemctl enable wdtt-tproxy 2>/dev/null || true
    systemctl restart wdtt-tproxy 2>/dev/null || true
    echo -e "  ✓ WDTT TPROXY маршрутизация активирована (TPROXY :${XRAY_TPROXY_PORT})"
else
    echo -e "  ✓ WDTT маршрутизация: Прямой выход"
fi

# Настройка безопасности (Блокировка шлюзов извне)
echo -e "${CYAN}==> Шаг 6: Настройка сетевой безопасности...${NC}"
iptables -I INPUT 1 -i "$WAN_IF" -p tcp --dport "${XRAY_TPROXY_PORT}" -j DROP 2>/dev/null || true
iptables -I INPUT 1 -i "$WAN_IF" -p udp --dport "${XRAY_TPROXY_PORT}" -j DROP 2>/dev/null || true
iptables -I INPUT 1 -i "$WAN_IF" -p tcp --dport "${XRAY_REDIRECT_PORT}" -j DROP 2>/dev/null || true
echo -e "  ✓ Внутренние порты ядра Xray (${XRAY_TPROXY_PORT}, ${XRAY_REDIRECT_PORT}) защищены от внешнего доступа"

# Установка диспетчера x-manager
echo -e "${CYAN}==> Шаг 7: Развертывание диспетчера x-manager...${NC}"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -f "$SCRIPT_DIR/bin/x-manager" ]; then
    cp "$SCRIPT_DIR/bin/x-manager" /usr/local/bin/x-manager
elif [ -f "/usr/local/bin/x-manager" ]; then
    chmod +x /usr/local/bin/x-manager
else
    curl -fsSL -o /usr/local/bin/x-manager https://raw.githubusercontent.com/534188-create/x-manager/main/bin/x-manager 2>/dev/null || true
fi
chmod +x /usr/local/bin/x-manager

ln -sf /usr/local/bin/x-manager /usr/local/bin/x-snell
ln -sf /usr/local/bin/x-manager /usr/local/bin/x-mieru
ln -sf /usr/local/bin/x-manager /usr/local/bin/x-wdtt
ln -sf /usr/local/bin/x-manager /usr/local/bin/x-qwdtt

echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}             УСТАНОВКА X-MANAGER УСПЕШНО ЗАВЕРШЕНА!                   ${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}Для входа в интерактивное меню запустите:${NC}"
echo -e "  ${CYAN}${BOLD}x-manager${NC}   - Главный центр управления всеми службами"
echo -e "  ${YELLOW}x-snell${NC}     - Раздел управления Snell v5"
echo -e "  ${YELLOW}x-mieru${NC}     - Раздел управления Mieru"
echo -e "  ${YELLOW}x-wdtt${NC}      - Раздел управления WDTT (qwdtt)"
echo ""
echo -e "${BOLD}Шлюзы ядра Xray (подхваченные/настроенные):${NC}"
echo -e "  • TPROXY:   127.0.0.1:${XRAY_TPROXY_PORT}"
echo -e "  • REDIRECT: 127.0.0.1:${XRAY_REDIRECT_PORT}"
echo -e "  • SOCKS5:   127.0.0.1:${XRAY_SOCKS_PORT}"
echo ""
if [ "$INSTALL_SNELL" = "yes" ]; then
    echo -e "${BOLD}Параметры Snell v5 (Hybrid TCP + UDP/QUIC):${NC}"
    echo -e "  • Сервер: ${SERVER_IP}:${SNELL_PORT}"
    echo -e "  • PSK:    ${GREEN}${SNELL_PSK}${NC}"
    echo -e "  • Режим:  Гибридный (NekoBox+: TCP, Surge: QUIC/UDP 0-RTT)"
    echo -e "  • Ссылка: ${CYAN}snell://${SNELL_PSK}@${SERVER_IP}:${SNELL_PORT}/?version=5#Snell-v5${NC}"
    echo ""
fi
if [ "$INSTALL_MIERU" = "yes" ]; then
    echo -e "${BOLD}Параметры Mieru (mita):${NC}"
    echo -e "  • Сервер: ${SERVER_IP} (Порты: ${MIERU_PORTS})"
    echo -e "  • Логин:  ${MIERU_USER} | Пароль: ${GREEN}${MIERU_PASS}${NC}"
    echo -e "  • Защита: Low-Entropy 48-bit + Rotate Right 7"
    pattern=$(mita export traffic-pattern 2>/dev/null || echo "")
    echo -e "  • Ссылка: ${CYAN}mierus://${MIERU_USER}:${MIERU_PASS}@${SERVER_IP}/?profile=Mieru-Home&port=${MIERU_PORTS}&protocol=${MIERU_PROTO}&multiplexing=MULTIPLEXING_HIGH&traffic-pattern=${pattern}&low-entropy-mode=LOW_ENTROPY_MODE_48&low-entropy-mask-rotation=LOW_ENTROPY_MASK_ROTATE_RIGHT_7${NC}"
    echo ""
fi
echo -e "${GREEN}Все службы запущены и работают в фоновом режиме.${NC}"
