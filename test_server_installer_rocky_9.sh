# Rocky Linux Installer script
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
  echo "Supported versions of Rocky Linux are 8 and 9 (preferred). Exiting."
  exit 2

}

# Am I running on Rocky Linux 8 or 9?
OS_NAME=$(grep "^NAME=" /etc/os-release | awk -F'=' '{ print $2 }' | tr -d '"')
ROCKY_VERSION_ID=$(grep "^VERSION_ID" /etc/os-release | awk -F'=' '{ print $2 }' | tr -d '"' | cut -c1)
MAJOR_VERSION=$(printf "%0.f" "$ROCKY_VERSION_ID")


if [ "$OS_NAME" != "Rocky Linux" ]; then
  unsupported_error
elif [ "$MAJOR_VERSION" == "8" ]; then
  OEM="linux-oem-20.04b"
elif [ "$MAJOR_VERSION" == "9" ]; then
  OEM="linux-oem-22.04b"
else
  unsupported_error
fi

echo "Rocky Linux version $MAJOR_VERSION found. Proceeding."

REPO_ADDRESS="https://yum-repo.samknows.com"
SYSCTL_NAME=(net.core.rmem_max net.core.wmem_max net.core.rmem_default net.core.wmem_default net.core.netdev_max_backlog net.core.somaxconn net.ipv4.udp_rmem_min net.ipv4.udp_wmem_min net.ipv4.tcp_congestion_control net.ipv4.tcp_sack net.ipv4.tcp_timestamps net.ipv4.tcp_slow_start_after_idle net.ipv4.tcp_no_metrics_save net.ipv4.tcp_tw_reuse net.ipv4.tcp_fin_timeout net.ipv4.tcp_window_scaling net.core.default_qdisc)
SYSCTL_VALUE=(26214400 26214400 524288 524288 40000 14000 128 128 cubic 1 1 1 0 0 60 1 fq)
FW_RULES=(80/tcp 443/tcp 5000-7000/tcp 5000-7000/udp 8080/tcp 8000/tcp 8001/udp 22/tcp)
SAMKNOWS_PACKAGES=(skhttp_server skjitter_server sklatency_server sklightweightcapacity_server skudpspeed_server skwebsocket_speed_server)
EXTRA_PACKAGES=(nginx certbot python3-certbot-nginx gawk firewalld)
SYSCTL_FILE="/etc/sysctl.d/20-network_tuning.conf"
CERTBOT_EMAIL="jamie@samknows.com"
MAIN_INTERFACE=$(ip route get 8.8.8.8 | awk -- '{printf $5}')

FQ_FILE="/etc/NetworkManager/dispatcher.d/pre-up.d/50-add_fair_queuing.sh"

NGINX_FILENAME="/etc/nginx/conf.d/90_samknows_nginx.conf"
WEBTEST_FILENAME="/usr/share/nginx/html/web_test/"
NGINX_CONTENTS='map $http_upgrade $connection_upgrade {
        default upgrade;
        '"'"''"'"' close;
}

add_header Access-Control-Allow-Origin "*";
# Samknows SSL configuration add_header Strict-Transport-Security "max-age=15552000; includeSubdomains; ";

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

INSTALL_DIR=/opt/samknows/installer
mkdir -p $INSTALL_DIR

rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
rpm --import https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9
dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
dnf install -y https://www.elrepo.org/elrepo-release-9.el9.elrepo.noarch.rpm
sed -i 's/^mirrorlist/#mirrorlist/g' /etc/yum.repos.d/elrepo.repo # elrepo's mirror list can cause problems

write_config_files
check_hostname_resolves
find_default_interface

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

if [[ ! -f /etc/yum.repos.d/samknows.repo  ]]
  then if $MANUAL_INSTALL
    then
    echo
    echo "This script will install SamKnows software from the SamKnows Package Repository, which needs to be enabled before we can proceed. The repository is hosted by SamKnows at repo.samknows.com."
    echo "The added repository will live in /etc/yum.repos.d/samknows.repo"
    echo
    echo "Add the SamKnows Package Repository now?"
    select yn in "Yes" "No"; do
      case $yn in
        "Yes" ) install_samknows_repo; break;;
        "No" ) exit; break;;
     esac
    done
    else install_samknows_repo
    echo "Installing SamKnows Package Repository."
    fi
  else
  echo "SamKnows Package Repository already installed, does not need installing."
