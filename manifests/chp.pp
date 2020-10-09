# Stand-alone configurable-http-proxy service for use with JupyterHub.
#
# See: https://jupyterhub.readthedocs.io/en/stable/reference/separate-proxy.html
class jupyterhub::chp (
    $chp_auth_token,
    $chp_maj_min_vers = '4.2',
    $chp_pub_port = 8000,
    $chp_pub_ip = 'all',
    $chp_api_port = 8001,
    $chp_api_ip = '127.0.0.1',
    $chp_default_target_host = 'localhost',
    $chp_default_target_port = 8081,
  ) {

  # Ensure nodejs and npm are installed
  include jupyterhub::nodejs

  # Install prefix for configurable-http-proxy
  file { '/opt/chp':
    ensure => 'directory',
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  # Install from package.json definition, _not_ using 'npm install -g ...',
  # as this way we can run 'npm audit' for vuln checking
  file { '/opt/chp/package.json':
    source  => 'directory',
    content => template('jupyterhub/chp-package.json.erb'),
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => File['/opt/chp'],
  }
  exec { 'install-chp':
    command => '/usr/bin/npm install',
    cwd     => '/opt/chp',
    require => File['/opt/chp/package.json'],
    unless  => "/usr/bin/npm list --depth=0 | grep @${chp_maj_min_vers}",
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
  service { 'chp.service':
    ensure => running,
    enable => true,
  }
}
