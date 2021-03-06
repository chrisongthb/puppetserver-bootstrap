#!/bin/bash
# https://github.com/chrisongthb/puppetserver-bootstrap
# puppetserver-bootstrap
# configure a single node puppetserver

set -e
set -u

_say () {
  echo
  echo '###################################################'
  echo -e $1
}

##########
_say 'reading properties file and lsb info...'
source /etc/lsb-release
source $(dirname $0)/puppetserver-bootstrap.properties

##########
_say 'preparing apt repos...'
curl -s ${_apt_key_puppetlabs} | apt-key add -
curl -s ${_apt_key_postgresql} | apt-key add -
apt-add-repository -n "${_apt_source_puppetlabs}"
apt-add-repository -n "${_apt_source_postgresql}"
apt-add-repository -n "${_apt_source_universe}"   # provides openjdk-8-jre-headless
apt-get update

##########
_say 'cleaning up old puppet stuff...'
apt-get purge -y puppet-agent puppetserver puppetdb
rm -rfv /etc/puppetlabs /opt/puppetlabs /var/tmp/puppetserver-bootstrap/

##########
_say 'installing puppet-agent and puppetserver...'
apt-get install -y puppet-agent puppetserver

##########
_say 'configuring puppetserver and installing puppetdb...'
/opt/puppetlabs/bin/puppet config set --section main server $(hostname -f)
/opt/puppetlabs/bin/puppetserver ca setup
apt-get install -y puppetdb

##########
_say 'preparing puppet apply (downloading puppet modules)...'
mkdir -v /var/tmp/puppetserver-bootstrap/
# to avoid certificate issues behind proxy
if export | grep -q 'https_proxy='; then
  rsync -a /etc/ssl/certs/ /opt/puppetlabs/puppet/ssl/certs/
fi
/opt/puppetlabs/bin/puppet module install --target-dir /var/tmp/puppetserver-bootstrap/ puppetlabs-concat --version '5.3.0'
/opt/puppetlabs/bin/puppet module install --target-dir /var/tmp/puppetserver-bootstrap/ puppet-r10k --version '6.8.0'
/opt/puppetlabs/bin/puppet module install --target-dir /var/tmp/puppetserver-bootstrap/ puppet-puppetserver --version '3.0.1'
/opt/puppetlabs/bin/puppet module install --target-dir /var/tmp/puppetserver-bootstrap/ puppetlabs-puppetdb --version '7.2.0'
/opt/puppetlabs/bin/puppet module install --target-dir /var/tmp/puppetserver-bootstrap/ puppetlabs-lvm --version '1.2.0'
/opt/puppetlabs/bin/puppet module install --target-dir /var/tmp/puppetserver-bootstrap/ puppet-hiera --version '3.4.1'
/opt/puppetlabs/bin/puppet module install --target-dir /var/tmp/puppetserver-bootstrap/ puppetlabs-puppet_authorization --version '0.5.0'
/opt/puppetlabs/bin/puppet module install --target-dir /var/tmp/puppetserver-bootstrap/ puppetlabs-inifile --version '2.5.0'

##########
_say 'starting puppet apply...'
set +e
/opt/puppetlabs/bin/puppet apply --detailed-exitcodes --modulepath=/var/tmp/puppetserver-bootstrap/ $(dirname $0)/puppetserver-bootstrap.pp
_rc=$?
if [ $_rc -ge 4 -o $_rc -eq 1 ]; then
  _say "something went wrong!\ndebug the error above and retry the puppet apply via:\n\n    /opt/puppetlabs/bin/puppet apply --modulepath=/var/tmp/puppetserver-bootstrap/ $(dirname $0)/puppetserver-bootstrap.pp\n"
  read -p 'OK? [press enter]'
else
  _say 'installation and configuration finished!'
fi
set -e

##########
_say 'printing systemd status of all puppet components...'
systemctl --no-pager status puppet.service puppetserver.service puppetdb.service webhook || true
