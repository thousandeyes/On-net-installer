#!/bin/bash

IFS='
'

# Am I running as root?
if [[ "$EUID" -ne 0 ]]
  then echo "Please run as root. Exiting."
  exit 1;
fi

unsupported_error() {
  
  echo "Unsupported operating system detected."
  echo
  echo "Supported versions of Ubuntu are 20.04 LTS and 22.04 LTS (preferred). Exiting."
  exit 2

}

# Am I running on Ubuntu 22.04 or 20.04?
OS_NAME=$(lsb_release -i | awk '{ print $NF}')
UBUNTU_VERSION=$(lsb_release -s -c 2>/dev/null)
BETA="0"

if [ "$OS_NAME" != "Ubuntu" ]; then
  unsupported_error
elif [ "$UBUNTU_VERSION" == "focal" ]; then
  OEM="linux-oem-20.04b"
elif [ "$UBUNTU_VERSION" == "jammy" ]; then
  UBUNTU_VERSION="stable"
  OEM="linux-oem-22.04b"
elif [ "$UBUNTU_VERSION" == "noble" ]; then
  UBUNTU_VERSION="stable"
  OEM="linux-oem-24.04b"
  BETA="1"
else 
  unsupported_error
fi

REPO_ADDRESS="https://repo.samknows.com"
SYSCTL_NAME=(net.core.rmem_max net.core.wmem_max net.core.rmem_default net.core.wmem_default net.core.netdev_max_backlog net.core.somaxconn net.ipv4.udp_rmem_min net.ipv4.udp_wmem_min net.ipv4.tcp_congestion_control net.ipv4.tcp_sack net.ipv4.tcp_timestamps net.ipv4.tcp_slow_start_after_idle net.ipv4.tcp_no_metrics_save net.ipv4.tcp_tw_reuse net.ipv4.tcp_fin_timeout net.ipv4.tcp_window_scaling net.core.default_qdisc)
SYSCTL_VALUE=(26214400 26214400 524288 524288 40000 14000 128 128 cubic 1 1 1 0 0 60 1 fq)
UFW_RULES=(80/tcp 443/tcp 5000:7000/tcp 5000:7000/udp 8080/tcp 8000/tcp 8001/udp 22/tcp)
SAMKNOWS_PACKAGES=(skhttp-server skjitter-server sklatency-server sklightweightcapacity-server skudpspeed-server skwebsocket-speed-server nginx certbot python3-certbot-nginx ufw gawk $OEM)
SYSCTL_FILE="/etc/sysctl.d/20-network_tuning.conf"
TC_FILENAME="samknows-interfacequeue"
TC_FILE="/etc/init.d/$TC_FILENAME"
CERTBOT_EMAIL="jamie@samknows.com"
MAIN_INTERFACE=$(ip route get 8.8.8.8 | awk -- '{printf $5}')


NGINX_FILENAME="/etc/nginx/sites-available/90_samknows.conf"
WEBTEST_FILENAME="/usr/share/nginx/html/web_test/"
NGINX_COFIG='map $http_upgrade $connection_upgrade {
        default upgrade;
        '"'"''"'"' close;
}

add_header Access-Control-Allow-Origin "*";

server {
        listen 80 default_server;
        listen [::]:80 default_server;
        listen 8080 default_server;
        listen [::]:8080 default_server;
# Samknows SSL configuration listen 6443 ssl default_server;
# Samknows SSL configuration listen [::]:6443 ssl default_server;
# Samknows SSL configuration listen 6800 ssl default_server;
# Samknows SSL configuration listen [::]:6800 ssl default_server;
        root /usr/share/nginx/html/web_test;

        location /ws/0.05 {
                proxy_pass http://localhost:6501;
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection $connection_upgrade;
        }

        location / {
                if ($request_method = POST) {
                        fastcgi_pass 127.0.0.1:9494;
                        return 200;
                }
        }
}'

HUND_SYSCTL_FILENAME='/etc/sysctl.d/21-network_tuning_100gbps.conf'

