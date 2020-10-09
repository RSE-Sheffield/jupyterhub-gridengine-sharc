# JupterHub (for GridEngine) and PostgreSQL services for Centos 7.x
class jupyterhub::jupyterhub (
    $jh_db = 'jupyterhub',
    $jh_user = 'jupyter',
    $jh_group = 'jupyter',
    $jh_vers = '1.1.0',
    $batchspawner_vers = '0.8.1',
    $psycopg2_vers = '2.8.5',
  ) {

  ############
  # Local vars
  ############
  # Python virtualenv path for JupyterHub PyPI pkg and dependencies.
  $venv = '/opt/jupyterhub'
  # SGE commands that need to be run on behalf of users using sudo to manage per-session Jupyter jobs.
  $sge_priv_cmds = [
    'qsub',
    'qstat',
    'qdel',
  ]
  $sge_root = '/usr/local/sge/live'

  ################################
  # Install RHEL and PyPI packages
  ################################
  Package { ensure => 'installed' }
  $rpm_pkgs = [
    'epel-release',
    'gcc',
    'postgresql',
    'postgresql-devel',
    'postgresql-server',
    'python3',
    'python3-devel',
  ]
  package {$rpm_pkgs:}
  # NB gcc and devel packages needed to build psycopg2 Python lib

  # Create a Python virtualenv for JupyterHub, Batchspawner and dependencies
  exec { 'jupyterhub-venv':
    command => "/usr/bin/python3 -m venv ${venv}",
    path    => ['/bin', '/usr/bin'],
    require => Package['python3'],
    creates => "${venv}/bin/activate",
  }
  # Install (particular versions of) JupyterHub, BatchSpawner and dependencies from PyPI
  -> file { "${venv}/requirements.txt":
    mode    => '0644',
    owner   => 'root',
    group   => 'sysadmins',
    content => template('jupyterhub/jupyterhub-requirements.txt.erb'),
  }
  ~> exec { 'py-pkg-install':
    command => "${venv}/bin/python3 -m pip install --upgrade --upgrade-strategy=only-if-needed -r ${venv}/requirements.txt",
    path    => ['/bin', '/usr/bin'],
  }

  #########################################
  # POSIX user/group for JupyterHub service
  #########################################
  group { $jh_group:
    gid => 1702
  }
  user { $jh_user:
    uid     => '11111',
    gid     => '1702',
    shell   => '/sbin/nologin',
    home    => '/dev/null',
    require => Group[$jh_group],
  }
# TODO: Use /var/lib/jupyterhub for home dir instead?  Need to be able to write to home dir?
# TODO: Rename group and user to jupyterhub/jupyterhub for clarity?

  ################################################################################
  # sudo: Allow the jupyter user to manage SGE jobs as any user without a password
  ################################################################################
  file { '/etc/sudoers.d/jupyterhub':
    mode    => '0640',
    owner   => 'root',
    group   => 'root',
    content => template('jupyterhub/jupyterhub-sudo'),
    require => [
      User[$jh_user],
      Group[$jh_group]
    ],
  }

  ####################################
  # PostgreSQL database for JupyterHub
  ####################################
  exec { 'pg-initdb':
    command => '/bin/postgresql-setup initdb',
    require => Package['postgresql-server'],
    creates => '/var/lib/pgsql/data/PG_VERSION',
  }
  -> service { 'postgresql.service':
    ensure => running,
    enable => true,
  }
  -> exec { 'pg-jh-user':
    command => "/bin/createuser ${jh_user}",
    user    => 'postgres',
    unless  => "/bin/psql -t -c '\du' | cut -d \| -f 1 | grep -qw ${jh_user}",
    require =>  User[$jh_user],
  }
  -> exec { 'pg-jh-db':
    command => "/bin/createdb --owner=${jh_user} encoding=UTF-8 --template=template1 ${jh_db}",
    user    => 'postgres',
    unless  => "/bin/psql -lqt | cut -d \| -f 1 | grep -qw ${jh_db}",
  }

  ############################
  # JupyterHub systemd service
  ############################
  file { '/etc/systemd/system/jupyterhub.service':
    mode    => '0644',
    owner   => 'root',
    group   => 'sysadmins',
    content => template('jupyterhub/jupyterhub.service.erb'),
    require => [
      Exec['py-pkg-install'],
      User[$jh_user],
      Exec['pg-jh-db'],
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
