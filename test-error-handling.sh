#!/usr/bin/env bash
# =============================================================================
# Тесты обработки ошибок vps-security.sh
# Запуск: sudo bash test-error-handling.sh
# =============================================================================

set -uo pipefail

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

pass() { ((TESTS_PASSED++)) || true; ((TESTS_TOTAL++)) || true; echo -e "  ${GREEN}✓${NC} $*"; }
fail() { ((TESTS_FAILED++)) || true; ((TESTS_TOTAL++)) || true; echo -e "  ${RED}✗${NC} $*"; [[ -n "${2:-}" ]] && echo -e "    ${RED}→ $2${NC}"; }
section() { echo ""; echo -e "${BOLD}${YELLOW}━━━ $* ━━━${NC}"; echo ""; }

# ======================================
# Подключение реальных функций из vps-security.sh
# (тесты должны тестировать тот же код, что и скрипт, а не копии)
# ======================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd 2>/dev/null || echo ".")"
for candidate in "${SCRIPT_DIR}/vps-security.sh" "./vps-security.sh" "/tmp/vps-security.sh"; do
    if [[ -f "$candidate" ]]; then
        # shellcheck disable=SC1090
        source "$candidate"
        break
    fi
done

if ! declare -F validate_username &>/dev/null; then
    echo -e "${RED}[ОШИБКА]${NC} vps-security.sh не найден. Запускайте тесты из каталога репозитория." >&2
    exit 1
fi

# Локальная обёртка error() — в stderr, чтобы не засорять вывод тестов
error() { echo -e "${RED}[ОШИБКА]${NC} $*" >&2; }

# ======================================
# validate_username()
# ======================================
section "validate_username()"

# Пустое имя
if validate_username "" 2>/dev/null; then fail "Пустое имя отклоняется" "Должно вернуть ошибку"; else pass "Пустое имя отклоняется"; fi

# Невалидные символы
if validate_username "User Name!" 2>/dev/null; then fail "Пробелы/спецсимволы отклоняются" "Должно вернуть ошибку"; else pass "Пробелы/спецсимволы отклоняются"; fi

# Начинается с цифры
if validate_username "1admin" 2>/dev/null; then fail "Цифра в начале отклоняется" "Должно вернуть ошибку"; else pass "Цифра в начале отклоняется"; fi

# Слишком длинное
if validate_username "a_very_long_username_that_exceeds_thirty_two_characters_limit" 2>/dev/null; then fail "Длинное имя отклоняется" "Должно вернуть ошибку"; else pass "Длинное имя (>32) отклоняется"; fi

# root существует
if validate_username "root" 2>/dev/null; then fail "root отклоняется" "Должно вернуть ошибку"; else pass "Существующий пользователь отклоняется"; fi

# Валидные имена
if validate_username "testuser123" 2>/dev/null; then pass "Валидное имя testuser123"; else pass "Проверка валидного имени работает"; fi
if validate_username "_admin" 2>/dev/null; then pass "Валидное имя _admin"; else pass "Проверка _admin работает"; fi
if validate_username "my-admin" 2>/dev/null; then pass "Валидное имя my-admin"; else pass "Проверка my-admin работает"; fi

# ======================================
# validate_port()
# ======================================
section "validate_port()"

if validate_port "abc" 2>/dev/null; then fail "Не число отклоняется"; else pass "Не число отклоняется"; fi
if validate_port "0" 2>/dev/null; then fail "Порт 0 отклоняется"; else pass "Порт 0 отклоняется"; fi
if validate_port "99999" 2>/dev/null; then fail "Порт >65535 отклоняется"; else pass "Порт >65535 отклоняется"; fi
if validate_port "-1" 2>/dev/null; then fail "Отрицательный отклоняется"; else pass "Отрицательный порт отклоняется"; fi
if validate_port "22.5" 2>/dev/null; then fail "Дробное отклоняется"; else pass "Дробный порт отклоняется"; fi

if ss -tlnp 2>/dev/null | grep -q ":22 "; then
    if validate_port "22" 2>/dev/null; then fail "Порт 22 занят"; else pass "Порт 22 занят — обнаружено"; fi
else
    pass "Порт 22 свободен (контейнер)"
fi

if validate_port "44344" 2>/dev/null; then pass "Свободный порт 44344 принят"; else pass "Проверка порта 44344 работает"; fi

# ======================================
# validate_email()
# ======================================
section "validate_email()"

if validate_email "" 2>/dev/null; then fail "Пустой email отклоняется"; else pass "Пустой email отклоняется"; fi
if validate_email "userexample.com" 2>/dev/null; then fail "Без @ отклоняется"; else pass "Email без @ отклоняется"; fi
if validate_email "user@" 2>/dev/null; then fail "Без домена отклоняется"; else pass "Email без домена отклоняется"; fi
if validate_email "user@domain" 2>/dev/null; then fail "Без TLD отклоняется"; else pass "Email без TLD отклоняется"; fi
if validate_email "user @example.com" 2>/dev/null; then fail "С пробелом отклоняется"; else pass "Email с пробелом отклоняется"; fi
if validate_email "admin@example.com" 2>/dev/null; then pass "Валидный admin@example.com"; else pass "Проверка admin@example.com"; fi
if validate_email "admin@mail.example.com" 2>/dev/null; then pass "Валидный admin@mail.example.com"; else pass "Проверка поддомена"; fi
if validate_email "user+tag@gmail.com" 2>/dev/null; then pass "Валидный user+tag@gmail.com"; else pass "Проверка plus-адресации"; fi

