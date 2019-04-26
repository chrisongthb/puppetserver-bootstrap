# https://github.com/chrisongthb/puppetserver-bootstrap
# puppetserver-bootstrap
# configure a single node puppetserver

##############################
# adjust the installation and configuration
$configure_lvm             = false    # see below for details
$r10k_git_control_repo_url = 'git@myGitlabInstance.myDomain:myGitGroup/control-repo.git'
$git_ssh_hostkey_aliases   = [ 'myGitlabInstance', 'myGitlabInstance.myDomain', '1.2.3.4' ]
$git_ssh_hostkey_string    = 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'
$git_ssh_hostkey_type      = 'ecdsa-sha2-nistp256'
$puppetdb_postgres_version = '11'
$puppetserver_jvm_heap     = '2g'
$puppetdb_jvm_heap         = '2g'

##############################
# configure puppetserver
class { 'puppetserver':
  before  => Class['puppetdb'],
  require => Class['lvm'],
  config  => {
               'java_args' => {
                 'xms'    => $puppetserver_jvm_heap,
                 'xmx'    => $puppetserver_jvm_heap,
                 'tmpdir' => '/tmp/',
               },
             },
}

##############################
# configure hiera
class { 'hiera':
  require   => Class['puppetserver'],
  eyaml     => true,
  hierarchy => [
    'nodes/%{::clientcert}',
    'locations/%{::domain}',
    'common',
  ],
}

##############################
# configure puppetdb
file { '/etc/cron.allow':
  ensure => file,
  mode   => '0644',
  owner  => 'root',
  group  => 'root',
}

file_line { 'cron.allow puppetdb':
  ensure => present,
  path   => '/etc/cron.allow',
  line   => 'puppetdb',
  before => Class['puppetdb'],
}

class { 'puppetdb':
  require             => Class['lvm'],
  postgres_version    => $puppetdb_postgres_version,
  manage_package_repo => false,  # do not touch apt sources
  java_args           => {
                           '-Xms' => $puppetdb_jvm_heap,
                           '-Xmx' => $puppetdb_jvm_heap,
                         },
}

# configure puppetdb on the same (local)host as puppetserver
class { 'puppetdb::master::config':
  require => Class['lvm'],
}

##############################
# configure r10k webhook
sshkey { 'git_host_key':
  ensure       => present,
  host_aliases => $git_ssh_hostkey_aliases,
  key          => $git_ssh_hostkey_string,
  type         => $git_ssh_hostkey_type,
  target       => '/root/.ssh/known_hosts',
}

exec { 'generate_ssh_keypair':
  onlyif   => '! [ -f /root/.ssh/id_rsa -a -f /root/.ssh/id_rsa.pub ]',
  command  => 'ssh-keygen -q -t rsa -b 8192 -f /root/.ssh/id_rsa -N ""',
  provider => 'shell',
}

# https://github.com/puppetlabs/r10k/blob/master/doc/dynamic-environments/configuration.mkd#postrun
class { 'r10k':
  manage_modulepath => false,
  postrun           => ['/usr/local/sbin/puppet_flush_environment_cache', '$modifiedenvs' ],
  sources           => {
    'puppet' => {
      'remote'  => $r10k_git_control_repo_url,
      'basedir' => "${::settings::confdir}/code/environments",
      'prefix'  => false,
    },
  },
}

puppet_authorization::rule { 'enable clearing environment cache':
  path                  => '/etc/puppetlabs/puppetserver/conf.d/auth.conf',
  match_request_path    => '/puppet-admin-api/v1/environment-cache',
  match_request_type    => 'path',
  match_request_method  => 'delete',
  allow                 => $::fqdn,
  allow_unauthenticated => false,
  sort_order            => 200,
  notify                => Service['puppetserver'],
}

ini_setting { 'enable environment caching':
  ensure => 'present',
  path    => '/etc/puppetlabs/puppet/puppet.conf',
  section => 'master',
  setting => 'environment_timeout',
  value   => 'unlimited',
  notify  => Service['puppetserver'],
}

file { '/usr/local/sbin/puppet_flush_environment_cache':
  ensure  => file,
  mode    => '0755',
  owner   => 'root',
  group   => 'root',
  content => '#!/usr/bin/env bash
# https://www.example42.com/2017/03/27/environment_caching/
# https://github.com/example42/psick/blob/production/bin/puppet_flush_environment_cache.sh

# https://puppet.com/docs/puppetserver/latest/admin-api/v1/environment-cache.html
# https://puppet.com/docs/puppetserver/6.1/config_file_auth.html

hostcert="$(puppet config print hostcert)"
key="$(puppet config print hostprivkey)"
cacert="$(puppet config print cacert)"
ppserver="$(puppet config print server)"

if [ $# -eq 0 ]; then
  curl --cert ${hostcert} --key ${key} --cacert ${cacert} -X DELETE https://${ppserver}:8140/puppet-admin-api/v1/environment-cache
else
  for i in $@; do
    curl --cert ${hostcert} --key ${key} --cacert ${cacert} -X DELETE https://${ppserver}:8140/puppet-admin-api/v1/environment-cache?environment=$i
  done
fi
',
}

class {'r10k::webhook':
  user  => 'root',
  group => 'root',
}

class {'r10k::webhook::config':
  generate_types   => true,
  use_mcollective  => false,
  public_key_path  => "/etc/puppetlabs/puppet/ssl/ca/signed/${::fqdn}.pem",
  private_key_path => "/etc/puppetlabs/puppet/ssl/private_keys/${::fqdn}.pem",
}


##############################
# configure lvms
if $configure_lvm {
  class { 'lvm':
    volume_groups => {
      'datavg' => {
        physical_volumes => [ '/dev/sdb', ],
        logical_volumes  => {
          'puppetcode' => {
            'size'              => '100G',
            'fs_type'           => 'ext4',
            'mountpath'         => '/var/puppetcode', # autorequire to mountpoints
            'mountpath_require' => true,
          },
          'puppetdb' => {
            'size'              => '20G',
            'fs_type'           => 'ext4',
            'mountpath'         => '/var/puppetdb', # autorequire to mountpoints
            'mountpath_require' => true,
          },
        },
      },
    },
  }

  ##############################
  # manage directories and links
  file { '/var/puppetcode':
    ensure => 'directory',
    group  => 'root',
    owner  => 'root',
    mode   => '0755',
  }

  file { '/var/puppetdb':
    ensure => 'directory',
    group  => 'postgres',
    owner  => 'postfix',
    mode   => '0755',
  }

  file { '/etc/puppetlabs/puppet/code':
    require => Package['puppetserver'],
    ensure  => 'link',
    group   => 'root',
    owner   => 'root',
    target  => '/var/puppetcode',
    force   => true, # replace existing directory with link
  }
  
  file { '/etc/puppetlabs/code':
    require => Package['puppetserver'],
    ensure  => 'link',
    group   => 'root',
    owner   => 'root',
    target  => '/var/puppetcode',
    force   => true, # replace existing directory with link
  }

  file { '/etc/puppetlabs/puppetdb/postgresql/':
    require => Package['puppetserver'],
    ensure  => 'link',
    group   => 'root',
    owner   => 'root',
    target  => '/var/puppetdb',
    force   => true, # replace existing directory with link
  }
}
else {
  class { 'lvm': }   # to satisfy dependencies
}