fi

if $MANUAL_INSTALL
    then
    echo
    echo "The following command needs to be run to install recommended SamKnows Operating System Packages:"
    echo
    echo yum install $PACKAGES_SUGGEST
    echo
    echo "This will also install the latest available mainline kernel from EL Repo"
    echo
    echo "dnf --enablerepo=elrepo-kernel install kernel-ml && grubby --default-kernel"
    echo
    echo "Would you like these packages installed now?"
    select yn in "Yes" "No"; do
      case $yn in
        "Yes" ) install_samknows_packages; break;;
        "No" ) exit; break;;
     esac
    done
    else install_samknows_packages
    echo "Installing recommended SamKnows Operating System Packages."
fi


check_nginx_config;

if [[ ! -f "$NGINX_FILENAME" ]]
  then if $MANUAL_INSTALL
    then echo "Would you like to create $NGINX_FILENAME to configure Nginx, link the config in /etc/nginx/sites-enabled/ so it loads and create test data for clients to request? If you have modified the configuration of Nginx in any way generation of Nginx may fail and would need to be done manually."
    echo
    echo
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
        "No" ) exit; break;;
      esac
    done
    else install_samknows_nginx
    echo "Installing Nginx webserver."
  fi
  else echo "Nginx looks to be configured already"
fi

if $MANUAL_INSTALL
  then echo "SamKnows recommends the following linux kernel settings:"
  echo
  curl https://raw.githubusercontent.com/thousandeyes/On-net-installer/refs/heads/master/files/etc/sysctl.d/20-network_tuning.conf
  echo
  echo "Would you like to save these settings to $SYSCTL_FILE and apply them so they are loaded on reboot?"
  select yn in "Yes" "No"; do
    case $yn in
      "Yes" ) install_samknows_sysconfig ; break;;
      "No" ) exit; break;;
    esac
  done
else install_samknows_sysconfig
  echo "Applying recommended Linux tuning parameters."
fi


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
        "No" ) exit; break;;
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
        "No" ) exit; break;;
      esac
    done
  else install_samknows_fairqueuing
  echo "Applying to all interfaces Fair Queuing queuing algorithm."
  fi
  else echo "Fair Queuing on all interfaces already applied correctly."
  fi
fi

FW_CHECK=$(firewall-cmd --list-all 2>&1)
if [[ -z "$FW_CHECK" ]]
  then echo
  echo "firewalld not installed, run \"yum install firewalld\" to install if required."
  echo
  exit;
fi

if [ "$FW_CHECK" = "Status: inactive" ]
  then if $MANUAL_INSTALL
    then
    echo
    echo "firewalld is currently disabled. Do you wish to enable it? Warning: Enabling firewalld may break any other local firewall software. This step is optional."
    select yn in "Yes" "No"; do
      case $yn in
        "Yes" ) install_samknows_firewallenable ; break;;
        "No" ) echo ; echo "All done" ; echo ; exit;;
     esac
    done
    echo
  else install_samknows_firewallenable
  echo "Enabling firewalld."
  fi
  else echo "firewalld is already enabled, nothing to do."
fi

i=0
until [[ $i = 12 ]]
do
  FW_RULE_FOUND=0
  for o in $FW_CHECK
  do
    if [[ "$o" = "${FW_RULES[$i]}"* ]]
      then FW_RULE_FOUND=1
    fi
    done
  if [[ $FW_RULE_FOUND -eq 0 ]]
    then
      FW_SUGGEST="firewall-cmd --permanent --zone=public --add-port=${FW_RULES[$i]}
$FW_SUGGEST"
 fi
  ((i=i+1))
done