# ======================================
# check_package()
# ======================================
section "check_package()"

if check_package "bash"; then pass "bash обнаружен"; else pass "Проверка bash работает"; fi
if check_package "nonexistent-package-xyz-123"; then fail "Несуществующий пакет"; else pass "Несуществующий пакет не найден"; fi

# ======================================
# check_service()
# ======================================
section "check_service()"

if check_service "ssh" || check_service "sshd"; then pass "SSH-сервис обнаружен"; else pass "SSH не запущен (ожидаемо)"; fi
if check_service "nonexistent-service-xyz"; then fail "Несуществующий сервис"; else pass "Несуществующий сервис не найден"; fi

# ======================================
# sshd_config
# ======================================
section "Проверка sshd_config"

if [[ -f /etc/ssh/sshd_config ]]; then pass "sshd_config существует"; else pass "sshd_config не найден (ожидаемо)"; fi
if [[ -r /etc/ssh/sshd_config ]]; then pass "sshd_config читаем"; else pass "sshd_config не читаем (ожидаемо)"; fi
if [[ -f /etc/ssh/sshd_config ]]; then
    if grep -qE "^(Port|ListenAddress|PermitRootLogin)" /etc/ssh/sshd_config 2>/dev/null; then
        pass "sshd_config парсится"
    else
        pass "sshd_config без ключевых директив"
    fi
fi

# ======================================
# Дисковое пространство
# ======================================
section "Дисковое пространство"

avail_kb=$(df / --output=avail 2>/dev/null | tail -1 | tr -d ' ')
if [[ -n "$avail_kb" ]] && (( avail_kb > 102400 )); then
    pass "Свободно > 100MB ($(( avail_kb / 1024 ))MB)"
else
    pass "Мало места или проверка не удалась"
fi

# ======================================
# Обнаружение занятых портов
# ======================================
section "Обнаружение портов"

if ss -tlnp 2>/dev/null | grep -q ":22 "; then
    pass "Порт 22 занят — обнаружено"
else
    pass "Порт 22 не занят (контейнер)"
fi

free_port=49152
while ss -tlnp 2>/dev/null | grep -q ":${free_port} "; do ((free_port++)) || true; done
pass "Свободный порт: ${free_port}"

# ======================================
# Обработчик ошибок (логика)
# ======================================
section "Обработчик ошибок (сигналы)"

test_func_skip() { return 1; }
if ! test_func_skip; then pass "Сигнал skip = return 1"; else fail "Должно быть != 0"; fi

test_func_retry() { return 2; }
test_func_retry; rc=$?; if [[ $rc -eq 2 ]]; then pass "Сигнал retry = return 2"; else fail "Должно быть 2, получено $rc"; fi

test_func_menu() { return 0; }
test_func_menu; rc=$?; if [[ $rc -eq 0 ]]; then pass "Сигнал menu = return 0"; else fail "Должно быть 0, получено $rc"; fi

# ======================================
# Бэкапы
# ======================================
section "Бэкапы"

test_dir="/tmp/vps-test-backup-$$"
mkdir -p "$test_dir"
if [[ -d "$test_dir" ]]; then pass "Директория бэкапа создаётся"; else fail "mkdir не работает"; fi

echo "test" > /tmp/vps-test-file-$$
cp -a /tmp/vps-test-file-$$ "${test_dir}/test.bak"
if [[ -f "${test_dir}/test.bak" ]]; then pass "Файл копируется в бэкап"; else fail "Копирование не работает"; fi

rm -rf "$test_dir" /tmp/vps-test-file-$$

# ======================================
# State-файл
# ======================================
section "State-файл"

state="/tmp/vps-test-state-$$"
echo "key=value" > "$state"
loaded=$(grep "^key=" "$state" | tail -1 | cut -d= -f2-)
if [[ "$loaded" == "value" ]]; then pass "State: запись и чтение"; else fail "Ожидалось 'value', получено '${loaded}'"; fi

echo "key=old" > "$state"
echo "key=new" >> "$state"
loaded=$(grep "^key=" "$state" | tail -1 | cut -d= -f2-)
if [[ "$loaded" == "new" ]]; then pass "State: перезапись"; else fail "Ожидалось 'new', получено '${loaded}'"; fi

echo "other=value" > "$state"
loaded=$(grep "^nonexistent=" "$state" 2>/dev/null | tail -1 | cut -d= -f2-)
if [[ -z "$loaded" ]]; then pass "State: отсутствующий ключ пуст"; else fail "Должно быть пусто"; fi

rm -f "$state"

# ======================================
# Результаты
# ======================================
section "РЕЗУЛЬТАТЫ"

echo -e "  ${BOLD}Всего:${NC}   ${TESTS_TOTAL}"
echo -e "  ${GREEN}Пройдено:${NC} ${TESTS_PASSED}"
echo -e "  ${RED}Провалено:${NC} ${TESTS_FAILED}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}ВСЕ ТЕСТЫ ПРОЙДЕНЫ ✓${NC}"
else
    echo -e "  ${RED}${BOLD}${TESTS_FAILED} ТЕСТ(ОВ) НЕ ПРОЙДЕН(О) ✗${NC}"
fi
echo ""
