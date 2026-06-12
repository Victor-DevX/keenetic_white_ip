#!/opt/bin/sh

# PPPoE White IP Guard

PPP_INTERFACE="PPPoE0"

# Сохраняем логи и счетчики на физическом накопителе (флешке)
workdir="/opt/var/log/wh_ip"

log="$workdir/reconnect.log"
counter="$workdir/counter.txt"
previp="$workdir/previp.txt"

# Блокировку оставляем в RAM, так как после ребута она в любом случае не нужна
lock="/opt/var/run/wh_ip_reconnect.lock"

max_tries=5
long_pause=300
max_log_size=25600

mkdir -p "$workdir"

# Ротация лога

if [ -f "$log" ]; then
    log_size=$(stat -c%s "$log" 2>/dev/null || echo 0)

    if [ "$log_size" -gt "$max_log_size" ]; then
        tail -n 50 "$log" > "${log}.tmp"
        mv "${log}.tmp" "$log"
        echo "$(date '+%Y-%m-%d %H:%M:%S') [SYS] Log rotated" >> "$log"
    fi
fi

log_msg() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$log"
}


# Фильтрация событий NDMS

[ -n "$address" ] || exit 0

# Отсекаем события от VPN и других интерфейсов
if [ "$system_name" != "$PPP_INTERFACE" ]; then
    exit 0
fi

log_msg "WAN event: interface=$interface system_name=$system_name ip=$address"


# Проверка CGNAT

is_gray_ip() {
    echo "$1" | grep -qE \
    "^(10\.|100\.6[4-9]\.|100\.[7-9][0-9]\.|100\.1[01][0-9]\.|100\.12[0-7]\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[01]\.)"
}


# Мягкий реконнект PPPoE

soft_reconnect() {
    delay="$1"

    (
        mkdir "$lock" 2>/dev/null || {
            log_msg "Реконнект уже выполняется"
            exit 0
        }

        trap 'rmdir "$lock" 2>/dev/null' EXIT

        log_msg "Запланирован реконнект через ${delay}с"
        sleep "$delay"

        log_msg "PPPoE down"

        if ndmc -c "interface $PPP_INTERFACE down"; then
            log_msg "down OK"
        else
            log_msg "down FAILED"
            exit 1
        fi

        sleep 5

        log_msg "PPPoE up"

        if ndmc -c "interface $PPP_INTERFACE up"; then
            log_msg "up OK"
        else
            log_msg "up FAILED"
            exit 1
        fi

        log_msg "Реконнект завершён"
    ) &
}


# Обработка серого IP

if is_gray_ip "$address"; then

    [ -f "$counter" ] || printf '0\n' > "$counter"

    try_nr=$(cat "$counter" 2>/dev/null)
    [ -n "$try_nr" ] || try_nr=0

    try_nr=$((try_nr + 1))

    log_msg "Обнаружен CGNAT IP: $address"
    log_msg "Попытка $try_nr из $max_tries"

    if [ "$try_nr" -ge "$max_tries" ]; then
        log_msg "Достигнут лимит попыток. Ожидание ${long_pause}с"
        printf '0\n' > "$counter"
        soft_reconnect "$long_pause"
        exit 0
    fi

    printf '%s\n' "$try_nr" > "$counter"

    # Случайная задержка 5-15 секунд
    delay=$(( ($(date +%s) % 11) + 5 ))
    soft_reconnect "$delay"

    exit 0
fi


# Обработка белого IP

log_msg "Получен белый IP: $address"

printf '0\n' > "$counter"

[ -f "$previp" ] || printf '0.0.0.0\n' > "$previp"

old_ip=$(cat "$previp" 2>/dev/null)

if [ "$old_ip" != "$address" ]; then
    printf '%s\n' "$address" > "$previp"
    log_msg "IP изменился: $old_ip -> $address"

    log_msg "Обновление WEBADMIN"

    if ndmc -c "ip http security-level public ssl"; then
        log_msg "WEBADMIN OK"
    else
        log_msg "WEBADMIN FAILED"
    fi

    sleep 2

    if ndmc -c "system configuration save"; then
        log_msg "Configuration saved"
    else
        log_msg "Configuration save FAILED"
    fi
fi

exit 0
