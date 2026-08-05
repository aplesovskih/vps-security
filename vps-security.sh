#!/usr/bin/env bash
# =============================================================================
# Скрипт настройки безопасности VPS для Debian
# Интерактивная настройка с откатом и логированием
# Версия: 2.1.0
# =============================================================================

# ponytail: при source (из тестов) только определяем функции, не выполняем main.
# BASH_SOURCE[0] пуст при запуске из stdin (curl | bash) — это тоже main.
if [[ -z "${BASH_SOURCE[0]}" || "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
fi

# --------------------------------------
# Константы
# --------------------------------------
readonly SCRIPT_VERSION="2.1.0"
# При curl | bash $0 = "bash" — для подсказок используем реальное имя скрипта
SCRIPT_NAME="$(basename "$0")"
case "$SCRIPT_NAME" in
    bash|sh|dash|-bash|-sh) SCRIPT_NAME="vps-security.sh" ;;
esac
readonly SCRIPT_NAME
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
    if [[ "$DRY_RUN" == "true" ]]; then
        # Демо-режим НЕ пишет в систему: лог и бэкапы — только во временную папку
        LOG_FILE="/tmp/vps-security-dryrun-$(date +%Y%m%d_%H%M%S).log"
        BACKUP_DIR="/tmp/vps-security-dryrun-$(date +%Y%m%d_%H%M%S)"
    else
        LOG_FILE="/var/log/vps-security-$(date +%Y%m%d_%H%M%S).log"
        BACKUP_DIR="/root/vps-security-backups/$(date +%Y%m%d_%H%M%S)"
    fi
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    mkdir -p "$BACKUP_DIR"
    # В бэкапах лежат копии /etc/shadow — закрываем доступ (только root)
    if [[ "$DRY_RUN" != "true" ]]; then
        chmod 700 "$BACKUP_DIR" 2>/dev/null || true
    fi
    log "INFO" "Скрипт запущен. PID=$$ Пользователь=root Версия=${SCRIPT_VERSION} Режим=$([[ "$DRY_RUN" == "true" ]] && echo dry-run || echo real)"
}

# --------------------------------------
# Утилиты вывода
# --------------------------------------
log() {
    local level="$1"; shift
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    [[ -n "${LOG_FILE:-}" ]] || return 0
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

    # Защита от инъекций: после подстановки переменных в команде не должно
    # оставаться $() или обратных кавычек (весь ввод пользователя валидируется)
    if [[ "$real_cmd" == *'$('* || "$real_cmd" == *'`'* ]]; then
        error "[${module}] Команда содержит опасную конструкцию. Пропуск."
        log "ERROR" "[${module}] Опасная команда заблокирована: ${real_cmd}"
        return 1
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
        read -rp "$(echo -e "${BOLD}Ваш выбор: ${NC}")" choice || return 0
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

validate_number() {
    local val="$1" name="$2"
    if ! [[ "$val" =~ ^[0-9]+$ ]] || (( val < 1 )); then
        error "${name} должен быть положительным числом (например: 3, 600, 3600)."
        return 1
    fi
    return 0
}

validate_ip_cidr() {
    local ip="$1" octets
    [[ -z "$ip" ]] && return 0
    if [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})(/([0-9]{1,2}))?$ ]]; then
        octets=("${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}")
        for octet in "${octets[@]}"; do
            if (( octet > 255 )); then
                error "Неверный IP: октет ${octet} больше 255. Примеры: 127.0.0.1 или 10.0.0.0/8"
                return 1
            fi
        done
        if [[ -n "${BASH_REMATCH[6]:-}" ]] && (( BASH_REMATCH[6] > 32 )); then
            error "Неверный префикс CIDR: /${BASH_REMATCH[6]} больше /32. Пример: 10.0.0.0/8"
            return 1
        fi
        return 0
    fi
    error "Неверный формат IP/CIDR: ${ip}. Примеры: 127.0.0.1 или 10.0.0.0/8"
    return 1
}

# ---- Сравнение версий OpenSSH (9.2p1 -> 9.2.1) ----
norm_ver() {
    local v="$1" parts i out=""
    v="${v//p/.}"
    IFS='.' read -ra parts <<< "$v"
    for ((i = 0; i < 3; i++)); do
        if [[ -n "${parts[$i]:-}" ]] && [[ "${parts[$i]}" =~ ^[0-9]+$ ]]; then
            out+="${parts[$i]}"
        else
            out+="0"
        fi
        (( i < 2 )) && out+="."
    done
    echo "$out"
}

ver_ge() { # $1 >= $2
    local a b
    a=$(norm_ver "$1"); b=$(norm_ver "$2")
    [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1)" == "$b" ]]
}

ver_le() { # $1 <= $2
    local a b
    a=$(norm_ver "$1"); b=$(norm_ver "$2")
    [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1)" == "$a" ]]
}

ver_lt() { # $1 < $2
    ! ver_ge "$1" "$2"
}