main () {

if [ "$BETA" == "1" ]; then
  echo "Ubuntu 24.04 detected - this is not officially supported, however the installation should work correctly still and everything should function."
  echo -e "We do not currently guarantee performance in parity with Ubuntu 22.04 and support will be provided on a best effort basis until we formally support 24.04.\n"
fi

check_hostname_resolves

echo "Do you wish to Install SamKnows Defaults or print each change made and have the changes made for you or exit?"
echo "This script can be stopped at any time and run multiple times without issue."
echo "Installation of a SSL certificate and running a firewall are optional options asked when doing a Verbose Install."
echo 
select yn in "Install" "Verbose Install" "Exit"; do
  case $yn in
    "Install" ) MANUAL_INSTALL=false ; break;;
    "Verbose Install" ) MANUAL_INSTALL=true ; break;;
    "Exit" ) exit;;
  esac
done

if [[ ! -f /etc/apt/sources.list.d/samknows.list  ]] || [[ ! -f /etc/apt/trusted.gpg.d/samknows.asc ]]
  then if $MANUAL_INSTALL 
    then
    echo
    echo "This script will install SamKnows software from the SamKnows Package Repository, which needs to be enabled before we can proceed. The repository will be enabled with these commands:"
    echo 
    echo echo "deb [arch=amd64] $REPO_ADDRESS/apt-repo $UBUNTU_VERSION main" \| sudo tee /etc/apt/sources.list.d/samknows.list
    echo curl -L $REPO_ADDRESS/pubkey.asc -o /etc/apt/trusted.gpg.d/samknows.asc
    echo apt update
    echo
    echo "Add the SamKnows Package Repository now?"
    select yn in "Yes" "No"; do
      case $yn in
        "Yes" ) install_samknows_repo; break;;
        "No" ) echo "Skipping this step"; break;;
     esac
    done
    else install_samknows_repo
    echo "Installing SamKnows Package Repository."
    fi
  else 
  echo "SamKnows Package Repository already installed, does not need installing."
fi

i=0
until [[ $i = ${#SAMKNOWS_PACKAGES[@]} ]]
do
  PACKAGES_CHECK=$(dpkg --get-selections ${SAMKNOWS_PACKAGES[$i]} 2>/dev/null)
  if [[ "$PACKAGES_CHECK" != "${SAMKNOWS_PACKAGES[$i]}"*"install" ]]
    then PACKAGES_SUGGEST="${SAMKNOWS_PACKAGES[$i]}
$PACKAGES_SUGGEST"
  fi
  ((i=i+1))
done

if [[ ! -z "$PACKAGES_SUGGEST" ]]
  then if $MANUAL_INSTALL
    then
    echo
    echo "The following command needs to be run to install recommended SamKnows Operating System Packages:"
    echo 
    echo apt install $PACKAGES_SUGGEST
    echo
    echo "Would you like these packages installed now?"
    select yn in "Yes" "No"; do
      case $yn in
        "Yes" ) install_samknows_packages; break;;
        "No" ) echo "Skipping this step"; break;;
     esac
    done
    else install_samknows_packages
    echo "Installing recommended SamKnows Operating System Packages."
  fi
  else
  echo "SamKnows Packages already installed, none needed to be installed."
fi

check_nginx_config;

if [[ ! -f "$NGINX_FILENAME" ]]
  then if $MANUAL_INSTALL
    then echo "Would you like to create $NGINX_FILENAME with the following content to configure Nginx, link the config in /etc/nginx/sites-enabled/ so it loads and create test data for clients to request? If you have modified the configuration of Nginx in any way generation of Nginx may fail and would need to be done manually."
    echo
    echo "$NGINX_COFIG"
    echo
    echo rm /etc/nginx/sites-enabled/default
    echo ln -snf $NGINX_FILENAME /etc/nginx/sites-enabled/
    echo 
    echo dd if=/dev/urandom of=/usr/share/nginx/html/web_test/100MB.bin bs=100M count=1 iflag=fullblock
    echo dd if=/dev/urandom of=/usr/share/nginx/html/web_test/1000MB.bin bs=100M count=10 iflag=fullblock
    echo touch /usr/share/nginx/html/web_test/index.html
    echo hostname \> /usr/share/nginx/html/web_test/hostname
    echo
    select yn in "Yes" "No"; do
      case $yn in
        "Yes" ) install_samknows_nginx; break;;
        "No" ) echo "Skipping this step"; break;;
      esac
    done
    else install_samknows_nginx
    echo "Installing Nginx webserver."
  fi
  else echo "Nginx looks to be configured already"
