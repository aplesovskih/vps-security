#!/usr/bin/env bash
# =============================================================================
# Скрипт настройки безопасности VPS для Debian
# Интерактивная настройка с откатом и логированием
# Версия: 2.0.0
# =============================================================================

set -euo pipefail

# --------------------------------------
# Константы
# --------------------------------------
readonly VERSION="2.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_URL="https://raw.githubusercontent.com/aplesovskih/vps-security/main/vps-security.sh"
readonly ORIGINAL_SSH_PORT=22

# Цвета
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Режим
DRY_RUN=false

# --------------------------------------
# Определение путей (отложенные)
# --------------------------------------
LOG_FILE=""
BACKUP_DIR=""

init_paths() {
    LOG_FILE="/var/log/vps-security-$(date +%Y%m%d_%H%M%S).log"
    BACKUP_DIR="/root/vps-security-backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    mkdir -p "$BACKUP_DIR"
    log "INFO" "Скрипт запущен. PID=$$ Пользователь=root Версия=${VERSION}"
}

# --------------------------------------
# Утилиты вывода
# --------------------------------------
log() {
    local level="$1"; shift
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${timestamp}] [${level}] $*" >> "${LOG_FILE}" 2>/dev/null || true
}

info()    { echo -e "${BLUE}[ИНФО]${NC} $*";  log "INFO" "$*"; }
success() { echo -e "${GREEN}[ОК]${NC} $*";    log "OK" "$*"; }
warn()    { echo -e "${YELLOW}[ВНИМ]${NC} $*"; log "WARN" "$*"; }
error()   { echo -e "${RED}[ОШИБКА]${NC} $*";  log "ERROR" "$*"; }

header() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  $*${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    log "INFO" "=== $* ==="
}

divider() { echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"; }

# --------------------------------------
# ASCII-арт для ошибок
# --------------------------------------
show_ascii_error() {
    local module="$1"
    local msg="$2"
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                                                      ║${NC}"
    echo -e "${RED}║  ███████ ███████ ███████ ██████   ██████                             ║${NC}"
    echo -e "${RED}║  ██      ██      ██      ██   ██ ██    ██                            ║${NC}"
    echo -e "${RED}║  █████   █████   █████   ██   ██ ██    ██                            ║${NC}"
    echo -e "${RED}║  ██      ██      ██      ██   ██ ██    ██                            ║${NC}"
    echo -e "${RED}║  ██      ██      ███████ ██████   ██████                             ║${NC}"
    echo -e "${RED}║                                                                      ║${NC}"
    echo -e "${RED}║  Модуль:  ${BOLD}${module}${NC}"
    echo -e "${RED}║  Ошибка:  ${YELLOW}${msg}${NC}"
    echo -e "${RED}║                                                                      ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_ascii_warning() {
    local msg="$1"
    echo ""
    echo -e "${YELLOW}┌──────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│  ⚠  ВНИМАНИЕ                                                       │${NC}"
    echo -e "${YELLOW}│                                                                      │${NC}"
    echo -e "${YELLOW}│  ${BOLD}${msg}${NC}"
    echo -e "${YELLOW}│                                                                      │${NC}"
    echo -e "${YELLOW}└──────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

show_ascii_critical() {
    local msg="$1"
    local hint="${2:-}"
    echo ""
    echo -e "${RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${RED}┃  ╳  КРИТИЧЕСКАЯ ОШИБКА                                             ┃${NC}"
    echo -e "${RED}┃                                                                      ┃${NC}"
    echo -e "${RED}┃  ${BOLD}${msg}${NC}"
    if [[ -n "$hint" ]]; then
        echo -e "${RED}┃                                                                      ┃${NC}"
        echo -e "${RED}┃  ${YELLOW}${hint}${NC}"
    fi
    echo -e "${RED}┃                                                                      ┃${NC}"
    echo -e "${RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo ""
}

show_ascii_success() {
    local msg="$1"
    echo ""
    echo -e "${GREEN}┌──────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${GREEN}│  ✓  УСПЕХ                                                           │${NC}"
    echo -e "${GREEN}│                                                                      │${NC}"
    echo -e "${GREEN}│  ${BOLD}${msg}${NC}"
    echo -e "${GREEN}│                                                                      │${NC}"
    echo -e "${GREEN}└──────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

show_ascii_dryrun() {
    local module="$1"
    local desc="$2"
    local cmd="$3"
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  ◎  ДЕМО-РЕЖИМ (dry-run)                                            ║${NC}"
    echo -e "${CYAN}║                                                                      ║${NC}"
    echo -e "${CYAN}║  Модуль:  ${BOLD}${module}${NC}"
    echo -e "${CYAN}║  Действие: ${desc}${NC}"
    echo -e "${CYAN}║  Команда:  ${YELLOW}${cmd}${NC}"
    echo -e "${CYAN}║                                                                      ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# --------------------------------------
# Обёртка dry-run
# --------------------------------------
dry_run_or_exec() {
    local module="$1"
    local desc="$2"
    local real_cmd="$3"

    if [[ "$DRY_RUN" == "true" ]]; then
        show_ascii_dryrun "$module" "$desc" "$real_cmd"
        log "DRY-RUN" "[${module}] ${desc} -> ${real_cmd}"
        return 0
    fi

    if ! eval "$real_cmd" 2>>"${LOG_FILE}"; then
        return 1
    fi
    return 0
}

# --------------------------------------
# Обработчик ошибок
# --------------------------------------
error_handler() {
    local module="$1"
    local msg="$2"
    local can_skip="${3:-yes}"
    local can_retry="${4:-yes}"

    show_ascii_error "$module" "$msg"
    log "ERROR" "[${module}] ${msg}"

    local options=()
    [[ "$can_retry" == "yes" ]] && options+=("r|Повторить")
    [[ "$can_skip" == "yes" ]]  && options+=("s|Пропустить")
    options+=("m|В главное меню")
    options+=("q|Выход")

    echo -e "${YELLOW}Что сделать?${NC}"
    for opt in "${options[@]}"; do
        local key="${opt%%|*}"
        local desc="${opt#*|}"
        echo -e "  ${CYAN}[${key}]${NC} ${desc}"
    done

    local choice
    while true; do
        read -rp "$(echo -e "${BOLD}Ваш выбор: ${NC}")" choice
        case "${choice,,}" in
            r) return 2 ;;
            s) return 1 ;;
            m) return 0 ;;
            q) exit 0 ;;
            *) echo "  Неверный выбор." ;;
        esac
    done
}

# --------------------------------------
# Безопасное выполнение
# --------------------------------------
safe_exec() {
    local cmd="$1"
    local error_msg="${2:-Команда не выполнилась}"
    local module="${3:-unknown}"

    if ! eval "$cmd" 2>>"${LOG_FILE}"; then
        error_handler "$module" "$error_msg" "yes" "yes"
        return $?
    fi
    return 0
}

