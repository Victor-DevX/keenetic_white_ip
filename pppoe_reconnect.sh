#!/opt/bin/sh

# === Конфигурация ===
log="/opt/var/log/pppoe_guard.log"
lockfile="/tmp/pppoe_reconnect.lock"

# ПУТИ ИСПРАВЛЕНЫ: Теперь файлы живут в оперативной памяти (/tmp/), USB-флешка не изнашивается
previp="/tmp/previp.txt"
counter="/tmp/CountReconnectWan.txt"

max_tries=5
max_log_size=25600 # Лимит лога: ~25 КБ

# === 0. Управление размером лога ===
if [ -f "$log" ]; then
    log_size=$(wc -c < "$log" 2>/dev/null || echo 0)
    if [ "$log_size" -gt "$max_log_size" ]; then
        tail -n 100 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"
        echo "$(date) [SYS] Лог обрезан." >> "$log"
    fi
fi

# === 1. МГНОВЕННАЯ ЗАЩИТА ОТ ПАРАЛЛЕЛЬНОГО ЗАПУСКА ===
if [ -f "$lockfile" ]; then
    oldpid=$(cat "$lockfile")
    if kill -0 "$oldpid" 2>/dev/null; then
        echo "$(date) [INFO] Скрипт уже запущен (PID: $oldpid). Блокировка дубликата." >> "$log"
        exit 0
    else
        rm -f "$lockfile"
    fi
fi

echo $$ > "$lockfile"
trap 'rm -f "$lockfile"' EXIT

# === 2. Пропуск при загрузке роутера ===
uptime_sec=$(cat /proc/uptime | awk '{print int($1)}')
if [ "$uptime_sec" -lt 90 ]; then
    echo "$(date) [SKIP] Система загружается (Uptime: ${uptime_sec}s)." >> "$log"
    exit 0
fi

# === 3. Стабилизация интерфейса ===
sleep 10

# === АВТООПРЕДЕЛЕНИЕ ИНТЕРФЕЙСОВ ===
# 1. Ищем Linux-имя активного шлюза (тот ppp, через который сейчас идет интернет)
linux_iface=$(ip route | awk '/default/ {print $5}' | grep -o 'ppp[0-9]*' | head -n 1)
[ -z "$linux_iface" ] && linux_iface="ppp0" # Фолбэк на случай ошибки определения

# 2. Ищем NDMS-имя PPPoE интерфейса для команд перезапуска
ndms_iface=$(ndmq -p 'show interface' | grep -o 'PPPoE[0-9]*' | head -n 1)
[ -z "$ndms_iface" ] && ndms_iface="PPPoE0" # Фолбэк

current_ip=$(ip addr show "$linux_iface" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1)
[ -z "$current_ip" ] && exit 0

# === 4. Главная логика проверки ===
# Добавлена подсеть 192.168.x.x в проверку "серых" IP
if echo "$current_ip" | grep -qE "^(10\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)"; then
    
    [ -f "$counter" ] || echo "0" > "$counter"
    try_nr=$(cat "$counter")
    try_nr=$((try_nr + 1))
    
    if [ "$try_nr" -ge "$max_tries" ]; then
        delay=300
        echo "0" > "$counter"
        echo "$(date) [WARN] Попытка $try_nr. ЛИМИТ! Серый IP: $current_ip. Пауза 5 минут..." >> "$log"
    else
        delay=15
        echo "$try_nr" > "$counter"
        echo "$(date) [WARN] Попытка $try_nr из $max_tries. Серый IP: $current_ip. Реконнект через 15 сек..." >> "$log"
    fi
    
    trap - EXIT
    
    nohup sh -c "
        echo \$\$ > $lockfile
        
        sleep $delay
        ndmq -p \"interface $ndms_iface down\"
        sleep 5
        ndmq -p \"interface $ndms_iface up\"
        
        echo \"\$(date) [EXEC] Переподключение $ndms_iface выполнено (пауза ${delay} сек).\" >> $log
        
        rm -f $lockfile
    " >/dev/null 2>&1 &

else

    [ -f "$previp" ] || echo "0.0.0.0" > "$previp"
    _previp=$(cat "$previp")
    
    if [ "$_previp" != "$current_ip" ]; then
        echo "$(date) [OK] Получен белый IP: $current_ip на интерфейсе $ndms_iface." >> "$log"
        echo "$current_ip" > "$previp"
    fi
    
    echo "0" > "$counter"
    
fi

exit 0