fi

i=0
until [[ $i = 17 ]]
do
  SYSCTL_CHECK=$(sysctl -b ${SYSCTL_NAME[$i]})
  if [[ "$SYSCTL_CHECK" != "${SYSCTL_VALUE[$i]}" ]]
    then SYSCTL_SUGGEST="${SYSCTL_NAME[$i]}=${SYSCTL_VALUE[$i]}
$SYSCTL_SUGGEST"
  fi
  ((i=i+1))
done
SYSCTL_CHECK=$(sysctl -b net.ipv4.tcp_rmem)
if [[ "$SYSCTL_CHECK" != "4096"*"131072"*"8388608" ]]
  then SYSCTL_SUGGEST="net.ipv4.tcp_rmem=4096 131072 8388608
$SYSCTL_SUGGEST"
fi
SYSCTL_CHECK=$(sysctl -b net.ipv4.tcp_wmem)
if [[ "$SYSCTL_CHECK" != "4096"*"131072"*"8388608" ]]
  then SYSCTL_SUGGEST="net.ipv4.tcp_wmem=4096 131072 8388608
$SYSCTL_SUGGEST"
fi

TC_SUGGEST=
for interface in `ip -br l | awk '$1 !~ "lo|vir|wl" { print $1}'` ; do 
  TC_OUT=$(tc qdisc show dev $interface | grep -v "qdisc mq 0: root") 
  if [[ "$TC_OUT" != *"qdisc fq 0: "* ]]
    then TC_SUGGEST="$TC_SUGGEST
tc qdisc add dev $interface root fq 
tc qdisc del dev $interface root" 
  fi
done

#Apply 100G tweaks to interfaces equal to or greater than 40G
if [[ -f /sys/class/net/$MAIN_INTERFACE/speed ]]
  then MAIN_INTERFACE_SPEED=$(cat /sys/class/net/$MAIN_INTERFACE/speed)
  else
    MAIN_INTERFACE_SPEED=10000
    echo "Could not determine main interface speed. Does this server have an interface running at 40G or higher?"
    select yn in "Yes" "No"; do
      case $yn in
        "Yes" ) MAIN_INTERFACE_SPEED=40000 ; break;;
        "No" ) MAIN_INTERFACE_SPEED=10000 ; break ;;
      esac
    done
fi
if [[ $MAIN_INTERFACE_SPEED -ge 40000 ]]
  then if $MANUAL_INSTALL
    then echo "40G or higher interface speed detected."
    echo "SamKnows has additional TCP tuning for higher test accuracy."
    echo "Would you like to save these settings and apply them so they are loaded on reboot?"
    select yn in "Yes" "No"; do
      case $yn in
        "Yes" ) apply_100g_tweaks ; break;;
        "No" ) echo "Skipping this step"; break;;
      esac
    done
  else apply_100g_tweaks
  echo "Applying TCP tuning for main interface due to >40G speeds."
  fi
else if [[ ! -z "$TC_SUGGEST" ]]
  then if $MANUAL_INSTALL
    then echo
    echo "SamKnows recommends changing interface queuing to Fair Queuing for improved performance:"
    echo "$TC_SUGGEST" 
    echo
    echo "Would you like to save these settings to $TC_FILE and apply them so they are loaded on reboot?"
    select yn in "Yes" "No"; do
      case $yn in
        "Yes" ) install_samknows_fairqueuing ; break;;
        "No" ) echo "Skipping this step"; break;;
      esac
    done
  else install_samknows_fairqueuing
  echo "Applying to all interfaces Fair Queuing queuing algorithm."
  fi
  else echo "Fair Queuing on all interfaces already applied correctly."
  fi
fi