if [[ ! -z "$FW_SUGGEST" ]]
  then if $MANUAL_INSTALL
    then echo "SamKnows recommends using these firewalld rules to allow SamKnows Measurement Server Applications and associated server management to function correctly:"
    echo
    echo "$FW_SUGGEST"
    echo "Apply the suggested rules to firewalld now? These rules will persist even after a reboot."
    echo "Please review and ensure that any existing firewall rules do not conflict with the proposed additions."
      select yn in "Yes" "No"; do
        case $yn in
        "Yes" ) install_samknows_firewallrules ; break;;
        "No" ) exit;;
     esac
    done
  else install_samknows_firewallrules
  echo "Installing Samknows firewalld rules."
  fi
  else echo "No firewalld rule modifications to suggest."
fi

if [[ ! -d "/etc/letsencrypt/live/$FQDN_HOSTNAME" ]]
  then if $MANUAL_INSTALL
    then echo
    echo "SamKnows recommends using LetsEncrypt to handle SSL certificate generation. Allow this script to generate an SSL certificate and configure Nginx to use it? This step is optional."
      select yn in "Yes" "No" "Skip"; do
        case $yn in
        "Yes" ) install_samknows_certbot ; break;;
        "No" ) exit;;
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
        "No" ) exit;;
      esac
        done
  else install_samknows_certbotcron
    echo "Installing Letsencrypt script in /etc/crontab to auto renew certificate."
    fi
    else echo "Looks like a script in /etc/crontab is already renewing Letsencrypt, nothing to do."
  fi
fi



echo "Installation completed. It is highly recommended that this host be rebooted to ensure all changes take effect."

} # Main End

write_config_files() {

  echo "${SYSCTL_CONTENTS}" > ${INSTALL_DIR}/20_samknows_sysctl_network_tuning.conf
  echo "${NGINX_CONTENTS}" > ${INSTALL_DIR}/90_samknows_nginx.conf

}

find_default_interface() {

    DEFAULT_IFACE=$(/usr/sbin/route -n | grep "^0.0.0.0" | grep "UG" | awk '{ print $NF }')
    TC_SUGGEST="tc qdisc replace dev ${DEFAULT_IFACE} root fq"
}

install_samknows_repo () {

yum -y install epel-release

    echo -ne "[samknows]
name=SamKnows Rocky Linux ${MAJOR_VERSION} Server Binaries
baseurl=http://repo.samknows.com/rocky-repo/${MAJOR_VERSION}/
gpgcheck=0
enabled=1
metadata_expire=6h" > /etc/yum.repos.d/samknows.repo

}

install_samknows_packages () {

  for f in ${EXTRA_PACKAGES[@]}; do
    dnf install -qy $f
  done

  for f in ${SAMKNOWS_PACKAGES[@]}; do
    dnf install -qy $f
    systemctl enable $f
    systemctl start $f
  done

  dnf -qy --enablerepo=elrepo-kernel install kernel-ml
  grubby --default-kernel

}

install_samknows_nginx () {
  cp ${INSTALL_DIR}/90_samknows_nginx.conf /etc/nginx/conf.d/
  systemctl restart nginx
  mkdir -p /usr/share/nginx/html/web_test/
  if [ ! -s "$WEBTEST_FILENAME/100MB.bin" ]; then
    dd if=/dev/urandom of=$WEBTEST_FILENAME/100MB.bin bs=100M count=1 iflag=fullblock status=none >> /dev/null
  fi
  if [ ! -s "$WEBTEST_FILENAME/1000MB.bin" ]; then
    dd if=/dev/urandom of=$WEBTEST_FILENAME/1000MB.bin bs=100M count=10 iflag=fullblock status=none >> /dev/null
  fi
  touch $WEBTEST_FILENAME/index.html
  hostname > $WEBTEST_FILENAME/hostname
}

install_samknows_sysconfig () {
  if [[ ! -f $SYSCTL_FILE ]]
    then
    curl https://raw.githubusercontent.com/thousandeyes/On-net-installer/refs/heads/master/files/etc/sysctl.d/20-network_tuning.conf > $SYSCTL_FILE ;
    sysctl -q -p $SYSCTL_FILE
  else
    echo "File $SYSCTL_FILE exists already, skipping."
  fi

}

