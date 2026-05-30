#!/opt/bin/sh

# Конфигурация
ConnInterface="eth3.3086"
counter="/opt/tmp/CountReconnectWan.txt"
previp="/opt/tmp/previp.txt"
max_tries=2
log="/tmp/pppoe_guard.log"

# Защита от параллельного запуска
lockfile="/tmp/pppoe_reconnect.lock"

if [ -f "$lockfile" ]; then
    oldpid=$(cat "$lockfile")
    if kill -0 "$oldpid" 2>/dev/null; then
        exit 0
    fi
fi

echo $$ > "$lockfile"
trap 'rm -f "$lockfile"' EXIT

# Логируем параметры hook
echo "$(date) Interface=$interface Address=$address Gateway=$gateway" >> "$log"

# ПРОПУСК ПРИ ЗАГРУЗКЕ: Ждем ~1.5 минуты (90 сек), чтобы дать подняться VPN и синхронизировать время
uptime_sec=$(cat /proc/uptime | awk '{print $1}' | cut -d. -f1)
if [ "$uptime_sec" -lt 90 ]; then
    echo "$(date) System is booting (Uptime: ${uptime_sec}s). Skipping reconnect." >> "$log"
    exit 0
fi

# Получаем IP PPPoE
current_ip=$(ip addr show ppp0 | awk '/inet / {print $2}' | cut -d/ -f1)

# Если IP не получили — выходим
[ -z "$current_ip" ] && exit 0

echo "$(date) Current IP=$current_ip" >> "$log"

# Проверка на серый IP (CGNAT диапазоны)
if echo "$current_ip" | grep -qE "^(10\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.|172\.(1[6-9]|2[0-9]|3[01])\.)"; then

    echo "$(date) Grey IP detected" >> "$log"

    # Создание файла счётчика
    [ -f "$counter" ] || echo "0" > "$counter"

    # Увеличение счётчика
    try_nr=$(cat "$counter")
    try_nr=$((try_nr + 1))

    if [ "$try_nr" -gt "$max_tries" ]; then
        echo "$(date) Max retries reached" >> "$log"
        echo "0" > "$counter"
        exit 0
    fi

    echo "$try_nr" > "$counter"

    # Запускаем переподключение через надежный ndmq и nohup
    nohup sh -c '
        sleep 20
        echo "$(date) Reconnecting PPPoE..." >> /tmp/pppoe_guard.log
        
        ndmq -p "interface PPPoE0 down"
        sleep 5
        ndmq -p "interface PPPoE0 up"
        
        echo "$(date) PPPoE reconnect complete" >> /tmp/pppoe_guard.log
    ' >/dev/null 2>&1 &

else

    echo "$(date) White IP detected" >> "$log"

    # Сброс счётчика
    echo "0" > "$counter"

    # Сохранение IP
    [ -f "$previp" ] || echo "0.0.0.0" > "$previp"

    _previp=$(cat "$previp")

    if [ "$_previp" != "$current_ip" ]; then
        echo "$current_ip" > "$previp"
    fi

fi

exit 0