if [[ ! -z "$SYSCTL_SUGGEST" ]] 
  then if $MANUAL_INSTALL
    then echo "SamKnows recommends the following linux kernel settings:"
    echo
    echo "$SYSCTL_SUGGEST"
    echo "Would you like to save these settings to $SYSCTL_FILE and apply them so they are loaded on reboot?"
    select yn in "Yes" "No"; do
      case $yn in
        "Yes" ) install_samknows_sysconfig ; break;;
        "No" ) echo "Skipping this step"; break;;
     esac
    done
  else install_samknows_sysconfig
  echo "Applying recommended Linux tuning parameters."
  fi
  else echo "No system configuration options to recommend."
fi

UFW_CHECK=$(ufw status verbose 2>&1)
if [[ -z "$UFW_CHECK" ]]
  then echo 
  echo "UFW (Ubuntu FireWall) not installed, run \"apt install ufw\" to install UFW if required."
  echo
  exit;
fi

if [[ ! -d "/etc/letsencrypt/live/$FQDN_HOSTNAME" ]]
  then if $MANUAL_INSTALL
    then echo
    echo "SamKnows recommends using LetsEncrypt to handle SSL certificate generation. Allow this script to generate an SSL certificate and configure Nginx to use it? This step is optional."
      select yn in "Yes" "No" "Skip"; do
        case $yn in
        "Yes" ) install_samknows_certbot ; break;;
        "No" ) NO_INSTALL_SSL=true; break;;
        "Skip" ) NO_INSTALL_SSL=true; break;;
     esac
    done
  else install_samknows_certbot 
  echo "Registering the host with LetsEncrypt, generating a valid SSL and enabling it in Nginx."
  fi
  else echo "Letsencrypt looks like it is already setup, nothing to do."
fi

CERTBOTCRON_INSTALLED=$(grep "certbot renew" /etc/crontab)

if ! [[ $NO_INSTALL_SSL ]] ; then
  if [[ -z $CERTBOTCRON_INSTALLED ]]
    then if $MANUAL_INSTALL
      then
      echo
      echo "Do you want to install a script in /etc/crontab to renew the LetsEncrypt SSL certificate automatically?"
      echo "If you do not do this, you will need to renew the LetsEncrypt SSL certificate manually every 3 months."
      SLEEPTIME=$(awk 'BEGIN{srand(); print int(rand()*(3600+1))}');
      echo
      echo 'echo "0 0,12 * * * root sleep $SLEEPTIME && certbot renew -q; systemctl reload nginx" >> /etc/crontab'
      echo
      select yn in "Yes" "No"; do
        case $yn in
        "Yes" ) install_samknows_certbotcron ; break;;
        "No" ) echo "Skipping this step";;
      esac
        done
  else install_samknows_certbotcron
    echo "Installing Letsencrypt script in /etc/crontab to auto renew certificate."
    fi
    else echo "Looks like a script in /etc/crontab is already renewing Letsencrypt, nothing to do."
  fi
fi

if [ "$UFW_CHECK" = "Status: inactive" ]
  then if $MANUAL_INSTALL
    then
    echo 
    echo "UFW (Ubuntu FireWall) is currently disabled. Do you wish to enable UFW? Warning: Enabling UFW may break any other local firewall software. This step is optional."
    select yn in "Yes" "No"; do
      case $yn in
        "Yes" ) install_samknows_firewallenable ; break;;
        "No" ) echo ; echo "All done" ; echo ; exit;;
     esac
    done
    echo
  else install_samknows_firewallenable
  echo "Enabling UFW (Ubuntu FireWall)."
  fi
  else echo "UFW (Ubuntu FireWall) is already enabled, nothing to do."
fi

i=0
until [[ $i = 12 ]]
do
  UFW_RULE_FOUND=0
  for o in $UFW_CHECK
  do 
    if [[ "$o" = "${UFW_RULES[$i]}"* ]]
      then UFW_RULE_FOUND=1
    fi
    done
  if [[ $UFW_RULE_FOUND -eq 0 ]]
    then
      UFW_SUGGEST="ufw allow ${UFW_RULES[$i]} 
$UFW_SUGGEST"
 fi
  ((i=i+1))
done

