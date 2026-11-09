#!/bin/bash
# Hosts File Manager for Alfred.
#
#   hosts.sh list "<query>"                  Script Filter JSON for Alfred
#   hosts.sh add <ip> <host> [comment]       append an entry
#   hosts.sh toggle <line> <host> <text>     comment a line out, or back in
#   hosts.sh remove <line> <host> <text>     delete a line
#
# toggle and remove only act if line <line> still reads <text>.
# HOSTS_FILE overrides the target file (used for testing on a copy).

HOSTS_FILE="${HOSTS_FILE:-/private/etc/hosts}"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

looks_like_ip() {
  [[ $1 =~ ^[0-9]+(\.[0-9]+)+$ || $1 =~ ^[0-9a-fA-F]*:[0-9a-fA-F:.]*$ ]]
}

is_ip() {
  if [[ $1 =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
    local i
    for i in 1 2 3 4; do (( 10#${BASH_REMATCH[$i]} <= 255 )) || return 1; done
    return 0
  fi
  [[ $1 =~ ^[0-9a-fA-F]*:[0-9a-fA-F]*:[0-9a-fA-F:.]*$ ]]
}

is_host() {
  [[ $1 =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]
}

# A pasted URL becomes its hostname: https://user@example.com:8080/about -> example.com
url_host() {
  local h="$1"
  if [[ $h =~ ^[A-Za-z][A-Za-z0-9+.-]*://([^/?#]+) ]]; then
    h=${BASH_REMATCH[1]}
    h=${h##*@}
    h=${h%%:*}
  fi
  printf '%s' "$h"
}

list() {
  local q w1 w2 rest search add_ip="" add_host="" add_comment="" add_error=""
  q=$(trim "$1")
  read -r w1 w2 rest <<< "$q"
  w1=$(url_host "$w1")
  w2=$(url_host "$w2")
  search=$(trim "$w1 $w2 $rest")

  # "<host> <ip> [comment]" and "<ip> <host> [comment]" both set the IP;
  # "<host> [comment]" defaults to 127.0.0.1. An IP on its own is only a search.
  if ! looks_like_ip "$w1" && looks_like_ip "$w2"; then
    local swap=$w1; w1=$w2; w2=$swap
  fi
  if looks_like_ip "$w1"; then
    if [[ -n $w2 ]]; then
      if ! is_ip "$w1"; then
        add_error="$w1 isn't a valid IP address"
      elif ! is_host "$w2"; then
        add_error="$w2 isn't a valid hostname"
      else
        add_ip=$w1 add_host=$w2 add_comment=$rest
      fi
    fi
  elif is_host "$w1"; then
    add_ip=127.0.0.1 add_host=$w1 add_comment=$(trim "$w2 $rest")
  fi
  add_comment=$(trim "${add_comment#\#}")

  awk -v q="$search" -v today="$(date +%d-%m-%Y)" \
      -v addip="$add_ip" -v addhost="$add_host" -v addcomment="$add_comment" -v adderror="$add_error" '
    function esc(s) {
      gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s)
      gsub(/\t/, "\\t", s); gsub(/\r/, "\\r", s)
      return s
    }
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function join(a, b) { return a == "" ? b : (b == "" ? a : a "  ·  " b) }
    function days(d, m, y) { if (m < 3) { y--; m += 12 } return 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + d }
    function ago(stamp,   p, t, n) {
      split(stamp, p, "-"); split(today, t, "-")
      n = days(t[1] + 0, t[2] + 0, t[3] + 0) - days(p[1] + 0, p[2] + 0, p[3] + 0)
      if (n <= 0) return "added today"
      if (n == 1) return "added yesterday"
      if (n < 14) return "added " n " days ago"
      if (n < 60) return "added " int(n / 7) " weeks ago"
      if (n < 730) return "added " int(n / 30) " months ago"
      return "added " int(n / 365) " years ago"
    }
    function is_entry(s) { return s ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[ \t]+[^ \t]/ || s ~ /^[0-9a-fA-F]*:[0-9a-fA-F]*:[0-9a-fA-F:.%a-z0-9]*[ \t]+[^ \t]/ }
    function matches(hay,   w, n, i) {
      n = split(tolower(q), w, /[ \t]+/)
      for (i = 1; i <= n; i++) if (index(hay, w[i]) == 0) return 0
      return 1
    }

    BEGIN { section = ""; inblock = 0; useritems = ""; sysitems = ""; found = 0 }

    {
      t = trim($0)
      if (t == "") { section = ""; inblock = 0; next }

      off = 0
      if (substr(t, 1, 1) == "#") {
        c = t; sub(/^#+/, "", c); c = trim(c)
        if (!is_entry(c)) {
          if (tolower(c) ~ /^end of section/) { section = ""; inblock = 0 }
          # The first line of text in a comment block names the entries below it.
          else if (!inblock && c != "") { section = c; sub(/^Added by /, "", section); inblock = 1 }
          next
        }
        off = 1; body = c
      } else {
        inblock = 0; body = t
      }

      comment = ""
      p = index(body, "#")
      if (p > 0) { comment = trim(substr(body, p + 1)); body = trim(substr(body, 1, p - 1)) }
      k = split(body, f, /[ \t]+/)
      if (k < 2) next

      ip = f[1]; names = f[2]
      for (i = 3; i <= k; i++) names = names " " f[i]
      exact = 0
      for (i = 2; i <= k; i++) if (tolower(f[i]) == tolower(addhost)) exact = found = 1

      age = ""
      if (match(comment, /\(?added [0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]\)?$/)) {
        stamp = substr(comment, RSTART, RLENGTH); gsub(/[^0-9-]/, "", stamp)
        age = ago(stamp); comment = trim(substr(comment, 1, RSTART - 1))
      }

      sys = (f[2] == "localhost" || f[2] == "broadcasthost")
      sub_ = join(off ? "Off" : "", ip); sub_ = join(sub_, comment); sub_ = join(sub_, age)
      sub_ = join(sub_, sys ? "System" : section)
      # Show entries matching every word, and always the one you are trying to add.
      if (!exact && !matches(tolower(names " " sub_))) next

      item = "{\"title\":\"" esc(names) "\",\"subtitle\":\"" esc(sub_) "\""
      item = item ",\"text\":{\"copy\":\"" esc(t) "\",\"largetype\":\"" esc(t) "\"}"
      if (off) item = item ",\"icon\":{\"path\":\"off.png\"}"
      if (sys) {
        item = item ",\"valid\":false,\"mods\":{\"alt\":{\"valid\":false,\"subtitle\":\"System entry. It can\x27t be removed.\"}}}"
        sysitems = sysitems (sysitems == "" ? "" : ",") item
      } else {
        a = "\"" NR "\",\"" esc(f[2]) "\",\"" esc($0) "\""
        item = item ",\"arg\":[\"toggle\"," a "],\"mods\":{\"alt\":{\"arg\":[\"remove\"," a "],\"subtitle\":\"Remove this entry\"}}}"
        useritems = useritems (useritems == "" ? "" : ",") item
      }
    }

    END {
      out = useritems
      if (sysitems != "") out = out (out == "" ? "" : ",") sysitems
      extra = ""
      if (adderror != "") {
        extra = "{\"title\":\"" esc(adderror) "\",\"subtitle\":\"Use <hostname> [ip] [comment], like site.test 10.0.0.5 My server\",\"valid\":false}"
      } else if (addhost != "" && !found) {
        s = addcomment != "" ? "Comment: " addcomment : "Not in your hosts file. An IP and a comment can follow the hostname."
        extra = "{\"title\":\"Add " esc(addhost) " → " esc(addip) "\",\"subtitle\":\"" esc(s) "\""
        extra = extra ",\"arg\":[\"add\",\"" esc(addip) "\",\"" esc(addhost) "\",\"" esc(addcomment) "\"],\"mods\":{\"alt\":{\"valid\":false}}}"
      }
      if (extra != "") out = out (out == "" ? "" : ",") extra
      if (out == "" && q != "") out = "{\"title\":\"No matching entries\",\"valid\":false}"
      if (q == "") {
        hint = "{\"title\":\"Search, or type a new hostname to add it\",\"subtitle\":\"hostname [ip] [comment], like mysite.test 10.0.0.5 My server\",\"valid\":false}"
        out = hint (out == "" ? "" : ",") out
      }
      print "{\"items\":[" out "]}"
    }
  ' "$HOSTS_FILE"
}

# Runs this script's internal command with write access to the hosts file,
# asking for an administrator password only when the file is not writable.
privileged() {
  local err rc
  if [[ -w "$HOSTS_FILE" ]]; then
    err=$(/bin/bash "$SELF" "$@" 2>&1 >/dev/null)
    rc=$?
  else
    err=$(osascript - "$SELF" "$@" 2>&1 >/dev/null <<'APPLESCRIPT'
on run argv
  set cmd to "/bin/bash"
  repeat with a in argv
    set cmd to cmd & " " & quoted form of (a as text)
  end repeat
  do shell script cmd with administrator privileges
end run
APPLESCRIPT
)
    rc=$?
  fi
  if (( rc != 0 )); then
    err=${err##*execution error: }
    err=${err% (*)}
    [[ $err == "User canceled." ]] && err="Cancelled"
    [[ -z $err ]] && err="Couldn't write $HOSTS_FILE"
    echo "$err"
    return 1
  fi
}

add() {
  local ip=$1 host=$2 comment line
  comment=$(trim "${3#\#}")
  if ! is_ip "$ip"; then echo "$ip isn't a valid IP address"; return 1; fi
  if ! is_host "$host"; then echo "$host isn't a valid hostname"; return 1; fi

  line="$ip $host # "
  [[ -n $comment ]] && line+="$comment "
  line+="(added $(date +%d-%m-%Y))"
  privileged _append "$line" || return 1
  echo "Added $host"
}

# Checks that line $1 still reads $2, so a file changed since listing is never edited.
unchanged() {
  [[ $1 =~ ^[0-9]+$ && "$(sed -n "${1}p" "$HOSTS_FILE")" == "$2" ]]
}

toggle() {
  unchanged "$1" "$3" || { echo "The hosts file changed. Open the list again."; return 1; }
  privileged _toggle "$1" "$3" || return 1
  if [[ $3 =~ ^[[:space:]]*# ]]; then echo "Turned on $2"; else echo "Turned off $2"; fi
}

remove() {
  unchanged "$1" "$3" || { echo "The hosts file changed. Open the list again."; return 1; }
  privileged _remove "$1" "$3" || return 1
  echo "Removed $2"
}

flush_dns() {
  if (( EUID == 0 )); then
    dscacheutil -flushcache
    killall -HUP mDNSResponder 2>/dev/null
  fi
  return 0
}

case "$1" in
  list) list "$2" ;;
  add) add "$2" "$3" "$4" ;;
  toggle) toggle "$2" "$3" "$4" ;;
  remove) remove "$2" "$3" "$4" ;;

  # Internal commands, run with write access by privileged().
  _append)
    # Start on a new line if the file does not end with one.
    [[ -s $HOSTS_FILE && -n "$(tail -c 1 "$HOSTS_FILE")" ]] && printf '\n' >> "$HOSTS_FILE"
    # A blank line keeps new entries out of the section above, unless that is our own last entry.
    last=$(tail -n 1 "$HOSTS_FILE")
    [[ -n $last && ! $last =~ \(added\ [0-9]{2}-[0-9]{2}-[0-9]{4}\)$ ]] && printf '\n' >> "$HOSTS_FILE"
    printf '%s\n' "$2" >> "$HOSTS_FILE" && flush_dns
    ;;
  _toggle)
    unchanged "$2" "$3" || { echo "The hosts file changed. Open the list again." >&2; exit 1; }
    if [[ $3 =~ ^[[:space:]]*# ]]; then
      sed -i '.bak' "${2}s/^[[:space:]]*#*[[:space:]]*//" "$HOSTS_FILE"
    else
      sed -i '.bak' "${2}s/^/#/" "$HOSTS_FILE"
    fi && flush_dns
    ;;
  _remove)
    unchanged "$2" "$3" || { echo "The hosts file changed. Open the list again." >&2; exit 1; }
    sed -i '.bak' "${2}d" "$HOSTS_FILE" && flush_dns
    ;;
  *)
    echo "Usage: $0 list \"<query>\" | add <ip> <host> [comment] | toggle|remove <line> <host> <text>" >&2
    exit 64
    ;;
esac