# --------------------------------------
# Бэкап и state
# --------------------------------------
backup_file() {
    local file="$1"
    # Демо-режим НЕ создаёт резервные копии — ничего не пишется на диск
    [[ "$DRY_RUN" == "true" ]] && return 0
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
        local result
        result=$(grep "^${key}=" "${BACKUP_DIR}/state.txt" 2>/dev/null | tail -1 | cut -d'=' -f2-) || true
        echo "${result:-$default}"
    else
        echo "$default"
    fi
}

# --------------------------------------
# Утилиты модулей
# --------------------------------------
set_sshd_option() {
    local key="$1" value="$2"
    local config="/etc/ssh/sshd_config"
    if [[ "$DRY_RUN" == "true" ]]; then
        show_ascii_dryrun "SSH" "${key} будет установлен в '${value}'" \
            "sed -i '/^#\\?${key}\\b/d; /^Include /!b; i\\${key} ${value}\\n' ${config}"
        return 0
    fi
    # ponytail: sshd uses first-match-wins — удалить все существующие строки (включая закомментированные)
    # и вставить ДО первого Include, чтобы значение не перезаписывалось файлами из sshd_config.d/
    sed -i "/^[# ]*${key}\\b/d" "$config"
    local include_line
    include_line=$(grep -n "^Include" "$config" 2>/dev/null | head -1 | cut -d: -f1)
    if [[ -n "$include_line" ]]; then
        sed -i "${include_line}i\\${key} ${value}" "$config"
    else
        echo "${key} ${value}" >> "$config"
    fi
}

