# puppetserver-bootstrap
Provides a bash script and a puppet manifest to install and configure a puppet server from scratch.  
Installs/configures:
* lvm
* puppet-agent
* puppetserver
* postgresql
* puppetdb
* r10k

## Getting Started
`/opt/puppetlabs/puppet/bin/gem` works only on ubuntu with ipv6 disabled or removed ipv6 address. So your first thing here is checking you haven't got an ipv6 address (`ip a`). If you have one remove it by typing `ip address del <ipv6 address> dev <device>`.

If you are sure you don't want to adjust anything to your installation, start the installation by  
``
bash puppetserver-bootstrap.sh
``

## Configuration
I highly recommend, that you go through the variables and configure your installation.  
Check your infrastructure. Do You need a internet proxy? Do you have got your own apt-mirror? Configure it in `puppetserver-bootstrap.properties`. Setup the puppetserver heap, the connection to your control-repo and the postgresql version in the first section of `puppetserver-bootstrap.pp`.  
Start the installation by typing `bash puppetserver-bootstrap.sh`

## Limitations
* r10k user is hardcoded 'root' (ssh key, ssh known hosts, webhook)
* iptables are not going to be configured
* /opt/puppetlabs/puppet/bin/gem works only on ubuntu with ipv6 disabled or removed ipv6 address, see [Getting Started](#Getting-Started).
* Tested and verified on Ubuntu 18.04; should be working on other Ubuntu versions, too.