# --------------------------------------
# Валидации
# --------------------------------------
validate_username() {
    local username="$1"
    if [[ -z "$username" ]]; then
        error "Имя пользователя не может быть пустым."
        return 1
    fi
    if ! [[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        error "Неверный формат. Допускаются: строчные буквы, цифры, _, -"
        return 1
    fi
    if [[ ${#username} -gt 32 ]]; then
        error "Имя слишком длинное (максимум 32 символа)."
        return 1
    fi
    if id "$username" &>/dev/null; then
        error "Пользователь '${username}' уже существует (UID=$(id -u "$username"))."
        return 1
    fi
    return 0
}

validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        error "Порт должен быть числом."
        return 1
    fi
    if (( port < 1 || port > 65535 )); then
        error "Порт должен быть от 1 до 65535."
        return 1
    fi
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
        local process
        process=$(ss -tlnp 2>/dev/null | grep ":${port} " | awk '{print $NF}' | head -1)
        error "Порт ${port} уже занят: ${process}"
        return 1
    fi
    return 0
}

validate_email() {
    local email="$1"
    if ! [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        error "Неверный формат email."
        return 1
    fi
    return 0
}

check_package() {
    local pkg="$1"
    dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"
}

check_service() {
    local svc="$1"
    systemctl is-active --quiet "$svc" 2>/dev/null
}

# --------------------------------------
# Бэкап и state
# --------------------------------------
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        mkdir -p "${BACKUP_DIR}"
        cp -a "$file" "${BACKUP_DIR}/$(basename "$file").bak"
        success "Резервная копия: ${file}"
        log "BACKUP" "Создана копия ${file}"
    fi
}

save_state() {
    local key="$1" value="$2"
    echo "${key}=${value}" >> "${BACKUP_DIR}/state.txt"
    log "STATE" "${key}=${value}"
}

load_state() {
    local key="$1" default="${2:-}"
    if [[ -f "${BACKUP_DIR}/state.txt" ]]; then
        grep "^${key}=" "${BACKUP_DIR}/state.txt" 2>/dev/null | tail -1 | cut -d'=' -f2-
    else
        echo "$default"
    fi
}

# --------------------------------------
# Общие проверки
# --------------------------------------
confirm() {
    local prompt="$1"
    local default="${2:-y}"
    local yn
    if [[ "$default" == "y" ]]; then
        prompt="${prompt} [Д/н]: "
    else
        prompt="${prompt} [д/Н]: "
    fi
    while true; do
        read -rp "$(echo -e "${YELLOW}${prompt}${NC}")" yn
        case "${yn:-$default}" in
            [ДдYy]*) return 0 ;;
            [НнNn]*) return 1 ;;
            *) echo "  Ответьте д (да) или н (нет)" ;;
        esac
    done
}

ask_port() {
    local prompt="$1"
    local port
    while true; do
        read -rp "$(echo -e "${YELLOW}${prompt}${NC}")" port
        if validate_port "$port"; then
            echo "$port"
            return 0
        fi
    done
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        show_ascii_critical "Скрипт должен быть запущен от root!" "Используйте: sudo $SCRIPT_NAME"
        exit 1
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="${ID}"
        OS_VERSION="${VERSION_ID}"
    else
        show_ascii_critical "Не удалось определить ОС." "/etc/os-release не найден"
        exit 1
    fi
    if [[ "$OS_ID" != "debian" && "$OS_ID" != "ubuntu" ]]; then
        warn "Скрипт предназначен для Debian/Ubuntu. Обнаружено: ${OS_ID}. Продолжаем."
    fi
    log "INFO" "ОС: ${OS_ID} ${OS_VERSION}"
}

# ======================================================================
# МОДУЛЬ 1: Создание пользователя
# ======================================================================
module_create_user() {
    header "МОДУЛЬ 1: Создание пользователя"

    if ! confirm "Создать нового пользователя с правами sudo?"; then
        info "Пропуск создания пользователя."
        save_state "user_created" "no"
        return 0
    fi

    local username
    while true; do
        read -rp "$(echo -e "${YELLOW}Введите имя нового пользователя: ${NC}")" username
        if validate_username "$username"; then
            break
        fi
    done

    # Создание
    if ! dry_run_or_exec "Создание пользователя" \
        "Будет создан пользователь '${username}'" \
        "useradd -m -s /bin/bash '$username'"; then
        error_handler "Модуль 1" "Не удалось создать пользователя" "yes" "yes"
        case $? in 2) module_create_user; return ;; 1) save_state "user_created" "no"; return ;; 0) return ;; esac
    fi
    success "Пользователь '${username}' создан."

    # Пароль
    if confirm "Установить пароль для '${username}'?" "y"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            show_ascii_dryrun "Создание пользователя" "Будет установлен пароль для '${username}'" "passwd $username"
        else
            passwd "$username"
        fi
    fi

    # Sudo
    if confirm "Добавить '${username}' в группу sudo?" "y"; then
        if ! dry_run_or_exec "Создание пользователя" \
            "Пользователь '${username}' будет добавлен в группу sudo" \
            "usermod -aG sudo '$username'"; then
            error_handler "Модуль 1" "Не удалось добавить в sudo" "yes" "yes"
            case $? in 2) module_create_user; return ;; 1) break ;; 0) return ;; esac
        fi
        success "Пользователь '${username}' добавлен в группу sudo."
    fi

    # Копирование конфигов
    for f in .bashrc .profile .bash_profile; do
        if [[ -f "/root/${f}" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                show_ascii_dryrun "Создание пользователя" "Копирование ${f} в домашнюю директорию" "cp /root/${f} /home/${username}/${f}"
            else
                cp "/root/${f}" "/home/${username}/${f}" 2>/dev/null || true
                chown "${username}:${username}" "/home/${username}/${f}" 2>/dev/null || true
            fi
        fi
    done
    success "Конфигурации оболочки скопированы."

    # SSH-ключ
    if confirm "Сгенерировать SSH-ключ для '${username}'?" "y"; then
        local key_type
        while true; do
            read -rp "$(echo -e "${YELLOW}Тип ключа [ed25519/rsa]: ${NC}")" key_type
            key_type="${key_type:-ed25519}"
            case "$key_type" in
                ed25519|rsa) break ;;
                *) error "Выберите ed25519 или rsa" ;;
            esac
        done

        if ! dry_run_or_exec "Создание пользователя" \
            "Будет сгенерирован SSH-ключ (${key_type}) для '${username}'" \
            "sudo -u $username ssh-keygen -t $key_type -f /home/$username/.ssh/id_${key_type} -N '' -C '${username}@$(hostname)'"; then
            warn "Не удалось сгенерировать ключ. Продолжаем."
        else
            if [[ "$DRY_RUN" != "true" ]]; then
                local key_path="/home/${username}/.ssh/id_${key_type}"
                chmod 700 "/home/${username}/.ssh"
                chmod 600 "${key_path}"
                chmod 644 "${key_path}.pub"
                success "SSH-ключ сгенерирован."
                info "Публичный ключ:"
                divider
                cat "${key_path}.pub"
                divider
            fi
        fi
    fi

    save_state "user_created" "yes"
    save_state "username" "$username"
    success "Модуль 1 завершён."
}

# ======================================================================
# МОДУЛЬ 2: UFW файрвол
# ======================================================================
module_firewall() {
    header "МОДУЛЬ 2: UFW файрвол"

    if ! confirm "Настроить файрвол UFW?"; then
        info "Пропуск настройки файрвола."
        save_state "firewall_configured" "no"
        return 0
    fi

    # Установка
    if ! command -v ufw &>/dev/null; then
        info "Установка UFW..."
        if ! dry_run_or_exec "Настройка файрвола" \
            "UFW будет установлен" \
            "apt-get update -qq && apt-get install -y -qq ufw"; then
            error_handler "Модуль 2" "Не удалось установить UFW" "yes" "yes"
            case $? in 2) module_firewall; return ;; 1) save_state "firewall_configured" "no"; return ;; 0) return ;; esac
        fi
        success "UFW установлен."
    else
        info "UFW уже установлен."
    fi

    # Проверка: UFW уже активен?
    if ufw status 2>/dev/null | grep -q "Status: active"; then
        warn "UFW уже активен с текущими правилами."
        if ! confirm "Сбросить UFW и настроить заново?"; then
            save_state "firewall_configured" "skip"
            return 0
        fi
    fi

    # Бэкап
    backup_file "/etc/ufw/ufw.conf"
    backup_file "/etc/ufw/user.rules"
    backup_file "/etc/ufw/user6.rules"

    # Сброс
    if confirm "Сбросить UFW до значений по умолчанию?" "y"; then
        dry_run_or_exec "Настройка файрвола" \
            "UFW будет сброшен" \
            "ufw --force reset" || true
        success "UFW сброшен."
    fi

    # Политики
    dry_run_or_exec "Настройка файрвола" \
        "Политика: запретить входящие, разрешить исходящие" \
        "ufw default deny incoming && ufw default allow outgoing"
    success "Политики: запретить входящие, разрешить исходящие."

    # SSH
    local ssh_port
    ssh_port=$(load_state "new_ssh_port" "$ORIGINAL_SSH_PORT")
    dry_run_or_exec "Настройка файрвола" \
        "Разрешён SSH на порту ${ssh_port}/tcp" \
        "ufw allow ${ssh_port}/tcp comment 'SSH'"
    success "Разрешён SSH на порту ${ssh_port}/tcp."

    # HTTP
    if confirm "Разрешить HTTP (порт 80)?" "y"; then
        dry_run_or_exec "Настройка файрвола" \
            "Разрешён HTTP (80/tcp)" \
            "ufw allow 80/tcp comment 'HTTP'"
        success "Разрешён HTTP (80/tcp)."
    fi

    # HTTPS
    if confirm "Разрешить HTTPS (порт 443)?" "y"; then
        dry_run_or_exec "Настройка файрвола" \
            "Разрешён HTTPS (443/tcp)" \
            "ufw allow 443/tcp comment 'HTTPS'"
        success "Разрешён HTTPS (443/tcp)."
    fi

    # Кастомные порты
    while confirm "Добавить правило для кастомного порта?"; do
        local port proto
        port=$(ask_port "Введите номер порта: ")
        while true; do
            read -rp "$(echo -e "${YELLOW}Протокол [tcp/udp/оба]: ${NC}")" proto
            case "$proto" in
                tcp|udp|оба|both) break ;;
                *) error "Введите tcp, udp или оба" ;;
            esac
        done
        if [[ "$proto" == "оба" || "$proto" == "both" ]]; then
            dry_run_or_exec "Настройка файрвола" \
                "Разрешён порт ${port}/tcp и ${port}/udp" \
                "ufw allow ${port}/tcp comment 'Custom' && ufw allow ${port}/udp comment 'Custom'"
        else
            dry_run_or_exec "Настройка файрвола" \
                "Разрешён порт ${port}/${proto}" \
                "ufw allow ${port}/${proto} comment 'Custom'"
        fi
        success "Разрешён порт ${port}/${proto}."
    done

    # Включение
    if confirm "Включить UFW сейчас? (текущая SSH-сессия НЕ прервётся)" "y"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            show_ascii_dryrun "Настройка файрвола" "UFW будет включён" "echo 'y' | ufw enable"
        else
            echo "y" | ufw enable
        fi
        success "UFW включён."
    else
        warn "UFW НЕ включён. Выполните 'ufw enable' когда будете готовы."
    fi

    # Статус
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        info "Текущий статус UFW:"
        ufw status verbose
    fi

    save_state "firewall_configured" "yes"
    success "Модуль 2 завершён."
}

