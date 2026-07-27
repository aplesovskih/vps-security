# VPS Security Hardening Script

Интерактивный скрипт настройки безопасности VPS на Debian. Полностью на русском языке.

## Быстрая установка

```bash
curl -s https://raw.githubusercontent.com/aplesovskih/vps-security/main/vps-security.sh | sudo bash
```

## Демо-режим (ничего не меняет)

```bash
curl -sO https://raw.githubusercontent.com/aplesovskih/vps-security/main/vps-security.sh && sudo bash vps-security.sh --dry-run
```

## Тесты

```bash
# Тесты обработки ошибок
curl -s https://raw.githubusercontent.com/aplesovskih/vps-security/main/test-error-handling.sh | sudo bash

# Интеграционные тесты
curl -s https://raw.githubusercontent.com/aplesovskih/vps-security/main/test-integration.sh | sudo bash
```

## Модули

| # | Модуль | Описание |
|---|--------|----------|
| 1 | Пользователь | Создание sudo-пользователя с SSH-ключами |
| 2 | UFW файрвол | Настройка файрвола (deny incoming, allow SSH/HTTP/HTTPS) |
| 3 | Fail2ban | Блокировка IP после неудачных попыток входа |
| 4 | SSH порт | Смена порта SSH с валидацией |
| 5 | SSH-ключи | Авторизация по ключам + ужесточение настроек |
| 6 | Автообновления | unattended-upgrades (только обновления безопасности) |
| 7 | SSH аудит | Проверка CVE (Terrapin, regreSSHion) и слабых шифров |
| 8 | AIDE | Мониторинг целостности файлов (IDS) |
| 9 | rkhunter | Обнаружение руткитов |
| 10 | Блокировка root | Отключение парольного входа от root |

## Опции запуска

| Опция | Описание |
|-------|----------|
| *(без опций)* | Интерактивный режим |
| `--dry-run` | Демо-режим — показать что будет сделано |
| `--rollback` | Откат всех изменений |
| `--rollback /path` | Откат из конкретной резервной копии |
| `--help` | Справка |

## Возможности

- **Полная русификация** — все диалоги и сообщения на русском
- **Демо-режим** — посмотреть что будет сделано без реальных изменений
- **Обработка ошибок** — при ошибке: повтор / пропуск / возврат в меню / выход
- **Валидация** — проверка всех вводимых данных (имена, порты, email)
- **Резервные копии** — автоматический бэкап перед каждым изменением
- **Откат** — полный откат всех изменений из бэкапов
- **Логирование** — все действия в `/var/log/vps-security-*.log`
- **Email-уведомления** — AIDE и rkhunter отправляют отчёты на почту
- **ASCII-арт** — наглядные сообщения об ошибках и успехе

## Требования

- Debian 10+ / Ubuntu 20.04+
- Права root (`sudo`)
- Подключение к интернету (для установки пакетов)

## Структура файлов

```
vps-security/
├── vps-security.sh            # Основной скрипт
├── test-error-handling.sh     # Тесты обработки ошибок
├── test-integration.sh        # Интеграционные тесты
├── README.md                  # Эта документация
└── LICENSE                    # MIT лицензия
```

## Лицензия

MIT License — свободное использование и модификация.
