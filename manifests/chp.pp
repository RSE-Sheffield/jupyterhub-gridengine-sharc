# Stand-alone configurable-http-proxy service for use with JupyterHub.
#
# See: https://jupyterhub.readthedocs.io/en/stable/reference/separate-proxy.html
class jupyterhub::chp (
    $chp_auth_token,
    $chp_vers = '4.2.1',
    $chp_pub_port = 8000,
    $chp_pub_ip = 'all',
    $chp_api_port = 8001,
    $chp_api_ip = '127.0.0.1',
    $chp_default_target_host = 'localhost',
    $chp_default_target_port = 8081,
  ) {

  # Ensure npm installed
  Package { ensure => 'installed' }
  $rpm_pkgs = [ 'epel-release', 'npm' ]
  package { $rpm_pkgs: }

  # Ensure configurable-http-proxy installed using npm.
  # Installs into /usr/lib/node_modules/configurable-http-proxy/
  # and creates /usr/bin/configurable-http-proxy symlink.
  exec { 'install-chp':
    command => "/usr/bin/npm install -g configurable-http-proxy@${chp_vers}",
    path    => [ '/bin', '/usr/bin' ],
    require => Package['npm'],
    creates => '/usr/lib/node_modules/configurable-http-proxy/bin/configurable-http-proxy',
  }

  # Group and user to run service as
  group { 'chp':
    gid => 1704
  }
  user { 'chp':
    uid   => '11112',
    gid   => '1704',
    shell => '/sbin/nologin',
    home  => '/dev/null',
  }

  # Environment file
  file { '/etc/default/chp':
    mode    => '0600',
    owner   => 'root',
    group   => 'root',
    content => "CONFIGPROXY_AUTH_TOKEN='${chp_auth_token}'",
  }
  file { '/etc/systemd/system/chp.service':
    mode    => '0644',
    owner   => 'root',
    group   => 'sysadmins',
    content => template('jupyterhub/chp.service.erb'),
    require => [
      Exec['install-chp'],
      File['/etc/default/chp'],
      User['chp'],
    ],
    notify  => Exec['systemd-daemon-reload'],
  }
  exec { 'systemd-daemon-reload':
    command     => 'systemctl daemon-reload',
    path        => [ '/bin', '/usr/bin' ],
    refreshonly => true,
  }
  service { 'jupyterhub.service':
    ensure => running,
    enable => true,
  }
  }