# ======================================================================
# МОДУЛЬ 3: Fail2ban
# ======================================================================
module_fail2ban() {
    header "МОДУЛЬ 3: Fail2ban"

    if ! confirm "Установить и настроить Fail2ban?"; then
        info "Пропуск Fail2ban."
        save_state "fail2ban_configured" "no"
        return 0
    fi

    # Установка
    if ! command -v fail2ban-client &>/dev/null; then
        info "Установка Fail2ban..."
        if ! dry_run_or_exec "Настройка Fail2ban" \
            "Fail2ban будет установлен" \
            "apt-get update -qq && apt-get install -y -qq fail2ban"; then
            error_handler "Модуль 3" "Не удалось установить Fail2ban" "yes" "yes"
            case $? in 2) module_fail2ban; return ;; 1) save_state "fail2ban_configured" "no"; return ;; 0) return ;; esac
        fi
        success "Fail2ban установлен."
    else
        info "Fail2ban уже установлен."
    fi

    backup_file "/etc/fail2ban/jail.local"

    local ssh_port
    ssh_port=$(load_state "new_ssh_port" "$ORIGINAL_SSH_PORT")

    local max_retry bantime findtime ignore_ip
    read -rp "$(echo -e "${YELLOW}Макс. неудачных попыток перед баном [3]: ${NC}")" max_retry
    max_retry="${max_retry:-3}"

    read -rp "$(echo -e "${YELLOW}Длительность блокировки в секундах [3600]: ${NC}")" bantime
    bantime="${bantime:-3600}"

    read -rp "$(echo -e "${YELLOW}Окно подсчёта попыток в секундах [600]: ${NC}")" findtime
    findtime="${findtime:-600}"

    read -rp "$(echo -e "${YELLOW}Игнорировать IP (например 127.0.0.1 или пусто): ${NC}")" ignore_ip

    if [[ "$DRY_RUN" == "true" ]]; then
        show_ascii_dryrun "Настройка Fail2ban" \
            "Будет создан /etc/fail2ban/jail.local с настройками: maxretry=${max_retry}, bantime=${bantime}" \
            "cat > /etc/fail2ban/jail.local"
    else
        cat > /etc/fail2ban/jail.local <<JAIL
[DEFAULT]
bantime  = ${bantime}
findtime = ${findtime}
maxretry = ${max_retry}
banaction = ufw
JAIL

        [[ -n "$ignore_ip" ]] && echo "ignoreip = ${ignore_ip}" >> /etc/fail2ban/jail.local

        cat >> /etc/fail2ban/jail.local <<JAIL

[sshd]
enabled  = true
port     = ${ssh_port}
filter   = sshd
logpath  = /var/log/auth.log
maxretry = ${max_retry}
JAIL
    fi
    success "Конфигурация Fail2ban записана."

    # Nginx jail
    if confirm "Включить jail для Nginx/Apache (защита от HTTP-флуда)?" "n"; then
        if [[ "$DRY_RUN" != "true" ]]; then
            cat >> /etc/fail2ban/jail.local <<JAIL

[nginx-http-auth]
enabled  = true
port     = http,https
filter   = nginx-http-auth
logpath  = /var/log/nginx/error.log
maxretry = 5

[nginx-limit-req]
enabled  = true
port     = http,https
filter   = nginx-limit-req
logpath  = /var/log/nginx/error.log
maxretry = 10
JAIL
        fi
        success "Jail для Nginx добавлены."
    fi

    # Запуск
    dry_run_or_exec "Настройка Fail2ban" \
        "Fail2ban будет включён и запущен" \
        "systemctl enable fail2ban && systemctl restart fail2ban"
    success "Fail2ban включён и запущен."

    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        info "Статус Fail2ban:"
        fail2ban-client status 2>/dev/null || true
        fail2ban-client status sshd 2>/dev/null || true
    fi

    save_state "fail2ban_configured" "yes"
    success "Модуль 3 завершён."
}

# ======================================================================
# МОДУЛЬ 4: Смена SSH порта
# ======================================================================
module_ssh_port() {
    header "МОДУЛЬ 4: Смена SSH порта"

    local current_port
    current_port=$(grep -E "^Port\s" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
    info "Текущий порт SSH: ${current_port}"

    if ! confirm "Изменить порт SSH?"; then
        info "Пропуск смены порта."
        save_state "new_ssh_port" "$current_port"
        return 0
    fi

    # Проверка sshd_config
    if [[ ! -f /etc/ssh/sshd_config ]]; then
        show_ascii_critical "Файл /etc/ssh/sshd_config не найден!" "Невозможно изменить порт SSH."
        save_state "new_ssh_port" "$current_port"
        return 1
    fi

    local new_port
    new_port=$(ask_port "Введите новый порт SSH: ")

    if [[ "$new_port" == "$current_port" ]]; then
        warn "Новый порт совпадает с текущим. Пропуск."
        save_state "new_ssh_port" "$current_port"
        return 0
    fi

    backup_file "/etc/ssh/sshd_config"

    # Изменение
    if ! dry_run_or_exec "Смена SSH порта" \
        "Порт SSH изменён с ${current_port} на ${new_port}" \
        "sed -i 's/^Port\s.*/# Port ${current_port}\nPort ${new_port}/' /etc/ssh/sshd_config"; then
        error_handler "Модуль 4" "Не удалось изменить sshd_config" "yes" "yes"
        case $? in 2) module_ssh_port; return ;; 1) save_state "new_ssh_port" "$current_port"; return ;; 0) return ;; esac
    fi

    # Проверка конфига
    if [[ "$DRY_RUN" != "true" ]]; then
        if sshd -t 2>/dev/null; then
            success "Проверка конфигурации sshd пройдена."
        else
            show_ascii_error "Смена SSH порта" "Проверка конфигурации sshd НЕ пройдена!"
            warn "Восстановление из резервной копии..."
            cp "${BACKUP_DIR}/sshd_config.bak" "/etc/ssh/sshd_config"
            warn "Порт SSH восстановлен на ${current_port}."
            save_state "new_ssh_port" "$current_port"
            return 1
        fi
    fi

    # UFW
    if [[ "$DRY_RUN" == "true" ]] || ufw status 2>/dev/null | grep -q "active"; then
        if confirm "Обновить правила UFW для нового порта SSH? (оставить старый как запасной)" "y"; then
            dry_run_or_exec "Смена SSH порта" \
                "В UFW разрешён новый порт ${new_port}/tcp" \
                "ufw allow ${new_port}/tcp comment 'SSH new port'"
            success "UFW: разрешён порт ${new_port}/tcp."
        fi
    fi

    # Перезапуск
    if confirm "Перезапустить SSHD сейчас? (текущая сессия использует порт ${current_port} - НЕ прервётся)" "y"; then
        dry_run_or_exec "Смена SSH порта" \
            "SSHD будет перезапущен" \
            "systemctl restart sshd"
        success "SSHD перезапущен на порту ${new_port}."
        warn "Подключиться через: ssh -p ${new_port} user@$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi

    save_state "new_ssh_port" "$new_port"
    success "Модуль 4 завершён."
}

