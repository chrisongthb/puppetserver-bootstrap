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

class { 'r10k':
  manage_modulepath => false,
  sources           => {
    'puppet' => {
      'remote'  => $r10k_git_control_repo_url,
      'basedir' => "${::settings::confdir}/environments",
      'prefix'  => false,
    },
  },
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

  file { '/etc/puppetlabs/code':
    require => Package['puppetserver'],
    ensure  => 'link',
    group   => 'root',
    owner   => 'root',
    target  => '/var/puppetcode',
    force   => true, # replace existing directory with link
  }

  file { '/etc/puppetlabs/puppetdb':
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