# ponytail: handle_error убирает дубли error_handler + case $? во всех модулях.
# retry перезапускает модуль сам; skip сохраняет state (skip_value) и возвращает 1; menu возвращает 0.
handle_error() {
    local module="$1" msg="$2" module_func="$3" state_key="${4:-}" skip_value="${5:-no}"
    error_handler "$module" "$msg" "yes" "yes"
    case $? in
        2) "$module_func"; return 0 ;;
        1) [[ -n "$state_key" ]] && save_state "$state_key" "$skip_value"; return 1 ;;
        0) return 0 ;;
    esac
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
        read -rp "$(echo -e "${YELLOW}${prompt}${NC}")" yn || {
            [[ "$default" == "y" ]] && return 0 || return 1
        }
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
        read -rp "$(echo -e "${YELLOW}${prompt}${NC}")" port || return 1
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
        read -rp "$(echo -e "${YELLOW}Введите имя нового пользователя: ${NC}")" username || return 0
        if validate_username "$username"; then
            break
        fi
    done

    # Создание
    if ! dry_run_or_exec "Создание пользователя" \
        "Будет создан пользователь '${username}'" \
        "useradd -m -s /bin/bash '$username'"; then
        handle_error "Модуль 1" "Не удалось создать пользователя" module_create_user "user_created" || true
        return
    fi
    success "Пользователь '${username}' создан."

    # Пароль
    if confirm "Установить пароль для '${username}'?" "y"; then
        local password
        echo -e "${YELLOW}Введите пароль для '${username}':${NC}"
        read -rs password || true
        echo ""
        if [[ -n "$password" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                show_ascii_dryrun "Создание пользователя" "Будет установлен пароль для '${username}'" "echo '${username}:***' | chpasswd"
            else
                echo "${username}:${password}" | chpasswd
                success "Пароль установлен."
            fi
        else
            warn "Пароль пустой. Пропуск."
        fi
    fi

    # Sudo
    if confirm "Добавить '${username}' в группу sudo?" "y"; then
        if ! dry_run_or_exec "Создание пользователя" \
            "Пользователь '${username}' будет добавлен в группу sudo" \
            "usermod -aG sudo '$username'"; then
            if handle_error "Модуль 1" "Не удалось добавить в sudo" module_create_user; then
                return
            fi
        else
            success "Пользователь '${username}' добавлен в группу sudo."
        fi
    fi

    # Копирование конфигов
    for f in .bashrc .profile .bash_profile; do
        [[ -f "/root/${f}" ]] || continue
        dry_run_or_exec "Создание пользователя" \
            "Копирование ${f} в домашнюю директорию" \
            "cp /root/${f} /home/${username}/${f} && chown ${username}:${username} /home/${username}/${f}" || true
    done
    success "Конфигурации оболочки скопированы."

    # SSH-ключ
    if confirm "Сгенерировать SSH-ключ для '${username}'?" "y"; then
        local key_type
        while true; do
            read -rp "$(echo -e "${YELLOW}Тип ключа [ed25519/rsa]: ${NC}")" key_type || { key_type="ed25519"; break; }
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
            if [[ "$DRY_RUN" == "true" ]]; then
                success "SSH-ключ (${key_type}) будет сгенерирован для '${username}'."
                info "Публичный ключ будет доступен в: /home/${username}/.ssh/id_${key_type}.pub"
            else
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
            handle_error "Модуль 2" "Не удалось установить UFW" module_firewall "firewall_configured" || true
            return
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
        port=$(ask_port "Введите номер порта: ") || continue
        while true; do
            read -rp "$(echo -e "${YELLOW}Протокол [tcp/udp/оба]: ${NC}")" proto || { proto="tcp"; break; }
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
            handle_error "Модуль 3" "Не удалось установить Fail2ban" module_fail2ban "fail2ban_configured" || true
            return
        fi
        success "Fail2ban установлен."
    else
        info "Fail2ban уже установлен."
    fi

    backup_file "/etc/fail2ban/jail.local"

    local ssh_port
    ssh_port=$(load_state "new_ssh_port" "$ORIGINAL_SSH_PORT")

    local max_retry bantime findtime ignore_ip
    while true; do
        read -rp "$(echo -e "${YELLOW}Макс. неудачных попыток перед баном [3]: ${NC}")" max_retry || true
        max_retry="${max_retry:-3}"
        validate_number "$max_retry" "Макс. попыток" && break
    done

    while true; do
        read -rp "$(echo -e "${YELLOW}Длительность блокировки в секундах [3600]: ${NC}")" bantime || true
        bantime="${bantime:-3600}"
        validate_number "$bantime" "Время блокировки" && break
    done

    while true; do
        read -rp "$(echo -e "${YELLOW}Окно подсчёта попыток в секундах [600]: ${NC}")" findtime || true
        findtime="${findtime:-600}"
        validate_number "$findtime" "Окно попыток" && break
    done

    while true; do
        read -rp "$(echo -e "${YELLOW}Игнорировать IP (например 127.0.0.1 или пусто): ${NC}")" ignore_ip || true
        validate_ip_cidr "$ignore_ip" && break
    done

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
    current_port=$(grep -E "^[# ]*Port\s" /etc/ssh/sshd_config 2>/dev/null | grep -v "^[[:space:]]*#" | head -1 | awk '{print $2}') || true
    current_port="${current_port:-22}"
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
    if ! new_port=$(ask_port "Введите новый порт SSH: "); then
        warn "Ввод отменён. Порт SSH не изменён."
        save_state "new_ssh_port" "$current_port"
        return 0
    fi

    if [[ -z "$new_port" || "$new_port" == "$current_port" ]]; then
        warn "Новый порт совпадает с текущим. Пропуск."
        save_state "new_ssh_port" "$current_port"
        return 0
    fi

    backup_file "/etc/ssh/sshd_config"

    # Изменение
    if ! dry_run_or_exec "Смена SSH порта" \
        "Порт SSH изменён с ${current_port} на ${new_port}" \
        "sed -i '/^\s*Port\s/ s/^/#/' /etc/ssh/sshd_config && echo 'Port ${new_port}' >> /etc/ssh/sshd_config"; then
        handle_error "Модуль 4" "Не удалось изменить sshd_config" module_ssh_port "new_ssh_port" "$current_port" || true
        return
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
    echo ""
    warn "После перезапуска SSHD:"
    echo "  1. Откройте НОВЫЙ терминал"
    echo "  2. Подключитесь: ssh -p ${new_port} user@$(hostname -I 2>/dev/null | awk '{print $1}')"
    echo "  3. Если не получится — старый порт ${current_port} ещё работает"
    echo ""
    show_ascii_warning "Текущая SSH-сессия НЕ прервётся при перезапуске SSHD. После перезапуска вход будет возможен только на новом порту ${new_port}."
    if confirm "Перезапустить SSHD сейчас? (текущая сессия использует порт ${current_port} - НЕ прервётся)" "y"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            show_ascii_dryrun "Смена SSH порта" "SSHD будет перезапущен" "systemctl restart ssh || systemctl restart sshd"
        else
            if systemctl restart ssh || systemctl restart sshd; then
                sleep 2
                success "SSHD перезапущен на порту ${new_port}."
                echo ""
                warn "Подключиться через: ssh -p ${new_port} user@$(hostname -I 2>/dev/null | awk '{print $1}')"
                warn "Если не получится — попробуйте порт ${current_port}"
            else
                warn "Не удалось перезапустить SSHD. Перезапустите вручную: systemctl restart ssh"
            fi
        fi
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
            read -rp "$(echo -e "${YELLOW}Тип ключа [ed25519/rsa]: ${NC}")" key_type || { key_type="ed25519"; break; }
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
        read -rp "$(echo -e "${YELLOW}> ${NC}")" pubkey || true
        pubkey="${pubkey//[$'\r\n']/}"

        if [[ -n "$pubkey" ]] && ! [[ "$pubkey" =~ ^(ssh-ed25519|ssh-rsa|ssh-dss|ecdsa-sha2-|sk-ssh-ed25519|sk-ecdsa-sha2-) ]]; then
            error "Не похоже на SSH-ключ (ожидается ssh-ed25519/ssh-rsa...). Пропуск."
            pubkey=""
        fi

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
        read -rp "$(echo -e "${YELLOW}Имя пользователя: ${NC}")" target_user || true

        if [[ -n "$target_user" ]] && ! id "$target_user" &>/dev/null; then
            error "Пользователь '${target_user}' не существует."
        elif [[ -n "$target_user" ]]; then
            echo -e "${YELLOW}Вставьте публичный ключ:${NC}"
            local pubkey2
            read -rp "> " pubkey2 || true
            pubkey2="${pubkey2//[$'\r\n']/}"

            if [[ -n "$pubkey2" ]] && ! [[ "$pubkey2" =~ ^(ssh-ed25519|ssh-rsa|ssh-dss|ecdsa-sha2-|sk-ssh-ed25519|sk-ecdsa-sha2-) ]]; then
                error "Не похоже на SSH-ключ (ожидается ssh-ed25519/ssh-rsa...). Пропуск."
                pubkey2=""
            fi

            if [[ -n "$pubkey2" ]]; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    show_ascii_dryrun "SSH-ключи" "Ключ будет добавлен пользователю ${target_user}" "echo key >> /home/${target_user}/.ssh/authorized_keys"
                else
                    local home_dir
                    home_dir=$(getent passwd "$target_user" | cut -d: -f6)
                    [[ -z "$home_dir" ]] && home_dir="/home/${target_user}"
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
        set_sshd_option "PermitRootLogin" "no"
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
            set_sshd_option "PasswordAuthentication" "no"
            success "PasswordAuthentication установлен в 'no'."
        fi
    fi

    local max_tries
    while true; do
        read -rp "$(echo -e "${YELLOW}Макс. попыток аутентификации [3]: ${NC}")" max_tries || true
        max_tries="${max_tries:-3}"
        validate_number "$max_tries" "Макс. попыток" && break
    done
    set_sshd_option "MaxAuthTries" "$max_tries"
    success "MaxAuthTries установлен в ${max_tries}."

    if confirm "Отключить проброс X11?" "y"; then
        set_sshd_option "X11Forwarding" "no"
        success "X11Forwarding установлен в 'no'."
    fi

    set_sshd_option "PermitEmptyPasswords" "no"
    success "PermitEmptyPasswords установлен в 'no'."

    # --- Расширенный харденинг ---
    info "Дополнительное ужесточение настроек SSH..."

    # LogLevel VERBOSE — детальное логирование входов
    set_sshd_option "LogLevel" "VERBOSE"
    success "LogLevel установлен в VERBOSE (детальные логи входов)."

    # KbdInteractiveAuthentication no — защита от фишинга паролей
    set_sshd_option "KbdInteractiveAuthentication" "no"
    success "KbdInteractiveAuthentication установлен в 'no'."

    # MaxSessions — ограничение одновременных сессий
    set_sshd_option "MaxSessions" "5"
    success "MaxSessions установлен в 5."

    # ClientAlive — автоматический разрыв неактивных сессий
    set_sshd_option "ClientAliveInterval" "300"
    set_sshd_option "ClientAliveCountMax" "2"
    success "Неактивные сессии будут разрываться (ClientAliveInterval=300, CountMax=2)."

    # AllowUsers — доступ только с указанных IP
    if confirm "Ограничить вход по IP (AllowUsers пользователь@IP)? Блокирует все остальные адреса" "n"; then
        local allow_users
        read -rp "$(echo -e "${YELLOW}Список 'пользователь@IP' через пробел (например: admin@1.2.3.4): ${NC}")" allow_users || true

        # Валидация каждого токена: имя или имя@IP
        local valid=true token
        for token in $allow_users; do
            if ! [[ "$token" =~ ^[A-Za-z0-9._-]+(@[0-9A-Za-z:./_-]+)?$ ]]; then
                valid=false
                error "Недопустимый токен AllowUsers: '${token}'"
            fi
        done

        if [[ -n "$allow_users" ]] && [[ "$valid" == "true" ]]; then
            set_sshd_option "AllowUsers" "$allow_users"
            success "AllowUsers: ${allow_users}"
            warn "Вход с других IP теперь будет отклонён! Проверьте доступ в НОВОМ терминале, не закрывая текущий."
        else
            warn "AllowUsers не применён (пустой ввод или неверный формат)."
        fi
    fi

    # Banner — предупреждение при входе
    if confirm "Добавить баннер предупреждения при входе по SSH?" "n"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            show_ascii_dryrun "SSH-ключи" "Будет создан /etc/ssh/banner.txt и включён Banner" "cat > /etc/ssh/banner.txt && set_sshd_option Banner"
        else
            cat > /etc/ssh/banner.txt <<'BANNER'
======================================================================
  ВНИМАНИЕ! Доступ только для авторизованных пользователей.
  Все действия на этом сервере протоколируются и могут быть
  использованы в качестве доказательств.
======================================================================
BANNER
            set_sshd_option "Banner" "/etc/ssh/banner.txt"
            success "Баннер создан и включён."
        fi
    fi

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

    show_ascii_warning "Текущая SSH-сессия не прервётся при перезапуске SSHD. Новые подключения будут работать по обновлённым правилам."
    if confirm "Перезапустить SSHD для применения изменений?" "y"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            show_ascii_dryrun "SSH-ключи" "SSHD будет перезапущен" "systemctl restart ssh || systemctl restart sshd"
        else
            if systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null; then
                success "SSHD перезапущен."
            else
                warn "Не удалось перезапустить SSHD. Перезапустите вручную: systemctl restart ssh"
            fi
        fi
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
        handle_error "Модуль 6" "Не удалось установить unattended-upgrades" module_auto_updates "auto_updates" || true
        return
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

    local ver_num
    ver_num=$(echo "$ssh_version" | grep -oP 'OpenSSH_\K[0-9]+(\.[0-9]+)*p?[0-9]*' || echo "0")
    ver_num="${ver_num:-0}"
    local ver_unknown=false
    [[ "$ver_num" == "0" ]] && ver_unknown=true

    echo ""
    divider
    info "ПРОВЕРКИ УЯЗВИМОСТЕЙ"
    divider
    echo ""

    local issues=0
    local sshd_conf="/etc/ssh/sshd_config"

    if [[ "$ver_unknown" == "true" ]]; then
        warn "  [!] Не удалось определить версию OpenSSH — проверки CVE пропущены."
        warn "      Проверьте вручную: ssh -V"
    else
        # CVE-2023-38408 (уязвимы версии < 9.3p2)
        if ver_lt "$ver_num" "9.3p2"; then
            warn "  [!] CVE-2023-38408 (удалённое выполнение кода через ssh-agent)"
            warn "      Затронутые версии: OpenSSH < 9.3p2"
            warn "      Исправление: обновить до OpenSSH >= 9.3p2"
            ((issues++)) || true
        fi

        # CVE-2023-48795 (Terrapin, < 9.6p1)
        if ver_lt "$ver_num" "9.6p1"; then
            warn "  [!] CVE-2023-48795 (Terrapin — атака на префикс ключевого обмена)"
            warn "      Затронутые версии: OpenSSH < 9.6p1"
            warn "      Исправление: обновить до OpenSSH >= 9.6p1"
            ((issues++)) || true
        fi

        # CVE-2024-6387 (regreSSHion, 8.5p1 - 9.7p1 на glibc)
        if ver_ge "$ver_num" "8.5p1" && ver_le "$ver_num" "9.7p1"; then
            warn "  [!] CVE-2024-6387 (regreSSHion — гонка данных)"
            warn "      Затронутые версии: OpenSSH 8.5p1 - 9.7p1 (glibc)"
            warn "      Исправление: обновить до OpenSSH >= 9.8p1"
            ((issues++)) || true
        fi
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
            warn "  [!] LoginGraceTime = ${grace_time}с (рекомендуется: 30с или менее)"
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
                    "блок Security Hardening будет вставлен в sshd_config перед Include"
            else
                backup_file "/etc/ssh/sshd_config"
                local block="

# === Security Hardening (vps-security.sh) ===
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
KexAlgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group18-sha512,diffie-hellman-group16-sha512
LoginGraceTime 30
# === End Security Hardening ==="

                # sshd: first-match-wins — вставляем блок ДО Include, чтобы настройки
                # не перекрывались файлами из /etc/ssh/sshd_config.d/
                sed -i '/# === Security Hardening (vps-security.sh) ===/,/# === End Security Hardening ===/d' "$sshd_conf"
                local include_line tmp_file
                include_line=$(grep -n "^Include" "$sshd_conf" 2>/dev/null | head -1 | cut -d: -f1)
                if [[ -n "$include_line" ]]; then
                    tmp_file=$(mktemp)
                    head -n "$(( include_line - 1 ))" "$sshd_conf" > "$tmp_file"
                    printf '%s\n' "$block" >> "$tmp_file"
                    tail -n "+${include_line}" "$sshd_conf" >> "$tmp_file"
                    local orig_mode
                    orig_mode=$(stat -c %a "$sshd_conf" 2>/dev/null || echo 644)
                    mv "$tmp_file" "$sshd_conf"
                    chmod "$orig_mode" "$sshd_conf"
                else
                    echo "$block" >> "$sshd_conf"
                fi
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
# МОДУЛЬ 8: Блокировка root
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
        handle_error "Модуль 10" "Не удалось заблокировать пароль root" module_lock_root "root_locked" || true
        return
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
    success "Модуль 8 завершён."
}

# ======================================================================
# МОДУЛЬ 9: Безопасные монтирования /tmp и /dev/shm
# ======================================================================
module_mount_hardening() {
    header "МОДУЛЬ 9: Безопасные монтирования (/tmp, /dev/shm)"

    if ! confirm "Настроить безопасные монтирования /tmp и /dev/shm?"; then
        info "Пропуск безопасных монтирований."
        save_state "mount_hardening" "no"
        return 0
    fi

    show_ascii_warning "Будут добавлены опции nodev,nosuid,noexec (запрет запуска файлов из /tmp)."
    warn "Некоторые приложения, выполняющие файлы из /tmp, могут перестать работать!"

    # Текущее состояние
    info "Текущие опции монтирования:"
    if command -v findmnt &>/dev/null; then
        findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS /tmp /dev/shm 2>/dev/null | column -t 2>/dev/null || true
    else
        echo "  (findmnt недоступен)"
    fi
    echo ""

    backup_file "/etc/fstab"

    # --- /dev/shm ---
    local shm_entry="tmpfs /dev/shm tmpfs defaults,nodev,nosuid,noexec,nofail,mode=1777 0 0"
    info "Настройка /dev/shm..."
    if grep -qE "^tmpfs[[:space:]]+/dev/shm" /etc/fstab 2>/dev/null; then
        info "/dev/shm уже настроен в /etc/fstab."
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            show_ascii_dryrun "Монтирования" "Запись для /dev/shm будет добавлена в /etc/fstab" "echo '${shm_entry}' >> /etc/fstab"
        else
            echo "$shm_entry" >> /etc/fstab
            success "/dev/shm: добавлена запись в fstab с nodev,nosuid,noexec (nofail)."
            warn "Применится после перезагрузки (немедленный remount может прервать активные приложения)."
        fi
    fi

    # --- /tmp ---
    info "Настройка /tmp..."
    local tmp_fs
    tmp_fs=$(findmnt -n -o FSTYPE /tmp 2>/dev/null || echo "")

    if [[ "$tmp_fs" == "tmpfs" ]]; then
        # /tmp — tmpfs, управляемый systemd (tmp.mount): применяем drop-in
        info "/tmp на tmpfs (systemd) — применяем drop-in для tmp.mount."
        if [[ "$DRY_RUN" == "true" ]]; then
            show_ascii_dryrun "Монтирования" "Будет создан /etc/systemd/system/tmp.mount.d/security.conf" "cat > /etc/systemd/system/tmp.mount.d/security.conf"
        else
            mkdir -p /etc/systemd/system/tmp.mount.d
            cat > /etc/systemd/system/tmp.mount.d/security.conf <<'CONF'
[Mount]
Options=mode=1777,nodev,nosuid,noexec
CONF
            systemctl daemon-reload 2>/dev/null || true
            success "/tmp: systemd drop-in применён (nodev,nosuid,noexec)."
            warn "Применится после перезагрузки."
        fi
    elif grep -qE "[[:space:]]/tmp[[:space:]]" /etc/fstab 2>/dev/null; then
        # /tmp — раздел на диске с записью в fstab: добавляем опции к существующей строке
        warn "/tmp — раздел на диске. Добавляем опции к строке fstab (без дублирования)."
        if [[ "$DRY_RUN" == "true" ]]; then
            show_ascii_dryrun "Монтирования" "Опции nodev,nosuid,noexec будут добавлены к строке /tmp в fstab" "awk-обработка строки /tmp в /etc/fstab"
        else
            awk 'BEGIN{OFS="\t"} $2=="/tmp" && $4 !~ /noexec/ { $4=$4",nodev,nosuid,noexec" } {print}' /etc/fstab > /tmp/fstab.new && mv /tmp/fstab.new /etc/fstab
            success "/tmp: опции добавлены к строке fstab (nodev,nosuid,noexec)."
            warn "Применится после перезагрузки."
        fi
    else
        warn "/tmp не найден в fstab и не является tmpfs — пропуск."
    fi

    save_state "mount_hardening" "yes"
    success "Модуль 9 завершён."
    warn "Перезагрузите сервер, чтобы применить опции монтирования."
}

# ======================================================================
# МОДУЛЬ 10: CrowdSec — коллективная защита
# ======================================================================
module_crowdsec() {
    header "МОДУЛЬ 10: CrowdSec (коллективная защита от атак)"

    if ! confirm "Установить CrowdSec (совместная защита от брутфорса и атак)?"; then
        info "Пропуск CrowdSec."
        save_state "crowdsec_installed" "no"
        return 0
    fi

    info "CrowdSec — Fail2ban нового поколения: общая база угроз сообщества."
    info "IP, атакующие другие серверы по всему миру, блокируются и у вас ещё до атаки."

    # Выбор bouncer: при активном UFW (nftables-бэкенд) конфликт возможен — используем iptables
    local bouncer_pkg="crowdsec-firewall-bouncer-nftables"
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        warn "Обнаружен активный UFW. Используем iptables-bouncer во избежание конфликта правил."
        bouncer_pkg="crowdsec-firewall-bouncer-iptables"
    fi

    # Установка
    if command -v cscli &>/dev/null; then
        info "CrowdSec уже установлен."
    else
        info "Установка CrowdSec и firewall-bouncer..."
        if ! dry_run_or_exec "CrowdSec" \
            "CrowdSec будет установлен (официальный репозиторий)" \
            "curl -s https://install.crowdsec.net | sh"; then
            handle_error "Модуль 10" "Не удалось добавить репозиторий CrowdSec" module_crowdsec "crowdsec_installed" || true
            return
        fi
        if ! dry_run_or_exec "CrowdSec" \
            "Пакеты crowdsec и ${bouncer_pkg} будут установлены" \
            "apt-get update -qq && apt-get install -y -qq crowdsec ${bouncer_pkg}"; then
            handle_error "Модуль 10" "Не удалось установить CrowdSec" module_crowdsec "crowdsec_installed" || true
            return
        fi
        success "CrowdSec установлен."
    fi

    # Активация сценариев и статус
    if [[ "$DRY_RUN" == "true" ]]; then
        show_ascii_dryrun "CrowdSec" "Будут активированы сценарии ssh-bf и проверен статус" "cscli collections install crowdsecurity/sshd"
    else
        cscli collections install crowdsecurity/sshd 2>/dev/null || true
        systemctl enable --now crowdsec 2>/dev/null || true
        systemctl restart crowdsec 2>/dev/null || true
        systemctl restart crowdsec-firewall-bouncer 2>/dev/null || true

        echo ""
        info "Статус CrowdSec:"
        cscli decisions list 2>/dev/null | head -15 || true
        echo ""
        info "Активные сценарии:"
        cscli parsers list 2>/dev/null | head -10 || true
    fi

    save_state "crowdsec_installed" "yes"
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

    # Монтирования /tmp и /dev/shm: убираем записи из fstab
    if [[ -f "${backup_path}/fstab.bak" ]]; then
        if confirm "Убрать безопасные монтирования (восстановить fstab)?" "n"; then
            cp "${backup_path}/fstab.bak" /etc/fstab
            rm -f /etc/systemd/system/tmp.mount.d/security.conf 2>/dev/null || true
            systemctl daemon-reload 2>/dev/null || true
            success "/etc/fstab восстановлен, drop-in /tmp удалён."
            warn "Применится после перезагрузки."
        fi
    fi

    # CrowdSec: удаление пакетов
    if [[ -f "${backup_path}/state.txt" ]]; then
        local cs_installed
        cs_installed=$(grep "^crowdsec_installed=" "${backup_path}/state.txt" 2>/dev/null | tail -1 | cut -d= -f2-)
        if [[ "$cs_installed" == "yes" ]]; then
            if confirm "Удалить CrowdSec (пакеты crowdsec и bouncer)?" "n"; then
                systemctl stop crowdsec 2>/dev/null || true
                apt-get remove -y -qq crowdsec crowdsec-firewall-bouncer-nftables crowdsec-firewall-bouncer-iptables 2>/dev/null || true
                success "CrowdSec удалён."
            fi
        fi
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

    # Читаем state.txt один раз в ассоциативный массив вместо 10 grep
    declare -A state=()
    if [[ -f "${BACKUP_DIR}/state.txt" ]]; then
        while IFS='=' read -r key val; do
            state["$key"]="$val"
        done < "${BACKUP_DIR}/state.txt"
    fi

    local line key desc
    for line in \
        "user_created|Создан новый пользователь с sudo" \
        "firewall_configured|Настроен UFW файрвол" \
        "fail2ban_configured|Установлен и настроен Fail2ban" \
        "ssh_keys_configured|Настроена авторизация по SSH-ключам" \
        "auto_updates|Включены автоматические обновления" \
        "ssh_audit|Аудит уязвимостей SSH выполнен" \
        "root_locked|Пароль root заблокирован" \
        "mount_hardening|Настроены безопасные монтирования /tmp и /dev/shm" \
        "crowdsec_installed|Установлен CrowdSec"; do
        key="${line%%|*}"
        desc="${line#*|}"
        [[ "${state[$key]:-}" == "yes" ]] && echo -e "  ${GREEN}[+]${NC} ${desc}"
    done

    local ssh_port="${state[new_ssh_port]:-22}"
    [[ -n "$ssh_port" && "$ssh_port" != "22" ]] && echo -e "  ${GREEN}[+]${NC} Порт SSH изменён на ${ssh_port}"

    echo ""
    divider
    echo -e "${BOLD}${YELLOW}ВАЖНЫЕ НАПОМИНАНИЯ:${NC}"
    divider
    echo -e "  1. ${RED}ПРОВЕРИТЕ SSH в НОВОМ терминале${NC} перед закрытием этой сессии!"
    if [[ "$ssh_port" != "22" ]]; then
        echo -e "     ${CYAN}ssh -p ${ssh_port} user@$(hostname -I 2>/dev/null | awk '{print $1}')${NC}"
    fi
    echo -e "  2. Сохраните SSH-ключ в безопасности!"
    echo -e "  3. Бэкапы: ${BACKUP_DIR}"
    echo -e "  4. Откат: ${CYAN}bash ${SCRIPT_NAME} --rollback${NC}"
    echo -e "  5. Откат из конкретного бэкапа: ${CYAN}bash ${SCRIPT_NAME} --rollback /path/to/backup${NC}"
    divider
    echo ""
}

# ======================================================================
# ГЛАВНОЕ МЕНЮ
# ======================================================================
show_menu() {
    header "Скрипт настройки безопасности VPS v${SCRIPT_VERSION}"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${BOLD}${CYAN}  ◎  РЕЖИМ: ДЕМОНСТРАЦИИ (dry-run) — ничего не будет изменено${NC}"
    else
        echo -e "${BOLD}${YELLOW}  ⚠  РЕЖИМ: РЕАЛЬНЫЙ — все изменения будут применены${NC}"
    fi
    echo -e "${BOLD}Debian Linux | Интерактивная настройка${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC}   Создание пользователя"
    echo -e "  ${CYAN}[2]${NC}   Настройка UFW файрвола"
    echo -e "  ${CYAN}[3]${NC}   Установка и настройка Fail2ban"
    echo -e "  ${CYAN}[4]${NC}   Смена порта SSH"
    echo -e "  ${CYAN}[5]${NC}   SSH-ключи и ужесточение настроек"
    echo -e "  ${CYAN}[6]${NC}   Автоматические обновления безопасности"
    echo -e "  ${CYAN}[7]${NC}   Аудит уязвимостей OpenSSH"
    echo -e "  ${CYAN}[8]${NC}   Блокировка пароля root"
    echo -e "  ${CYAN}[9]${NC}   Безопасные монтирования (/tmp, /dev/shm)"
    echo -e "  ${CYAN}[10]${NC}  CrowdSec — коллективная защита"
    echo ""
    echo -e "  ${CYAN}[D]${NC}   Переключить режим (демо/реальный)"
    echo -e "  ${CYAN}[R]${NC}   Откат изменений"
    echo -e "  ${CYAN}[A]${NC}   Запустить ВСЕ модули (интерактивно)"
    echo -e "  ${CYAN}[Q]${NC}   Выход"
    echo ""
    divider
}

# ======================================================================
# ТОЧКА ВХОДА
# ======================================================================
main() {
    # Справка доступна без root и без tty
    case "${1:-}" in
        --help|-h)
            echo ""
            echo "Использование: bash $SCRIPT_NAME [опция]"
            echo ""
            echo "Опции:"
            echo "  (без опций)  Интерактивный режим"
            echo "  --dry-run    Демо-режим (ничего не меняет)"
            echo "  --rollback   Откат изменений"
            echo "  --rollback /path  Откат из конкретного бэкапа"
            echo "  --help       Показать справку"
            echo ""
            echo "Быстрый запуск:"
            echo "  curl -s https://raw.githubusercontent.com/aplesovskih/vps-security/main/vps-security.sh | bash"
            echo ""
            exit 0
            ;;
    esac

    # Если stdin — pipe (curl | bash), переключить на терминал.
    # Если терминала нет (cron/CI/docker) — понятная ошибка вместо падения
    if [[ ! -t 0 ]]; then
        if ( exec </dev/tty ) 2>/dev/null; then
            exec </dev/tty
        else
            show_ascii_critical "Нет интерактивного терминала (tty)!" \
                "Запустите скрипт в интерактивном терминале: bash ${SCRIPT_NAME}"
            exit 1
        fi
    fi

    # Демо-режим безопасен и без root: пишет только в /tmp
    if [[ "${1:-}" != "--dry-run" ]]; then
        check_root
    fi

    # --dry-run ДО init_paths: демо-режим пишет лог/бэкапы только в /tmp
    if [[ "${1:-}" == "--dry-run" ]]; then
        DRY_RUN=true
        echo ""
        echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}${CYAN}  ◎  РЕЖИМ ДЕМОНСТРАЦИИ (dry-run)                             ${NC}"
        echo -e "${BOLD}${CYAN}  Скрипт покажет что БУДЕТ сделано, но НИЧЕГО не изменит.      ${NC}"
        echo -e "${BOLD}${CYAN}  Для реальных изменений запустите без --dry-run              ${NC}"
        echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════════════${NC}"
        echo ""
    fi

    init_paths

    case "${1:-}" in
        --rollback)
            do_rollback "${2:-}"
            exit $?
            ;;
    esac

    detect_os

    while true; do
        show_menu
        read -rp "$(echo -e "${BOLD}Ваш выбор: ${NC}")" choice || {
            echo ""
            error "Нет доступного ввода. Используйте: bash $SCRIPT_NAME"
            exit 1
        }

        case "${choice,,}" in
            1)  module_create_user || true ;;
            2)  module_firewall || true ;;
            3)  module_fail2ban || true ;;
            4)  module_ssh_port || true ;;
            5)  module_ssh_keys || true ;;
            6)  module_auto_updates || true ;;
            7)  module_ssh_audit || true ;;
            8)  module_lock_root || true ;;
            9)  module_mount_hardening || true ;;
            10) module_crowdsec || true ;;
            d|D)
                if [[ "$DRY_RUN" == "true" ]]; then
                    DRY_RUN=false
                    echo ""
                    echo -e "${BOLD}${YELLOW}  ⚠  РЕАЛЬНЫЙ РЕЖИМ ВКЛЮЧЁН${NC}"
                    echo -e "  Все изменения будут применены к системе."
                    echo ""
                else
                    DRY_RUN=true
                    echo ""
                    echo -e "${BOLD}${CYAN}  ◎  ДЕМО-РЕЖИМ ВКЛЮЧЁН${NC}"
                    echo -e "  Скрипт покажет что будет сделано, но ничего не изменит."
                    echo ""
                fi
                ;;
            r|R)
                do_rollback "" || true
                ;;
            a|A)
                module_create_user || true
                module_ssh_port || true
                module_ssh_keys || true
                module_fail2ban || true
                module_firewall || true
                module_auto_updates || true
                module_ssh_audit || true
                module_lock_root || true
                module_mount_hardening || true
                module_crowdsec || true
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
    exit 0
}

# ponytail: запускаем main только при прямом запуске; при source только определения
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