# ======================================================================
# МОДУЛЬ 5: SSH-ключи и харденинг
# ======================================================================
module_ssh_keys() {
    header "МОДУЛЬ 5: SSH-ключи и ужесточение настроек"

    if ! confirm "Настроить авторизацию по SSH-ключам?"; then
        info "Пропуск настройки SSH-ключей."
        save_state "ssh_keys_configured" "no"
        return 0
    fi

    backup_file "/etc/ssh/sshd_config"

    # Генерация ключей
    if confirm "Сгенерировать новую SSH-ключевую пару на сервере?"; then
        local key_type
        while true; do
            read -rp "$(echo -e "${YELLOW}Тип ключа [ed25519/rsa]: ${NC}")" key_type
            key_type="${key_type:-ed25519}"
            case "$key_type" in
                ed25519|rsa) break ;;
                *) error "Выберите ed25519 или rsa" ;;
            esac
        done

        local key_path="/root/.ssh/id_${key_type}_server"
        if ! dry_run_or_exec "SSH-ключи" \
            "Будет сгенерирован ключ ${key_type}" \
            "ssh-keygen -t ${key_type} -f ${key_path} -N '' -C 'server-$(hostname)-$(date +%Y%m%d)'"; then
            warn "Не удалось сгенерировать ключ. Продолжаем."
        else
            if [[ "$DRY_RUN" != "true" ]]; then
                echo ""
                divider
                info "ВАШ ПУБЛИЧНЫЙ КЛЮЧ (скопируйте на локальную машину в ~/.ssh/authorized_keys):"
                divider
                cat "${key_path}.pub"
                divider
                echo ""
                warn "Сохраните этот ключ! Он также находится: ${key_path}"
            fi
        fi
    fi

    # Вставка ключа в root
    if confirm "Добавить публичный ключ в authorized_keys для root?" "y"; then
        local pubkey
        echo ""
        info "Вставьте ваш ПУБЛИЧНЫЙ КЛЮЧ (полная строка, начинается с ssh-ed25519 или ssh-rsa):"
        read -rp "$(echo -e "${YELLOW}> ${NC}")" pubkey

        if [[ -n "$pubkey" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                show_ascii_dryrun "SSH-ключи" "Публичный ключ будет добавлен в /root/.ssh/authorized_keys" "echo '$pubkey' >> /root/.ssh/authorized_keys"
            else
                mkdir -p /root/.ssh && chmod 700 /root/.ssh
                touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
                if grep -qF "$pubkey" /root/.ssh/authorized_keys; then
                    warn "Ключ уже существует в authorized_keys."
                else
                    echo "$pubkey" >> /root/.ssh/authorized_keys
                    success "Публичный ключ добавлен в /root/.ssh/authorized_keys"
                fi
            fi
        else
            warn "Ключ не введён. Пропуск."
        fi
    fi

    # Ключ для другого пользователя
    if confirm "Добавить публичный ключ другому пользователю?" "n"; then
        local target_user
        read -rp "$(echo -e "${YELLOW}Имя пользователя: ${NC}")" target_user

        if ! id "$target_user" &>/dev/null; then
            error "Пользователь '${target_user}' не существует."
        else
            echo -e "${YELLOW}Вставьте публичный ключ:${NC}"
            local pubkey2
            read -rp "> " pubkey2

            if [[ -n "$pubkey2" ]]; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    show_ascii_dryrun "SSH-ключи" "Ключ будет добавлен пользователю ${target_user}" "echo key >> /home/${target_user}/.ssh/authorized_keys"
                else
                    local home_dir
                    home_dir=$(eval echo "~${target_user}")
                    mkdir -p "${home_dir}/.ssh" && chmod 700 "${home_dir}/.ssh"
                    touch "${home_dir}/.ssh/authorized_keys" && chmod 600 "${home_dir}/.ssh/authorized_keys"
                    echo "$pubkey2" >> "${home_dir}/.ssh/authorized_keys"
                    chown -R "${target_user}:${target_user}" "${home_dir}/.ssh"
                    success "Ключ добавлен пользователю ${target_user}."
                fi
            fi
        fi
    fi

    # --- Харденинг ---
    info "Ужесточение настроек SSH..."

    if confirm "Запретить вход от root по SSH?" "y"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            show_ascii_dryrun "SSH-ключи" "PermitRootLogin будет установлен в 'no'" "sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config"
        else
            if grep -q "^PermitRootLogin" /etc/ssh/sshd_config; then
                sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
            else
                echo "PermitRootLogin no" >> /etc/ssh/sshd_config
            fi
        fi
        success "PermitRootLogin установлен в 'no'."
    fi

    if confirm "Отключить авторизацию по паролю (только ключи)?" "y"; then
        # Проверка: есть ли ключи?
        local has_keys=false
        for user_home in /root /home/*; do
            if [[ -f "${user_home}/.ssh/authorized_keys" ]] && [[ -s "${user_home}/.ssh/authorized_keys" ]]; then
                has_keys=true
                break
            fi
        done

        if [[ "$has_keys" == "false" ]]; then
            show_ascii_critical \
                "SSH-ключи не найдены в authorized_keys!" \
                "Невозможно отключить парольную авторизацию без ключей. Добавьте ключ и повторите."
            warn "Пропуск отключения парольной авторизации."
        else
            if [[ "$DRY_RUN" == "true" ]]; then
                show_ascii_dryrun "SSH-ключи" "PasswordAuthentication будет установлен в 'no'" "sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config"
            else
                if grep -q "^PasswordAuthentication" /etc/ssh/sshd_config; then
                    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
                else
                    echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
                fi
            fi
            success "PasswordAuthentication установлен в 'no'."
        fi
    fi

    local max_tries
    read -rp "$(echo -e "${YELLOW}Макс. попыток аутентификации [3]: ${NC}")" max_tries
    max_tries="${max_tries:-3}"
    if [[ "$DRY_RUN" == "true" ]]; then
        show_ascii_dryrun "SSH-ключи" "MaxAuthTries будет установлен в ${max_tries}" "sed -i 's/^MaxAuthTries.*/MaxAuthTries ${max_tries}/' /etc/ssh/sshd_config"
    else
        if grep -q "^MaxAuthTries" /etc/ssh/sshd_config; then
            sed -i "s/^MaxAuthTries.*/MaxAuthTries ${max_tries}/" /etc/ssh/sshd_config
        else
            echo "MaxAuthTries ${max_tries}" >> /etc/ssh/sshd_config
        fi
    fi
    success "MaxAuthTries установлен в ${max_tries}."

    if confirm "Отключить проброс X11?" "y"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            show_ascii_dryrun "SSH-ключи" "X11Forwarding будет установлен в 'no'" "sed -i 's/^X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config"
        else
            if grep -q "^X11Forwarding" /etc/ssh/sshd_config; then
                sed -i 's/^X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
            else
                echo "X11Forwarding no" >> /etc/ssh/sshd_config
            fi
        fi
        success "X11Forwarding установлен в 'no'."
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        show_ascii_dryrun "SSH-ключи" "PermitEmptyPasswords будет установлен в 'no'" "sed -i 's/^PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config"
    else
        if grep -q "^PermitEmptyPasswords" /etc/ssh/sshd_config; then
            sed -i 's/^PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config
        else
            echo "PermitEmptyPasswords no" >> /etc/ssh/sshd_config
        fi
    fi
    success "PermitEmptyPasswords установлен в 'no'."

    # Проверка конфига
    if [[ "$DRY_RUN" != "true" ]]; then
        if sshd -t 2>/dev/null; then
            success "Проверка конфигурации sshd пройдена."
        else
            show_ascii_error "SSH-ключи" "Проверка конфигурации sshd НЕ пройдена!"
            warn "Восстановление из резервной копии..."
            cp "${BACKUP_DIR}/sshd_config.bak" "/etc/ssh/sshd_config"
            warn "SSH-конфигурация восстановлена."
            save_state "ssh_keys_configured" "error"
            return 1
        fi
    fi

    if confirm "Перезапустить SSHD для применения изменений?" "y"; then
        dry_run_or_exec "SSH-ключи" \
            "SSHD будет перезапущен" \
            "systemctl restart sshd"
        success "SSHD перезапущен."
    fi

    save_state "ssh_keys_configured" "yes"
    success "Модуль 5 завершён."
}

# ======================================================================
# МОДУЛЬ 6: Автообновления
# ======================================================================
module_auto_updates() {
    header "МОДУЛЬ 6: Автоматические обновления безопасности"

    if ! confirm "Включить автоматические обновления безопасности?"; then
        info "Пропуск автообновлений."
        save_state "auto_updates" "no"
        return 0
    fi

    info "Установка unattended-upgrades..."
    if ! dry_run_or_exec "Автообновления" \
        "unattended-upgrades будет установлен" \
        "apt-get update -qq && apt-get install -y -qq unattended-upgrades apt-listchanges"; then
        error_handler "Модуль 6" "Не удалось установить unattended-upgrades" "yes" "yes"
        case $? in 2) module_auto_updates; return ;; 1) save_state "auto_updates" "no"; return ;; 0) return ;; esac
    fi

    if [[ "$DRY_RUN" != "true" ]]; then
        cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'UPGRADES'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Package-Blacklist {
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
UPGRADES

        cat > /etc/apt/apt.conf.d/20auto-upgrades <<'AUTO'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
AUTO
    else
        show_ascii_dryrun "Автообновления" \
            "Будут созданы конфигурации unattended-upgrades" \
            "cat > /etc/apt/apt.conf.d/50unattended-upgrades"
    fi

    dry_run_or_exec "Автообновления" \
        "unattended-upgrades будет включён" \
        "systemctl enable unattended-upgrades && systemctl restart unattended-upgrades"

    success "Автоматические обновления безопасности включены."
    warn "Сервер НЕ будет перезагружаться автоматически. Перезагружайте вручную после обновлений ядра."

    save_state "auto_updates" "yes"
    success "Модуль 6 завершён."
}

