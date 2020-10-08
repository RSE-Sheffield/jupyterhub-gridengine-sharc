# Stand-alone configurable-http-proxy service for use with JupyterHub.
#
# See: https://jupyterhub.readthedocs.io/en/stable/reference/separate-proxy.html
class jupyterhub::configurable_http_proxy (
    $chproxy_auth_token,
    $chproxy_vers = '4.2.1',
    $chproxy_pub_port = 8000,
    $chproxy_pub_ip = 'all',
    $chproxy_api_port = 8001,
    $chproxy_api_ip = '127.0.0.1',
    $chproxy_default_target_host = 'localhost',
    $chproxy_default_target_port = 8081,
  ) {

  # Ensure npm installed
  Package { ensure => 'installed' }
  $rpm_pkgs = [ 'epel-release', 'npm' ]
  package { $rpm_pkgs: }

  # Ensure configurable-http-proxy installed using npm.
  # Installs into /usr/lib/node_modules/configurable-http-proxy/
  # and creates /usr/bin/configurable-http-proxy symlink.
  exec { 'install-chproxy':
    command => "/usr/bin/npm install -g configurable-http-proxy@${chproxy_vers}",
    path    => [ '/bin', '/usr/bin' ],
    require => Package['npm'],
    creates => '/usr/lib/node_modules/configurable-http-proxy/bin/configurable-http-proxy',
  }

  # Group and user to run service as
  group { 'chproxy':
    gid => 1704
  }
  user { 'chproxy':
    uid   => '11112',
    gid   => '1704',
    shell => '/sbin/nologin',
    home  => '/dev/null',
  }
  file { '/etc/systemd/system/configurable-http-proxy.service':
    mode    => '0644',
    owner   => 'root',
    group   => 'sysadmins',
    content => template('jupyterhub/configurable-http-proxy.service.erb'),
    require => Exec['install-chproxy'],
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
