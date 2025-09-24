# On-net Servers Guide for SamKnows Clients
Many ISPs want to install test servers inside their network (hence "on-net") to allow them to segregate on-net and off-net performance. SamKnows provides a script to install an On-net Server.

## Why use on-net?

The overwhelming majority of test servers used by SamKnows customers are off-net, i.e. hosted on the public internet in some fashion.  We believe that reporting results to targets off an ISP's own network represents a "real world" experience for end users. However, we do recommend that ISPs install and test against on-net servers as well as off-net. With both on-net and off-net servers in use, customers can see the difference between the performance of the ISP's own network and that of the public internet. The results can be used to troubleshoot peering links, routing issues, or simply rule out any capacity problems within the ISP's own network.

## Requirements

On-net test servers can be either virtual machines or dedicated hardware. For dedicated servers, we strongly recommend that they only operate as test servers and are not used for any unrelated purpose (for example, as a web server or file server).

The minimum specification of a 10Gbps test server is as follows:

* CPU: Quad Core Xeon (2GHz+)
* RAM: 16GB
* Disk: 250GB SSD
* Operating System: Ubuntu 22.04 LTS (preferred), Ubuntu 20.04, Rocky Linux 9.x
* Connectivity: 10Gbps minimum, 100Gbps preferred*
* IPv4 and IPv6 connectivity

For larger deployments, 100Gbps test servers are preferred. The recommended minimum specifications for 100Gbps servers is as follows:

* CPU: 20+ cores at 2.4GHz+
* RAM: 64GB
* Disk: 250GB SSD
* Operating System: Ubuntu 22.04 LTS (preferred), Ubuntu 20.04, Rocky Linux 9.x
* Connectivity: 100Gbps, with an nVidia/Mellanox ConnectX-5/6/7 card
* IPv4 and IPv6 connectivity

At a minimum, one publicly routable IPv4 address must be provisioned per server. The test server must not be presented with a NAT'd address. It is preferable for any new test servers to also be provisioned with an IPv6 address at installation time. DNS records must be configured for each server before installation of SamKnows applications can proceed. We recommend using separate DNS records for IPv4 and IPv6, for example v4-servername.company.com and v6-servername.company.com to make it clear which protocol is being used at any time.

We now allow installation on Ubuntu 24.04, however this is with the caveat that this has not been extensively tested for performance. At present, we cannot guarantee performance in parity with Ubuntu 22.04, and support would be provided on a best efforts basis until we do formally support 24.04.

# Server Management
## Provisioning on-net test servers

ISPs are requested to complete an information form for each test server they wish to provision on their network. This will be provided by your SamKnows account manager.

## Installation

Installation proceeds as follows:
Ensure that your test servers meet the minimum specifications.
Ensure your servers have the necessary firewall and/or ACL rules permitted.

Downloading and executing the script can be done by cutting and pasting the following commands as the root user on the host you wish to install, using the filename associated with the chosen operating system (Ubuntu or Rocky):

### For Ubuntu (22.04 or 20.04)
```
curl -O -s https://raw.githubusercontent.com/SamKnows/On-net-installer/master/test_server_installer_ubuntu.sh
chmod +x test_server_installer_ubuntu.sh
./test_server_installer_ubuntu.sh
```

### For Rocky Linux 9
```
curl -O -s https://raw.githubusercontent.com/SamKnows/On-net-installer/master/test_server_installer_rocky_9.sh
chmod +x test_server_installer_rocky_9.sh
./test_server_installer_rocky_9.sh
```


Tracing the Installation Script Step-by-Step:

```
## Usage

The test_server_install.sh script needs to be run by the root user to work. On execution of the script you will be presented with three options.

1) Install
2) Verbose Install
3) Exit

It is recommended you select “1) Install”, which will then automatically make a number of changes to allow the On Net Server software to install.

You may also choose “2) Verbose Install”, which will present each change in full before the change is made and you will be presented with an option to allow the change or not.

The third option is to do nothing and exit.

The installation script will make the following changes:

* Adds the SamKnows repo
* Installs SamKnows test server software from the repo
* Adds recommended sysctl changes for network tuning
* Enables firewall UFW and allows access to ports needed using UFW
* Installs Nginx (with optional SSL configuration)
* Installs latest kernel with “fair queuing” enabled

# Firewalls & Network Information

## Firewalling of on-net test servers

It is preferred that the test servers do not sit behind a hardware firewall or a network Access Control List as firewalling is usually managed on the testserver. If a firewall is used, then care must be taken to ensure it can sustain the throughput required above. Additionally, the following rules must be permitted at a minimum:

## Inbound firewall rules required

Note: We recommend opening a range of TCP and UDP ports for proper operation of our services. We list the primary ports used by our applications for informative purposes.

| Source IP | Protocol(s) | Port(s)   | Purpose                                             |
| --------- | ----------- | --------- | --------------------------------------------------- |
| ALL       | TCP         | 80, 443   | Test Traffic to Nginx (HTTP + HTTPS)                |
| ALL       | TCP & UDP   | 5000-7000 | Test Traffic (SamKnows Applications)                |
| ALL       | TCP         | 8080      | Test Traffic (SamKnows HTTP Server)                 |
| ALL       | TCP         | 8000      | Test Traffic (SamKnows UDP Server Control Port)     |
| ALL       | UDP         | 8001      | Test Traffic (SamKnows UDP Server Measurement Port) |

## Outbound Firewall Rules

Note: These are only required if outbound access is denied by default. We recommend that outbound traffic be enabled by default. Please ensure that the host has functioning DNS resolvers (for example, Google DNS at 8.8.8.8).

The firewalling should allow for the traffic from the Test applications on ports listed in the Inbound rules to reach the devices that will be using this server as a target.

| Destination IP | Protocol(s) | Port(s) | Purpose                     |
| -------------- | ----------- | ------- | --------------------------- |
| ALL            | TCP         | 80, 443 | SamKnows Package Repository |

# System Adminstration

The server applications are managed by systemd.

Please avoid disabling any of the following essential processes or systemd units which implement the measurement servers:
* skhttp_server
* skjitter_server
* sklatency_server
* sklightweightcapacity_server
* skudpspeed_server
* skwebsocket_speed_server
* dart