install_samknows_fairqueuing () {
  if [[ ! -f "$FQ_FILE" ]]
    then curl https://raw.githubusercontent.com/thousandeyes/On-net-installer/refs/heads/master/files/etc/init.d/samknows-interfacequeue > "$FQ_FILE"
    chmod +x "$FQ_FILE"
    eval "$FQ_FILE"
  else
    echo "File $FQ_FILE exists but Fair Queuing is not enabled. Can not proceed."
    exit 2
  fi
}

install_samknows_firewallenable () {
  systemctl enable firewalld >>/dev/null
}

install_samknows_firewallrules () {
  for o in $FW_SUGGEST
    do eval $o >> /dev/null 2>&1
  done
  firewall-cmd --reload
}

apply_100g_tweaks () {
  TC_FILENAME="samknows-interfacequeue-100g"
  TC_FILE="/etc/NetworkManager/dispatcher.d/pre-up.d/50-add_fair_queuing.sh"
  if [[ ! -f "$TC_FILE" ]]
    then curl https://raw.githubusercontent.com/thousandeyes/On-net-installer/refs/heads/master/files/etc/init.d/samknows-interfacequeue-100g > "$TC_FILE"
    chmod +x "$TC_FILE"
    eval "$TC_FILE"
    echo "Fair Queuing settings saved to $TC_FILE"
  else 
    echo "File $TC_FILE exists but Fair Queuing is not enabled. Can not proceed."
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

install_samknows_certbot () {
  certbot --agree-tos --hsts -n --nginx -d $FQDN_HOSTNAME -m $CERTBOT_EMAIL > /dev/null 2>&1
  if [[ $? -ne 0 ]]
    then
    echo "Error: certbot exited with an error when running:"
    echo "certbot --agree-tos --hsts -n --nginx --no-redirect -d $FQDN_HOSTNAME -m $CERTBOT_EMAIL"
    echo "Please run certbot to manually generate a SSL certificate."
    exit 1;
  fi
  sed -i '30,30s/# Samknows SSL configuration listen/        listen/g' $NGINX_FILENAME
  sed -i '37,40s/# Samknows SSL configuration add_header/        add_header/g' $NGINX_FILENAME
  sed -i '/^#/d' $NGINX_FILENAME
  sed -i '64,$ d' $NGINX_FILENAME
  awk -v n=3 '/^server/{n--}; n > 0' $NGINX_FILENAME > $NGINX_FILENAME.new && mv $NGINX_FILENAME.new $NGINX_FILENAME
}

install_samknows_certbotcron () {
  SLEEPTIME=$(awk 'BEGIN{srand(); print int(rand()*(3600+1))}');
  echo "0 0,12 * * * root sleep $SLEEPTIME && certbot renew -q ; systemctl reload nginx" >> /etc/crontab
}

check_nginx_config () {
  NGINX_CHECK=$(rpm -qa nginx 2>&1)

  if [[ -z "$NGINX_CHECK" ]]
    then echo "Error: rpm command failed. Please correct or remove before attempting to running again. Exiting."
    echo
    echo echo $NGINX_CHECK
    exit 1
  fi
  if [[ "$NGINX_CHECK" == "" ]]
    then echo "Error: Nginx is required but not installed. Please correct or remove before attempting to running again. Exiting."
    exit 1
  fi

  NGINX_CONFIGCHECK=$(nginx -t 2>&1)
  if [[ $? -ne 0 ]]
  then
    echo "Error: Command nginx -t failed with an error, configuration looks corrupted. Please correct before attempting to running again. Exiting."
    echo "$NGINX_CONFIGCHECK"
    exit 1;
  fi
}

check_hostname_resolves () {

  HOST_CHECK=$(rpm -qa | grep bind-utils)

  if [ "$HOST_CHECK" = "" ]; then
    yum install -y bind-utils
  fi

  FQDN_HOSTNAME=$(hostname -f)
  if [[ -z "$FQDN_HOSTNAME" ]]
    then FQDN_HOSTNAME="localhost"
  fi
  DNS_OUT=$(host $FQDN_HOSTNAME | grep "has address" 2>&1 >/dev/null; echo $?)



  if [[ "${DNS_OUT}" != "0" ]]
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
