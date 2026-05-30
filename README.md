# Keenetic PPPoE Auto Reconnect
Скрипт для роутеров Keenetic, который автоматически переподключает PPPoE-сессию при получении серого (CGNAT) IP-адреса.

Полезно для:
- прямого удалённого доступа через keendns
- использования роутера как VPN-сервера
- DDNS
- self-hosted сервисов
- обхода CGNAT

---
## Возможности
- Проверка IP на принадлежность к диапазонам:
  - `10.0.0.0/8`
  - `100.64.0.0/10`
  - `172.16.0.0/12`
- Автоматический реконнект PPPoE сессии
- Ограничение количества попыток для защиты от бана со стороны провайдера
- Защита от параллельного запуска
- Логирование
- Перезапуск Keenetic Cloud после реконнекта (для исключения проблем связи с облаком)
- Лёгкий shell-скрипт без зависимостей

---
## Требования
- роутер Keenetic с USB и обязательной поддержкой Entware
- PPPoE-подключение провайдера (если стоит провайдерский роутер, то нужно его перевести в bridge)


## Необходимые компоненты
Перед установкой убедитесь, что на роутере установлены:
- Entware
- wget или curl

Проверить наличие можно командами:
```sh
which wget
which curl
```

Если `wget` отсутствует:
```sh
opkg install wget
```

Если `curl` отсутствует:
```sh
opkg install curl
```

---
## Установка через wget

```sh
wget -O /opt/etc/ndm/wan.d/pppoe_reconnect.sh \
https://raw.githubusercontent.com/Victor-DevX/keenetic_white_ip/refs/heads/main/pppoe_reconnect.sh && \
chmod +x /opt/etc/ndm/wan.d/pppoe_reconnect.sh
```

---
## Установка через curl

```sh
curl -o /opt/etc/ndm/wan.d/pppoe_reconnect.sh \
https://raw.githubusercontent.com/Victor-DevX/keenetic_white_ip/refs/heads/main/pppoe_reconnect.sh && \
chmod +x /opt/etc/ndm/wan.d/pppoe_reconnect.sh
```

---
## Установка вручную
Скачать и скопировать скрипт по пути:
```sh
/opt/etc/ndm/wan.d/pppoe_reconnect.sh
```

Выдать права:
```sh
chmod +x /opt/etc/ndm/wan.d/pppoe_reconnect.sh
```

---
## Удаление
```sh
rm /opt/etc/ndm/wan.d/pppoe_reconnect.sh
```

---
## Запуск вручную
```sh
/opt/etc/ndm/wan.d/pppoe_reconnect.sh
```

---
## Настройка
Основные параметры:

```sh
ConnInterface="eth3.3086"
max_tries=2
```

При необходимости можно изменить интерфейс и количество попыток реконнекта.

---
## Логи
Файл логов:

```sh
/tmp/pppoe_guard.log
```

---
## Как работает

1. Скрипт даёт загрузится роутеру и сервисам
2. Получает текущий IP PPPoE
3. Проверяет, является ли IP серым
4. Если IP серый:
   - увеличивает счётчик попыток
   - отключает PPPoE
   - подключает PPPoE заново
5. Если IP белый:
   - сбрасывает счётчик
   - сохраняет IP

---
## Примечание

Скрипт создавался для ситуаций, когда провайдер динамически выдаёт как белые, так и CGNAT IP-адреса.
---

## License

MIT