if [[ ! -z "$UFW_SUGGEST" ]]
  then if $MANUAL_INSTALL
    then echo "SamKnows recommends using these UFW rules to allow SamKnows Measurement Server Applications and associated server management to function correctly:"
    echo
    echo "$UFW_SUGGEST"
    echo "Apply the suggested rules to UFW (Ubuntu FireWall) now? These rules will persist even after a reboot."
    echo "Please review and ensure that any existing UFW rules do not conflict with the proposed additions."
      select yn in "Yes" "No"; do
        case $yn in
        "Yes" ) install_samknows_firewallrules ; break;;
        "No" ) exit;;
     esac
    done
  else install_samknows_firewallrules
  echo "Installing Samknows UFW (Ubuntu Firewall) rules."
  fi
  else echo "No UFW (Ubuntu FireWall) rule modifications to suggest."
fi

echo "Installation completed. It is highly recommended that this host be rebooted to ensure all changes take effect."

} # Main End

install_samknows_repo () {
  echo "deb [arch=amd64] $REPO_ADDRESS/apt-repo $UBUNTU_VERSION main" > /etc/apt/sources.list.d/samknows.list
  curl -s -L $REPO_ADDRESS/pubkey.asc -o /etc/apt/trusted.gpg.d/samknows.asc
  apt-get update -qq >> /dev/null
  apt-get check -qq
}

install_samknows_packages () {
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $PACKAGES_SUGGEST >> /dev/null 2>&1
}

install_samknows_nginx () {
  echo "$NGINX_COFIG" > $NGINX_FILENAME
  ln -snf $NGINX_FILENAME /etc/nginx/sites-enabled/ >> /dev/null
  rm -f /etc/nginx/sites-enabled/default
  service nginx reload
  mkdir -p /usr/share/nginx/html/web_test/
  dd if=/dev/urandom of=$WEBTEST_FILENAME/100MB.bin bs=100M count=1 iflag=fullblock status=none >> /dev/null
  dd if=/dev/urandom of=$WEBTEST_FILENAME/1000MB.bin bs=100M count=10 iflag=fullblock status=none >> /dev/null
  touch $WEBTEST_FILENAME/index.html
  hostname > $WEBTEST_FILENAME/hostname
}

install_samknows_sysconfig () {
  if [[ ! -f $SYSCTL_FILE ]]
    then
    curl https://raw.githubusercontent.com/thousandeyes/On-net-installer/refs/heads/master/files/etc/sysctl.d/20-network_tuning.conf > "$SYSCTL_FILE" ; 
    sysctl -q -p 
    service procps force-reload 
  else 
    echo "File $SYSCTL_FILE exists already. Nothing to do."
  fi
}

apply_100g_tweaks () {
  TC_FILENAME="samknows-interfacequeue-100g"
  TC_FILE="/etc/init.d/$TC_FILENAME"
  if [[ ! -f "$TC_FILE" ]]
    then curl https://raw.githubusercontent.com/thousandeyes/On-net-installer/refs/heads/master/files/etc/init.d/samknows-interfacequeue-100g > "$TC_FILE"
    chmod +x "$TC_FILE"
    update-rc.d "$TC_FILENAME" defaults
    eval "$TC_FILE"
    echo "Fair Queuing settings saved to $TC_FILE"
  else 
    echo "File $TC_FILE exists already. Nothing to do."
    exit 2
  fi

  sysctl -q -w net.core.default_qdisc=fq

  for interface in `ip -br l | awk '$1 !~ "lo|vir|wl" { print $1}'` ; do
    tc qdisc add dev $interface root fq 
    tc qdisc del dev $interface root
    tc qdisc replace dev $interface root mq
    for QUEUE in $(tc qdisc show | grep "^qdisc fq" | awk '{ print $7 }')
      do tc qdisc replace dev $interface parent "${QUEUE}" fq flow_limit 10000 maxrate 30gbit
    done
    ip link set dev $interface txqueuelen 10000
  done
  if [[ ! -f $HUND_SYSCTL_FILENAME ]]
    then touch $HUND_SYSCTL_FILENAME
  fi
  curl https://raw.githubusercontent.com/thousandeyes/On-net-installer/refs/heads/master/files/etc/sysctl.d/21-network_tuning_100gbps.conf > $HUND_SYSCTL_FILENAME
  echo "TCP tuning settings saved to $HUND_SYSCTL_FILENAME"
  sysctl -q -p
}

