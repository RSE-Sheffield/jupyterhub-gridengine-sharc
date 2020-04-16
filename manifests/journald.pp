class jupyterhub::journald {

  # Disable PAM fingerprint reader module to reduce syslog spam
  exec { 'disable_pam_fprintd':
    command => 'authconfig --disablefingerprint --update',
    unless  => 'authconfig --test | grep -q "pam_fprintd is disabled"',
    path    => [ '/usr/sbin', '/bin', '/usr/bin' ],
  }

  # Ensure that journald running and journald logs persist over reboots
  service { 'systemd-journald':
    ensure    => 'running',
    enable    => true,
    hasstatus => true,
  }
  file { '/etc/systemd/journald.conf.d':
    ensure => 'directory',
  }
  file { '/etc/systemd/journald.conf.d/journald-persistence.conf':
    mode    => '0644',
    owner   => 'root',
    group   => 'root',
    source  => 'puppet:///modules/jupyterhub/jupyterhub/journald-persistence.conf',
    require => File['/etc/systemd/journald.conf.d'],
    notify  => Service['systemd-journald'],
  }
}