# ======================================================================
# МОДУЛЬ 7: Аудит SSH
# ======================================================================
module_ssh_audit() {
    header "МОДУЛЬ 7: Аудит уязвимостей OpenSSH"

    if ! confirm "Запустить аудит уязвимостей и конфигурации SSH?"; then
        info "Пропуск аудита SSH."
        save_state "ssh_audit" "no"
        return 0
    fi

    local ssh_version
    ssh_version=$(ssh -V 2>&1 || echo "unknown")
    info "Установленная версия SSH: ${ssh_version}"
    log "AUDIT" "Версия SSH: ${ssh_version}"

    local ver_num major_ver
    ver_num=$(echo "$ssh_version" | grep -oP 'OpenSSH_\K[0-9]+(\.[0-9]+)*' || echo "0")
    major_ver=$(echo "$ver_num" | cut -d. -f1)

    echo ""
    divider
    info "ПРОВЕРКИ УЯЗВИМОСТЕЙ"
    divider
    echo ""

    local issues=0
    local sshd_conf="/etc/ssh/sshd_config"

    # CVE-2023-38408
    if [[ "$major_ver" -le 9 ]] 2>/dev/null; then
        warn "  [!] CVE-2023-38408 (удалённое выполнение кода через ssh-agent)"
        warn "      Затронутые версии: OpenSSH <= 9.3"
        warn "      Исправление: обновить до OpenSSH >= 9.3p2"
        ((issues++)) || true
    fi

    # CVE-2023-48795 (Terrapin)
    local minor_ver
    minor_ver=$(echo "$ver_num" | cut -d. -f2)
    if [[ "$major_ver" -lt 9 ]] || { [[ "$major_ver" -eq 9 ]] && [[ "${minor_ver:-0}" -lt 6 ]]; }; then
        warn "  [!] CVE-2023-48795 (Terrapin — атака на префикс ключевого обмена)"
        warn "      Затронутые версии: OpenSSH < 9.6p1"
        warn "      Исправление: обновить до OpenSSH >= 9.6p1"
        ((issues++)) || true
    fi

    # CVE-2024-6387 (regreSSHion)
    if [[ "$major_ver" -ge 8 ]] && [[ "$major_ver" -le 9 ]] 2>/dev/null; then
        warn "  [!] CVE-2024-6387 (regreSSHion — гонка данных)"
        warn "      Затронутые версии: OpenSSH 8.5p1 - 9.7p1 (glibc)"
        warn "      Исправление: обновить до OpenSSH >= 9.8p1"
        ((issues++)) || true
    fi

    # Слабые шифры
    if [[ -f "$sshd_conf" ]]; then
        info "Проверка sshd_config на слабые настройки..."
        echo ""

        if grep -qi "^Ciphers" "$sshd_conf"; then
            local ciphers
            ciphers=$(grep "^Ciphers" "$sshd_conf" | awk '{print $2}')
            if echo "$ciphers" | grep -qiE "3des|cbc|arcfour|blowfish"; then
                warn "  [!] Слабые шифры: ${ciphers}"
                warn "      Рекомендуется: chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com"
                ((issues++)) || true
            else
                success "  Шифры OK: ${ciphers}"
            fi
        fi

        if grep -qi "^MACs" "$sshd_conf"; then
            local macs
            macs=$(grep "^MACs" "$sshd_conf" | awk '{print $2}')
            if echo "$macs" | grep -qiE "hmac-md5|hmac-sha1-96|hmac-md5-96"; then
                warn "  [!] Слабые MAC: ${macs}"
                warn "      Рекомендуется: hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com"
                ((issues++)) || true
            else
                success "  MAC OK: ${macs}"
            fi
        fi

        if grep -qi "^KexAlgorithms" "$sshd_conf"; then
            local kex
            kex=$(grep "^KexAlgorithms" "$sshd_conf" | awk '{print $2}')
            if echo "$kex" | grep -qiE "diffie-hellman-group1-sha1|diffie-hellman-group14-sha1"; then
                warn "  [!] Слабые KexAlgorithms: ${kex}"
                warn "      Рекомендуется: sntrup761x25519-sha512@openssh.com,curve25519-sha256"
                ((issues++)) || true
            else
                success "  KexAlgorithms OK: ${kex}"
            fi
        fi

        local grace_time
        grace_time=$(grep -E "^LoginGraceTime" "$sshd_conf" 2>/dev/null | awk '{print $2}' || echo "120")
        if [[ "$grace_time" -gt 60 ]] 2>/dev/null; then
            warn "  [!] LoginGraceTime = ${grace}с (рекомендуется: 30с или менее)"
            ((issues++)) || true
        else
            success "  LoginGraceTime: ${grace_time}с"
        fi
    fi

    # Авто-fix
    echo ""
    if [[ $issues -gt 0 ]]; then
        warn "Найдено ${issues} проблем(ы)."

        if confirm "Применить рекомендуемые шифры/MAC/KexAlgorithms к sshd_config?" "y"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                show_ascii_dryrun "SSH аудит" \
                    "Будут применены рекомендуемые шифры, MAC и KexAlgorithms" \
                    "sed -i '/Security Hardening/,/End Security Hardening/d' /etc/ssh/sshd_config"
            else
                backup_file "/etc/ssh/sshd_config"
                local block="

# === Security Hardening (vps-security.sh) ===
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
KexAlgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group18-sha512,diffie-hellman-group16-sha512
LoginGraceTime 30
# === End Security Hardening ==="
                sed -i '/# === Security Hardening (vps-security.sh) ===/,/# === End Security Hardening ===/d' /etc/ssh/sshd_config
                echo "$block" >> /etc/ssh/sshd_config
            fi
            success "Шифры/MAC/KexAlgorithms применены."

            if [[ "$DRY_RUN" != "true" ]] && ! sshd -t 2>/dev/null; then
                error "Проверка sshd НЕ пройдена! Восстановление..."
                cp "${BACKUP_DIR}/sshd_config.bak" "/etc/ssh/sshd_config"
            fi
        fi
    else
        success "Слабых шифров/MAC/KexAlgorithms не обнаружено."
    fi

    # Права на .ssh
    info "Проверка прав на SSH-директории..."
    for user_home in /root /home/*; do
        if [[ -d "${user_home}/.ssh" ]]; then
            local perms
            perms=$(stat -c "%a" "${user_home}/.ssh" 2>/dev/null)
            if [[ "$perms" != "700" ]]; then
                warn "  [!] ${user_home}/.ssh права: ${perms} (должно быть 700)"
                if [[ "$DRY_RUN" != "true" ]]; then
                    chmod 700 "${user_home}/.ssh"
                fi
                success "  Исправлено: ${user_home}/.ssh -> 700"
            else
                success "  ${user_home}/.ssh права: OK (700)"
            fi

            if [[ -f "${user_home}/.ssh/authorized_keys" ]]; then
                perms=$(stat -c "%a" "${user_home}/.ssh/authorized_keys" 2>/dev/null)
                if [[ "$perms" != "600" ]]; then
                    warn "  [!] ${user_home}/.ssh/authorized_keys права: ${perms} (должно быть 600)"
                    if [[ "$DRY_RUN" != "true" ]]; then
                        chmod 600 "${user_home}/.ssh/authorized_keys"
                    fi
                    success "  Исправлено: authorized_keys -> 600"
                else
                    success "  authorized_keys права: OK (600)"
                fi
            fi
        fi
    done

    if [[ $issues -gt 0 ]] && confirm "Перезапустить SSHD для применения шифров?" "y"; then
        dry_run_or_exec "SSH аудит" \
            "SSHD будет перезапущен с новыми настройками шифров" \
            "systemctl restart sshd"
    fi

    echo ""
    divider
    if [[ $issues -gt 0 ]]; then
        warn "Аудит выявил ${issues} проблем(ы). Проверьте вывод выше."
    else
        success "Аудит SSH пройден. Критических проблем не обнаружено."
    fi
    divider

    save_state "ssh_audit" "yes"
    save_state "ssh_audit_issues" "$issues"
    success "Модуль 7 завершён."
}

# ======================================================================
# МОДУЛЬ 8: AIDE
# ======================================================================
module_aide() {
    header "МОДУЛЬ 8: AIDE — мониторинг целостности файлов (IDS)"

    if ! confirm "Установить и настроить AIDE (система обнаружения вторжений)?"; then
        info "Пропуск AIDE."
        save_state "aide_configured" "no"
        return 0
    fi

    # Установка
    info "Установка AIDE..."
    if ! dry_run_or_exec "AIDE" \
        "AIDE будет установлен" \
        "apt-get update -qq && apt-get install -y -qq aide"; then
        error_handler "Модуль 8" "Не удалось установить AIDE" "yes" "yes"
        case $? in 2) module_aide; return ;; 1) save_state "aide_configured" "no"; return ;; 0) return ;; esac
    fi
    success "AIDE установлен."

    backup_file "/etc/aide/aide.conf"

    # Проверка места на диске
    local avail_kb
    avail_kb=$(df / --output=avail 2>/dev/null | tail -1 | tr -d ' ' || echo "0")
    if [[ "$avail_kb" -lt 1048576 ]] 2>/dev/null; then
        show_ascii_warning "Мало места на диске! Доступно: $(( avail_kb / 1024 ))MB. Рекомендуется минимум 1GB."
        if ! confirm "Продолжить несмотря на мало места?"; then
            save_state "aide_configured" "no"
            return 0
        fi
    fi

    info "Проверка AIDE..."
    if [[ "$DRY_RUN" == "true" ]]; then
        show_ascii_dryrun "AIDE" \
            "Будет создана база AIDE (может занять несколько минут)" \
            "aideinit || aide --init"
    else
        warn "Создание базы AIDE... Это может занять несколько минут."
        echo ""
        if aideinit 2>/dev/null || aide --init 2>/dev/null; then
            success "База AIDE инициализирована."
            local aide_db_dir
            aide_db_dir=$(grep "^DBDIR" /etc/aide/aide.conf 2>/dev/null | awk '{print $3}' || echo "/var/lib/aide")
            aide_db_dir="${aide_db_dir:-/var/lib/aide}"

            if [[ -f "${aide_db_dir}/aide.db.new" ]]; then
                mv "${aide_db_dir}/aide.db.new" "${aide_db_dir}/aide.db"
                success "База AIDE активирована."
            elif [[ -f "${aide_db_dir}/aide.db.new.gz" ]]; then
                mv "${aide_db_dir}/aide.db.new.gz" "${aide_db_dir}/aide.db.gz"
                success "База AIDE активирована."
            fi
        else
            error_handler "Модуль 8" "Не удалось инициализировать AIDE" "yes" "yes"
            case $? in 2) module_aide; return ;; 1) save_state "aide_configured" "error"; return ;; 0) return ;; esac
        fi
    fi

    # Email
    local aide_email=""
    if confirm "Настроить email-уведомления для AIDE?" "y"; then
        while true; do
            read -rp "$(echo -e "${YELLOW}Введите email для уведомлений: ${NC}")" aide_email
            if validate_email "$aide_email"; then
                break
            fi
        done

        # Установка mailutils
        if ! command -v mail &>/dev/null; then
            dry_run_or_exec "AIDE" \
                "mailutils будет установлен для отправки уведомлений" \
                "apt-get install -y -qq mailutils"
        fi
    fi

    # Cron
    if confirm "Настроить ежедневную проверку AIDE через cron?" "y"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            show_ascii_dryrun "AIDE" \
                "Будет создана cron-задача для ежедневной проверки" \
                "cat > /etc/cron.daily/aide-check"
        else
            mkdir -p /var/log/aide
            cat > /etc/cron.daily/aide-check <<CRON
#!/bin/bash
LOG="/var/log/aide/aide-check-\$(date +%Y%m%d).log"
REPORT="/var/log/aide/aide-report-\$(date +%Y%m%d).txt"
echo "=== Проверка AIDE: \$(date) ===" > "\$LOG"
aide --check >> "\$LOG" 2>&1
CRON
            if [[ -n "$aide_email" ]]; then
                cat >> /etc/cron.daily/aide-check <<CRON
if grep -q "changed\|Added\|Removed" "\$LOG"; then
    echo "ALERT: AIDE обнаружил изменения на \$(hostname)!" > "\$REPORT"
    echo "Дата: \$(date)" >> "\$REPORT"
    echo "Сервер: \$(hostname) (\$(hostname -I | awk '{print \$1}'))" >> "\$REPORT"
    echo "" >> "\$REPORT"
    grep -E "^(Changed|Added|Removed|File)" "\$LOG" >> "\$REPORT" 2>/dev/null || true
    mail -s "[BEZOPASnost] AIDE Alert: \$(hostname) - обнаружены изменения" "${aide_email}" < "\$REPORT"
fi
CRON
            fi
            cat >> /etc/cron.daily/aide-check <<'CRON'
find /var/log/aide -name "aide-*" -mtime +30 -delete 2>/dev/null
CRON
            chmod +x /etc/cron.daily/aide-check
            success "Cron-задача AIDE создана."
            [[ -n "$aide_email" ]] && success "Уведомления будут отправляться на: ${aide_email}"
        fi
    fi

    # Первый запуск
    if [[ "$DRY_RUN" != "true" ]] && confirm "Запустить первую проверку AIDE сейчас? (занимает время)" "n"; then
        warn "Запуск проверки AIDE..."
        aide --check 2>&1 | tail -20
        success "Проверка AIDE завершена."
    fi

    info "Полезные команды:"
    echo -e "  ${CYAN}aide --check${NC}        - проверить изменения"
    echo -e "  ${CYAN}aide --update${NC}       - обновить базу после просмотра изменений"
    echo -e "  ${CYAN}aide --compare${NC}      - сравнить текущее состояние"

    save_state "aide_configured" "yes"
    success "Модуль 8 завершён."
}

# ======================================================================
# МОДУЛЬ 9: rkhunter
# ======================================================================
module_rkhunter() {
    header "МОДУЛЬ 9: rkhunter — обнаружение руткитов"

    if ! confirm "Установить и настроить rkhunter (сканер руткитов)?"; then
        info "Пропуск rkhunter."
        save_state "rkhunter_configured" "no"
        return 0
    fi

    # Установка
    info "Установка rkhunter..."
    if ! dry_run_or_exec "rkhunter" \
        "rkhunter будет установлен" \
        "apt-get update -qq && apt-get install -y -qq rkhunter"; then
        error_handler "Модуль 9" "Не удалось установить rkhunter" "yes" "yes"
        case $? in 2) module_rkhunter; return ;; 1) save_state "rkhunter_configured" "no"; return ;; 0) return ;; esac
    fi
    success "rkhunter установлен."

    backup_file "/etc/rkhunter.conf"

    # Обновление баз
    if [[ "$DRY_RUN" == "true" ]]; then
        show_ascii_dryrun "rkhunter" \
            "Базы rkhunter будут обновлены" \
            "rkhunter --update --quiet"
    else
        info "Обновление баз rkhunter..."
        if ! rkhunter --update --quiet 2>/dev/null; then
            warn "Обновление баз rkhunter завершилось с ошибкой (возможно, сеть ограничена). Продолжаем."
        else
            success "Базы rkhunter обновлены."
        fi
    fi

    # Email
    local rkhunter_email=""
    if confirm "Настроить email-уведомления для rkhunter?" "y"; then
        while true; do
            read -rp "$(echo -e "${YELLOW}Введите email для уведомлений: ${NC}")" rkhunter_email
            if validate_email "$rkhunter_email"; then
                break
            fi
        done

        if ! command -v mail &>/dev/null; then
            dry_run_or_exec "rkhunter" \
                "mailutils будет установлен" \
                "apt-get install -y -qq mailutils"
        fi
    fi

    # Cron
    if confirm "Настроить ежедневный скан rkhunter через cron?" "y"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            show_ascii_dryrun "rkhunter" \
                "Будет создана cron-задача для ежедневного сканирования" \
                "cat > /etc/cron.daily/rkhunter-check"
        else
            mkdir -p /var/log/rkhunter
            cat > /etc/cron.daily/rkhunter-check <<CRON
#!/bin/bash
LOG="/var/log/rkhunter/rkhunter-\$(date +%Y%m%d).log"
REPORT="/var/log/rkhunter/rkhunter-report-\$(date +%Y%m%d).txt"
echo "=== Проверка rkhunter: \$(date) ===" > "\$LOG"
rkhunter --check --sk --quiet --report-warnings-only >> "\$LOG" 2>&1
CRON
            if [[ -n "$rkhunter_email" ]]; then
                cat >> /etc/cron.daily/rkhunter-check <<CRON
if grep -qi "warning\|suspect\|infected" "\$LOG"; then
    echo "ALERT: rkhunter обнаружил предупреждения на \$(hostname)!" > "\$REPORT"
    echo "Дата: \$(date)" >> "\$REPORT"
    echo "Сервер: \$(hostname) (\$(hostname -I | awk '{print \$1}'))" >> "\$REPORT"
    echo "" >> "\$REPORT"
    grep -iE "warning|suspect|infected|found" "\$LOG" >> "\$REPORT" 2>/dev/null || true
    mail -s "[BEZOPASnost] rkhunter Alert: \$(hostname) - предупреждения" "${rkhunter_email}" < "\$REPORT"
fi
CRON
            fi
            cat >> /etc/cron.daily/rkhunter-check <<'CRON'
find /var/log/rkhunter -name "rkhunter-*" -mtime +30 -delete 2>/dev/null
CRON
            chmod +x /etc/cron.daily/rkhunter-check
            success "Cron-задача rkhunter создана."
            [[ -n "$rkhunter_email" ]] && success "Уведомления будут отправляться на: ${rkhunter_email}"
        fi
    fi

    # Первый запуск
    if [[ "$DRY_RUN" != "true" ]] && confirm "Запустить первый скан rkhunter сейчас? (занимает несколько минут)" "n"; then
        warn "Запуск скана rkhunter..."
        rkhunter --check --sk --quiet 2>&1 | tail -20
        success "Скан rkhunter завершён."
    fi

    info "Полезные команды:"
    echo -e "  ${CYAN}rkhunter --check --sk${NC}           - запустить скан (без пауз)"
    echo -e "  ${CYAN}rkhunter --update${NC}               - обновить базы"
    echo -e "  ${CYAN}rkhunter --check --report-warnings-only${NC} - только предупреждения"

    save_state "rkhunter_configured" "yes"
    success "Модуль 9 завершён."
}

# ======================================================================
# МОДУЛЬ 10: Блокировка root
# ======================================================================
module_lock_root() {
    header "МОДУЛЬ 10: Блокировка пароля root"

    echo ""
    show_ascii_warning "Этот модуль блокирует пароль root. Вы СМОЖЕТЕ стать root ТОЛЬКО через: sudo su - или sudo -i"
    warn "Убедитесь, что у вас есть sudo-пользователь (Модуль 1)!"
    echo ""

    # Проверка sudo-пользователей
    local sudo_users
    sudo_users=$(getent group sudo 2>/dev/null | cut -d: -f4 || true)
    if [[ -z "$sudo_users" ]]; then
        show_ascii_critical \
            "Sudo-пользователи не найдены!" \
            "Сначала создайте sudo-пользователя (Модуль 1), затем повторите."
        warn "Пропуск блокировки root."
        save_state "root_locked" "no"
        return 1
    fi

    info "Пользователи в группе sudo: ${sudo_users}"

    if ! confirm "Заблокировать пароль root?"; then
        info "Пропуск блокировки root."
        save_state "root_locked" "no"
        return 0
    fi

    backup_file "/etc/shadow"

    # Текущий статус
    local root_status
    root_status=$(passwd --status root 2>/dev/null || echo "недоступно")
    info "Текущий статус пароля root: ${root_status}"

    # Блокировка
    if ! dry_run_or_exec "Блокировка root" \
        "Пароль root будет заблокирован" \
        "passwd -l root"; then
        error_handler "Модуль 10" "Не удалось заблокировать пароль root" "yes" "yes"
        case $? in 2) module_lock_root; return ;; 1) save_state "root_locked" "no"; return ;; 0) return ;; esac
    fi
    success "Пароль root заблокирован."

    if [[ "$DRY_RUN" != "true" ]]; then
        root_status=$(passwd --status root 2>/dev/null || echo "недоступно")
        info "Новый статус пароля root: ${root_status}"
    fi

    echo ""
    info "Что это значит:"
    echo -e "  ${GREEN}+${NC} 'ssh root@сервер' с паролем: ${RED}ЗАБЛОКИРОВАНО${NC}"
    echo -e "  ${GREEN}+${NC} 'su - root' с паролем: ${RED}ЗАБЛОКИРОВАНО${NC}"
    echo -e "  ${GREEN}+${NC} 'sudo su -' из sudo-пользователя: ${GREEN}РАБОТАЕТ${NC}"
    echo -e "  ${GREEN}+${NC} 'sudo -i' из sudo-пользователя: ${GREEN}РАБОТАЕТ${NC}"
    echo -e "  ${GREEN}+${NC} SSH-ключи для root: ${GREEN}РАБОТАЮТ${NC} (если настроены)"
    echo ""

    # Дополнительно: nologin shell
    if confirm "Дополнительно установить root shell на /usr/sbin/nologin? (дополнительная защита)" "n"; then
        backup_file "/etc/passwd"
        if [[ "$DRY_RUN" == "true" ]]; then
            show_ascii_dryrun "Блокировка root" \
                "Root shell будет установлен на /usr/sbin/nologin" \
                "chsh -s /usr/sbin/nologin root"
        else
            chsh -s /usr/sbin/nologin root
        fi
        success "Root shell установлен на /usr/sbin/nologin."
        warn "Root имеет доступ ТОЛЬКО через 'sudo'."
    fi

    save_state "root_locked" "yes"
    success "Модуль 10 завершён."
}

# ======================================================================
# ОТКАТ
# ======================================================================
do_rollback() {
    header "ОТКАТ: Восстановление предыдущего состояния"

    local backup_path="$1"

    if [[ -z "$backup_path" ]] || [[ ! -d "$backup_path" ]]; then
        backup_path=$(find /root/vps-security-backups -maxdepth 1 -type d 2>/dev/null | sort -r | head -1)
        if [[ -z "$backup_path" ]] || [[ ! -d "$backup_path" ]]; then
            show_ascii_critical "Резервные копии не найдены!" "Откат невозможен."
            return 1
        fi
    fi

    info "Восстановление из: ${backup_path}"

    if ! confirm "Выполнить откат?"; then
        return 0
    fi

    # sshd_config
    if [[ -f "${backup_path}/sshd_config.bak" ]]; then
        cp "${backup_path}/sshd_config.bak" /etc/ssh/sshd_config
        systemctl restart sshd 2>/dev/null || true
        success "sshd_config восстановлен и SSHD перезапущен."
    fi

    # UFW
    for f in ufw.conf user.rules user6.rules; do
        [[ -f "${backup_path}/${f}.bak" ]] && cp "${backup_path}/${f}.bak" "/etc/ufw/${f}"
    done
    if [[ -f "${backup_path}/ufw.conf.bak" ]]; then
        systemctl restart ufw 2>/dev/null || true
        success "Правила UFW восстановлены."
    fi

    # fail2ban
    if [[ -f "${backup_path}/jail.local.bak" ]]; then
        cp "${backup_path}/jail.local.bak" /etc/fail2ban/jail.local
        systemctl restart fail2ban 2>/dev/null || true
        success "Конфигурация fail2ban восстановлена."
    fi

    # shadow
    if [[ -f "${backup_path}/shadow.bak" ]]; then
        if confirm "Восстановить /etc/shadow (отмена блокировки root)?" "y"; then
            cp "${backup_path}/shadow.bak" /etc/shadow
            chown root:shadow /etc/shadow && chmod 640 /etc/shadow
            success "/etc/shadow восстановлен."
        fi
    fi

    # passwd
    if [[ -f "${backup_path}/passwd.bak" ]]; then
        if confirm "Восстановить /etc/passwd (возврат shell)?" "y"; then
            cp "${backup_path}/passwd.bak" /etc/passwd
            success "/etc/passwd восстановлен."
        fi
    fi

    # AIDE
    if [[ -f "${backup_path}/aide.conf.bak" ]]; then
        cp "${backup_path}/aide.conf.bak" /etc/aide/aide.conf
        success "Конфигурация AIDE восстановлена."
    fi

    # rkhunter
    if [[ -f "${backup_path}/rkhunter.conf.bak" ]]; then
        cp "${backup_path}/rkhunter.conf.bak" /etc/rkhunter.conf
        success "Конфигурация rkhunter восстановлена."
    fi

    # Пользователь
    if [[ -f "${backup_path}/state.txt" ]]; then
        local user_created username
        user_created=$(grep "^user_created=" "${backup_path}/state.txt" 2>/dev/null | tail -1 | cut -d= -f2-)
        username=$(grep "^username=" "${backup_path}/state.txt" 2>/dev/null | tail -1 | cut -d= -f2-)

        if [[ "$user_created" == "yes" ]] && [[ -n "$username" ]]; then
            if confirm "Удалить пользователя '${username}' созданного этим скриптом?" "n"; then
                userdel -r "$username" 2>/dev/null || true
                success "Пользователь '${username}' удалён."
            fi
        fi
    fi

    # Cron
    if confirm "Удалить cron-задачи созданные этим скриптом (aide, rkhunter)?" "n"; then
        rm -f /etc/cron.daily/aide-check /etc/cron.daily/rkhunter-check
        success "Cron-задачи удалены."
    fi

    echo ""
    success "Откат завершён."
    warn "Проверьте изменения и убедитесь что SSH работает."
}

# ======================================================================
# ФИНАЛЬНЫЙ ОТЧЁТ
# ======================================================================
show_report() {
    header "ОТЧЁТ О НАСТРОЙКЕ БЕЗОПАСНОСТИ"

    echo -e "${BOLD}Файл лога:${NC}           ${LOG_FILE}"
    echo -e "${BOLD}Директория бэкапов:${NC}  ${BACKUP_DIR}"
    echo ""

    echo -e "${BOLD}Выполненные действия:${NC}"
    echo ""

    if [[ -f "${BACKUP_DIR}/state.txt" ]]; then
        local val
        val=$(grep "^user_created=" "${BACKUP_DIR}/state.txt" 2>/dev/null | tail -1 | cut -d= -f2-); [[ "$val" == "yes" ]] && echo -e "  ${GREEN}[+]${NC} Создан новый пользователь с sudo"
        val=$(grep "^firewall_configured=" "${BACKUP_DIR}/state.txt" 2>/dev/null | tail -1 | cut -d= -f2-); [[ "$val" == "yes" ]] && echo -e "  ${GREEN}[+]${NC} Настроен UFW файрвол"
        val=$(grep "^fail2ban_configured=" "${BACKUP_DIR}/state.txt" 2>/dev/null | tail -1 | cut -d= -f2-); [[ "$val" == "yes" ]] && echo -e "  ${GREEN}[+]${NC} Установлен и настроен Fail2ban"
        val=$(grep "^new_ssh_port=" "${BACKUP_DIR}/state.txt" 2>/dev/null | tail -1 | cut -d= -f2-)
        [[ "$val" != "22" && -n "$val" ]] && echo -e "  ${GREEN}[+]${NC} Порт SSH изменён на ${val}"
        val=$(grep "^ssh_keys_configured=" "${BACKUP_DIR}/state.txt" 2>/dev/null | tail -1 | cut -d= -f2-); [[ "$val" == "yes" ]] && echo -e "  ${GREEN}[+]${NC} Настроена авторизация по SSH-ключам"
        val=$(grep "^auto_updates=" "${BACKUP_DIR}/state.txt" 2>/dev/null | tail -1 | cut -d= -f2-); [[ "$val" == "yes" ]] && echo -e "  ${GREEN}[+]${NC} Включены автоматические обновления"
        val=$(grep "^ssh_audit=" "${BACKUP_DIR}/state.txt" 2>/dev/null | tail -1 | cut -d= -f2-); [[ "$val" == "yes" ]] && echo -e "  ${GREEN}[+]${NC} Аудит уязвимостей SSH выполнен"
        val=$(grep "^aide_configured=" "${BACKUP_DIR}/state.txt" 2>/dev/null | tail -1 | cut -d= -f2-); [[ "$val" == "yes" ]] && echo -e "  ${GREEN}[+]${NC} Настроен AIDE (мониторинг целостности)"
        val=$(grep "^rkhunter_configured=" "${BACKUP_DIR}/state.txt" 2>/dev/null | tail -1 | cut -d= -f2-); [[ "$val" == "yes" ]] && echo -e "  ${GREEN}[+]${NC} Настроен rkhunter (обнаружение руткитов)"
        val=$(grep "^root_locked=" "${BACKUP_DIR}/state.txt" 2>/dev/null | tail -1 | cut -d= -f2-); [[ "$val" == "yes" ]] && echo -e "  ${GREEN}[+]${NC} Пароль root заблокирован"
    fi

    echo ""
    divider
    echo -e "${BOLD}${YELLOW}ВАЖНЫЕ НАПОМИНАНИЯ:${NC}"
    divider
    echo -e "  1. ${RED}ПРОВЕРИТЕ SSH в НОВОМ терминале${NC} перед закрытием этой сессии!"
    local ssh_port
    ssh_port=$(grep "^new_ssh_port=" "${BACKUP_DIR}/state.txt" 2>/dev/null | tail -1 | cut -d= -f2- || echo "22")
    if [[ "$ssh_port" != "22" ]]; then
        echo -e "     ${CYAN}ssh -p ${ssh_port} user@$(hostname -I 2>/dev/null | awk '{print $1}')${NC}"
    fi
    echo -e "  2. Сохраните SSH-ключ в безопасности!"
    echo -e "  3. Бэкапы: ${BACKUP_DIR}"
    echo -e "  4. Откат: ${CYAN}sudo bash ${SCRIPT_NAME} --rollback${NC}"
    echo -e "  5. Откат из конкретного бэкапа: ${CYAN}sudo bash ${SCRIPT_NAME} --rollback /path/to/backup${NC}"
    echo -e "  6. AIDE: выполняйте ${CYAN}aide --check${NC} или ждите cron"
    echo -e "  7. rkhunter: выполняйте ${CYAN}rkhunter --check --sk${NC} или ждите cron"
    divider
    echo ""
}

# ======================================================================
# ТЕСТЫ ИЗ МЕНЮ
# ======================================================================
run_tests() {
    header "ЗАПУСК ТЕСТОВ"

    info "Скачивание и запуск тестов обработки ошибок..."
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        show_ascii_dryrun "Тесты" \
            "Тесты будут скачаны и запущены" \
            "bash <(curl -s https://raw.githubusercontent.com/aplesovskih/vps-security/main/test-error-handling.sh)"
        return 0
    fi

    echo -e "${YELLOW}Выберите:${NC}"
    echo -e "  ${CYAN}[1]${NC} Тесты обработки ошибок (test-error-handling.sh)"
    echo -e "  ${CYAN}[2]${NC} Интеграционные тесты (test-integration.sh)"
    echo -e "  ${CYAN}[3]${NC} Оба набора тестов"
    echo ""

    local choice
    read -rp "$(echo -e "${BOLD}Ваш выбор: ${NC}")" choice

    case "$choice" in
        1)
            bash <(curl -s https://raw.githubusercontent.com/aplesovskih/vps-security/main/test-error-handling.sh) 2>/dev/null || {
                warn "Не удалось скачать тесты. Попробуйте вручную."
                info "Скачайте: curl -O https://raw.githubusercontent.com/aplesovskih/vps-security/main/test-error-handling.sh"
            }
            ;;
        2)
            bash <(curl -s https://raw.githubusercontent.com/aplesovskih/vps-security/main/test-integration.sh) 2>/dev/null || {
                warn "Не удалось скачать тесты. Попробуйте вручную."
            }
            ;;
        3)
            bash <(curl -s https://raw.githubusercontent.com/aplesovskih/vps-security/main/test-error-handling.sh) 2>/dev/null || true
            echo ""
            bash <(curl -s https://raw.githubusercontent.com/aplesovskih/vps-security/main/test-integration.sh) 2>/dev/null || true
            ;;
        *)
            error "Неверный выбор."
            ;;
    esac
}

# ======================================================================
# ГЛАВНОЕ МЕНЮ
# ======================================================================
show_menu() {
    header "Скрипт настройки безопасности VPS v${VERSION}"
    echo -e "${BOLD}Debian Linux | Интерактивная настройка${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC}   Создание пользователя"
    echo -e "  ${CYAN}[2]${NC}   Настройка UFW файрвола"
    echo -e "  ${CYAN}[3]${NC}   Установка и настройка Fail2ban"
    echo -e "  ${CYAN}[4]${NC}   Смена порта SSH"
    echo -e "  ${CYAN}[5]${NC}   SSH-ключи и ужесточение настроек"
    echo -e "  ${CYAN}[6]${NC}   Автоматические обновления безопасности"
    echo -e "  ${CYAN}[7]${NC}   Аудит уязвимостей OpenSSH"
    echo -e "  ${CYAN}[8]${NC}   AIDE — мониторинг целостности файлов (IDS)"
    echo -e "  ${CYAN}[9]${NC}   rkhunter — обнаружение руткитов"
    echo -e "  ${CYAN}[10]${NC}  Блокировка пароля root"
    echo ""
    echo -e "  ${CYAN}[D]${NC}   Демо-режим (dry-run) — показать что будет сделано"
    echo -e "  ${CYAN}[R]${NC}   Откат изменений"
    echo -e "  ${CYAN}[T]${NC}   Запустить тесты"
    echo -e "  ${CYAN}[A]${NC}   Запустить ВСЕ модули (интерактивно)"
    echo -e "  ${CYAN}[Q]${NC}   Выход"
    echo ""
    divider
}

# ======================================================================
# ТОЧКА ВХОДА
# ======================================================================
main() {
    check_root
    init_paths

    # Обработка аргументов
    case "${1:-}" in
        --rollback)
            do_rollback "${2:-}"
            exit $?
            ;;
        --dry-run)
            DRY_RUN=true
            echo ""
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}${CYAN}  ◎  РЕЖИМ ДЕМОНСТРАЦИИ (dry-run)                             ${NC}"
            echo -e "${BOLD}${CYAN}  Скрипт покажет что БУДЕТ сделано, но НИЧЕГО не изменит.      ${NC}"
            echo -e "${BOLD}${CYAN}  Для реальных изменений запустите без --dry-run              ${NC}"
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════════════${NC}"
            echo ""
            ;;
        --help|-h)
            echo ""
            echo "Использование: sudo bash $SCRIPT_NAME [опция]"
            echo ""
            echo "Опции:"
            echo "  (без опций)  Интерактивный режим"
            echo "  --dry-run    Демо-режим (ничего не меняет)"
            echo "  --rollback   Откат изменений"
            echo "  --rollback /path  Откат из конкретного бэкапа"
            echo "  --help       Показать справку"
            echo ""
            echo "Быстрый запуск:"
            echo "  curl -s https://raw.githubusercontent.com/aplesovskih/vps-security/main/vps-security.sh | sudo bash"
            echo ""
            exit 0
            ;;
    esac

    detect_os

    while true; do
        show_menu
        read -rp "$(echo -e "${BOLD}Ваш выбор: ${NC}")" choice

        case "${choice,,}" in
            1)  module_create_user ;;
            2)  module_firewall ;;
            3)  module_fail2ban ;;
            4)  module_ssh_port ;;
            5)  module_ssh_keys ;;
            6)  module_auto_updates ;;
            7)  module_ssh_audit ;;
            8)  module_aide ;;
            9)  module_rkhunter ;;
            10) module_lock_root ;;
            d|D)
                DRY_RUN=true
                echo ""
                echo -e "${BOLD}${CYAN}  ◎  ДЕМО-РЕЖИМ ВКЛЮЧЁН${NC}"
                echo -e "  Скрипт покажет что будет сделано, но ничего не изменит."
                echo ""
                ;;
            r|R)
                do_rollback ""
                ;;
            t|T)
                run_tests
                ;;
            a|A)
                module_create_user
                module_ssh_port
                module_ssh_keys
                module_fail2ban
                module_firewall
                module_auto_updates
                module_ssh_audit
                module_aide
                module_rkhunter
                module_lock_root
                show_report
                break
                ;;
            q|Q)
                echo ""
                info "До свидания. Будьте в безопасности!"
                break
                ;;
            *)
                error "Неверный выбор. Попробуйте снова."
                ;;
        esac
    done

    log "INFO" "Скрипт завершён."
}

main "$@"