install_samknows_fairqueuing () {
  TC_FILENAME="samknows-interfacequeue"
  TC_FILE="/etc/init.d/$TC_FILENAME"
  if [[ ! -f "$TC_FILE" ]]
    then curl https://raw.githubusercontent.com/thousandeyes/On-net-installer/refs/heads/master/files/etc/init.d/samknows-interfacequeue > "$TC_FILE"
    chmod +x "$TC_FILE"
    update-rc.d "$TC_FILENAME" defaults
    eval "$TC_FILE"
  else 
    echo "File $TC_FILE exists already. Nothing to do."
    exit 2
  fi
}

install_samknows_firewallenable () {
  ufw --force enable >>/dev/null
}

install_samknows_firewallrules () {
  for o in $UFW_SUGGEST
    do eval $o >> /dev/null 2>&1
  done 
}

install_samknows_certbot () {
  certbot --agree-tos -n --nginx -d $FQDN_HOSTNAME -m $CERTBOT_EMAIL > /dev/null 2>&1
  if [[ $? -ne 0 ]]
    then
    echo "Error: certbot exited with an error doing:"
    echo "certbot --agree-tos -n --nginx --no-redirect -d $FQDN_HOSTNAME -m $CERTBOT_EMAIL"
    echo "Please run certbot to manually generate a SSL certificate."
    exit 1;
  fi
  sed -i '36,39s/# Samknows SSL configuration listen/        listen/g' $NGINX_FILENAME
  sed -i '/^#/d' $NGINX_FILENAME
  sed -i '63,$ d' $NGINX_FILENAME
  awk -v n=3 '/^server/{n--}; n > 0' $NGINX_FILENAME > $NGINX_FILENAME.new && mv $NGINX_FILENAME.new $NGINX_FILENAME
}

install_samknows_certbotcron () {
  SLEEPTIME=$(awk 'BEGIN{srand(); print int(rand()*(3600+1))}');
  echo "0 0,12 * * * root sleep $SLEEPTIME && certbot renew -q ; systemctl reload nginx" >> /etc/crontab
}

check_nginx_config () {
  NGINX_CHECK=$(dpkg -s nginx 2>&1)

  if [[ -z "$NGINX_CHECK" ]]
    then echo "Error: dpkg command failed. Please correct or remove before attempting to running again. Existing."
    echo
    echo echo $NGINX_CHECK
    exit 1
  fi
  if [[ "$NGINX_CHECK" != *"Status: install ok installed"* ]]
    then echo "Error: Nginx is required but not installed. Please correct or remove before attempting to running again. Exiting."
    exit 1
  fi

  NGINX_CONFIGCHECK=$(nginx -t 2>&1)
  if [[ $? -ne 0 ]]
  then
    echo "Error: Command nginx -t failed with error, configure looks corrupted. Please correct  before attempting to running again. Exiting."
    echo "$NGINX_CONFIGCHECK"
    exit 1;
  fi
}

check_hostname_resolves () {
  FQDN_HOSTNAME=$(hostname -f)
  if [[ -z "$FQDN_HOSTNAME" ]]
    then FQDN_HOSTNAME="localhost"
  fi
  host $FQDN_HOSTNAME 2>&1 >> /dev/null

  if [[ $? -ne 0 ]]
  then
    echo "Hostname of the system \"$FQDN_HOSTNAME\" does not resolve."
    echo -n "Enter the fully qualified hostname of this host or press enter to exit: "
    read FQDN_HOSTNAME
    if [[ -z $FQDN_HOSTNAME ]]
    then
      echo "Exiting."
      exit 1
    fi
    host $FQDN_HOSTNAME 2>&1 >> /dev/null
    if [[ $? -ne 0 ]]
    then
      echo "Error: Hostname $FQDN_HOSTNAME does not resolve. Can not continue. Exiting."
      exit 1;
    fi
  fi

  if [[ ! $FQDN_HOSTNAME = *"."* ]]
  then
    echo "Error: hostname \""$FQDN_HOSTNAME"\" needs at least one dot to continue. Please set the hostname correctly, e.g. \"hostnamectl hostname [hostname.domain.com]\". Exiting"
    exit 1
  fi
}
main "$@"; exit
