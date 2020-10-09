# Install NodeJS after setting up nodesource RPM repository
#
# See: https://github.com/nodesource/distributions
class jupyterhub::nodejs(
  $nodejs_maj_vers = 14,
) {
  # Ensure GPG key file for nodesource repo is on filesystem
  file { '/tmp/nodesource.key':
    mode   => '0600',
    owner  => 'root',
    group  => 'root',
    source => 'puppet:///modules/jupyterhub/jupyterhub/RPM-GPG-KEY-CentOS-7',
  }

  # Install GPG key for nodesource repo
  exec { 'inst_repo_key':
    command => '/usr/bin/rpm --import /tmp/nodesource.key',
    require => File['/tmp/nodesource.key'],
    creates => '/etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7'
  }

  # Define nodesource repo
  file { '/etc/yum.repos.d/nodesource-el7.repo':
    mode    => '0644',
    owner   => 'root',
    group   => 'root',
    content => template('jupyterhub/nodesource-el7.repo.erb'),
  }

  # Ensure NodeJS RPM installed from nodesource repo
  package { 'nodejs':
    ensure  => 'installed',
    require => [
      File['/etc/yum.repos.d/nodesource-el7.repo'],
      Exec['inst_repo_key'],
    ]
  }
}
