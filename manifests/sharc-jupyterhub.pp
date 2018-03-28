class jupyterhub::sharc-jupyterhub (
    $jh_admin_users,
    $jh_whitelist_users,
    $cluster_net_cidr,
    $public_net_cidr,
    $is_devel_env = false,
    $file_cache = '/usr/local/media',
    $py_vers = 3,
    $miniconda_vers = '4.3.11',
    $miniconda_dl_md5 = '1924c8d9ec0abf09005aa03425e9ab1a',
    $conda_root = '/usr/local/packages/apps/conda',
    $conda_env = 'jupyterhub',
  ) {


  ################################
  # Install useful system packages
  ################################

  # (https://www.puppetcookbook.com/posts/install-multiple-packages.html)
  Package { ensure => 'installed' }
  # npm no longer needed as the npm package 'configurable-http-proxy' is installed from conda-forge
  $rpm_pkgs = [ 'git', 'tmux', 'bzip2', 'bash-completion', 'stow', 'the_silver_searcher' ]
  package { $rpm_pkgs: }


  #######################################
  # Directory to store installers etc in.
  #######################################

  file { $file_cache:
    ensure => directory,
    mode   => '0775',
    owner  => 'root',
    group  => 'sysadmins',
  }


  ###############
  # Install Conda
  ###############

  $miniconda_dl_fname = "Miniconda${py_vers}-${miniconda_vers}-Linux-x86_64.sh"
  $miniconda_dl_url = "https://repo.continuum.io/miniconda/${miniconda_dl_fname}"
  $miniconda_dl_fpath = "${file_cache}/${miniconda_dl_fname}"
  exec { 'miniconda-download':
    command => "curl --location ${miniconda_dl_url} --output ${miniconda_dl_fname}",
    cwd     => $file_cache,
    path    => [ '/bin', '/usr/bin' ],
    creates => $miniconda_dl_fpath,
    unless  => "echo ${miniconda_dl_md5}  ${miniconda_dl_fname} | md5sum --check --status"
  }
  file { $conda_root:
    ensure => directory,
    mode   => '0775',
    owner  => 'root',
    group  => 'sysadmins',
  }
  exec { 'miniconda-install':
    command => "bash ${miniconda_dl_fpath} -f -b -p ${conda_root} && touch ${conda_root}/.installed",
    path    => [ '/bin', '/usr/bin' ],
    creates => "${conda_root}/.installed",
  }
  file { "${conda_root}/.condarc":
    mode    => '0644',
    owner   => 'root',
    group   => 'root',
    source  => 'puppet:///modules/jupyterhub/sharc-jupyterhub/condarc',
    require => Exec['miniconda-install'],
  }


  #################################################
  # Conda environment for JupyterHub and SGESpawner
  #################################################

  # Copy over conda environment definition file (which was created using 'conda env export')
  file { "${file_cache}/jupyterhub.yml":
    mode    => '0644',
    owner   => 'root',
    group   => 'root',
    source  => 'puppet:///modules/jupyterhub/sharc-jupyterhub/jupyterhub.yml',
    require => Exec['miniconda-install'],
    notify  => [Exec['conda-env-create'], Exec['conda-env-update']],
  }
  # Only create the conda environment if it doesn't already exist
  exec { 'conda-env-create':
    command => "conda env create --file=${file_cache}/jupyterhub.yml --name=${conda_env}",
    path    => [ "${conda_root}/bin", '/bin', '/usr/bin' ],
    unless  => "conda env list | grep -q -e \"envs/${conda_env}\$\"",
    require => File["${file_cache}/jupyterhub.yml"],
  }
  # If the conda environment definition file changes then update the environment accordingly
  exec { 'conda-env-update':
    command     => "conda env update --file=${file_cache}/jupyterhub.yml --name=${conda_env}",
    path        => [ "${conda_root}/bin", '/bin', '/usr/bin' ],
    onlyif      => "conda env list | grep -q -e \"envs/${conda_env}\$\"",
    require     => File["${file_cache}/jupyterhub.yml"],
    refreshonly => true,
  }

  ########################
  # Users, groups and sudo
  ########################

  # Group and user to run juypterhub as.
  group { 'jupyter':
    gid => 1702
  }
  user { 'jupyter':
    uid   => '11111',
    gid   => '1702',
    shell => '/sbin/nologin',
    home  => '/dev/null',
  }
  # Allow the jupyter user to submit Grid Engine jobs as any user.
  file { '/etc/sudoers.d/sharc-jupyterhub':
    mode    => '0640',
    owner   => 'root',
    group   => 'root',
    source  => 'puppet:///modules/jupyterhub/sharc-jupyterhub/jupyter-sudo',
    require => [ User['jupyter'], Group['jupyter'] ],
  }


  ########################
  # JupyterHub directories
  ########################

  # Runtime data directory
  file { '/srv/jupyterhub':
    ensure  => directory,
    mode    => '0770',
    owner   => 'jupyter',
    group   => 'sysadmins',
    require => User['jupyter'],
  }
  # Config directory 
  $jh_cfg_dir = '/etc/jupyterhub'
  file { $jh_cfg_dir:
    ensure  => directory,
    mode    => '0570',
    owner   => 'jupyter',
    group   => 'sysadmins',
    require => User['jupyter'],
  }
  # SSL directory
  $jh_ssl_dir = "${jh_cfg_dir}/ssl"
  file { $jh_ssl_dir:
    ensure  => directory,
    mode    => '0570',
    owner   => 'jupyter',
    group   => 'sysadmins',
    require => User['jupyter'],
  }


  ###########
  # TLS setup
  ###########

  # Ensure OpenSSL config for generating X.509 private key and CSR is present
  $jh_ssl_cfg = "${jh_ssl_dir}/jupyterhub.cnf"
  $jh_ssl_csr = "${jh_ssl_dir}/jupyterhub.csr"
  $jh_ssl_key = "${jh_ssl_dir}/jupyterhub.key"
  $jh_ssl_crt = "${jh_ssl_dir}/jupyterhub.crt"
  file { $jh_ssl_cfg:
    ensure  => file,
    content => template('jupyterhub/openssl.cnf.erb'),
    mode    => '0660',
    owner   => 'jupyter',
    group   => 'sysadmins',
    require => File[$jh_ssl_dir],
  }

  # Ensure X.509 private key and CSR have been generated
  $x509_key_and_cert = [ $jh_ssl_key, $jh_ssl_csr ]

  exec { 'gen_x509_key_csr':
    command => "openssl req -out ${jh_ssl_csr} -newkey rsa:2048 -nodes -keyout ${jh_ssl_key} -config ${jh_ssl_cfg}",
    creates => [ $jh_ssl_key, $jh_ssl_csr ],
    path    => [ '/bin', '/usr/bin' ],
    require => File[$jh_ssl_cfg],
  }

  file { [ $jh_ssl_key, $jh_ssl_csr ]:
    mode    => '0660',
    owner   => 'jupyter',
    group   => 'sysadmins',
    require => Exec['gen_x509_key_csr'],
  }

  # Ensure X.509 self-signed cert (if we are on dev machine)
  if $is_devel_env {
    exec { 'gen_x509_self_sign':
      command => "openssl x509 -signkey ${jh_ssl_key} -in ${jh_ssl_csr} -req -days 365 -out ${jh_ssl_crt}",
      creates => $jh_ssl_crt,
      path    => [ '/bin', '/usr/bin' ],
      require => File[[ $jh_ssl_key, $jh_ssl_csr ]],
    }
  }

  ########################################
  # Configure JupyterHub and start service 
  ########################################

  $jh_public_port = 8443
  # Install JupyterHub config
  file { "${jh_cfg_dir}/jupyterhub_config.py":
    mode    => '0464',
    owner   => 'jupyter',
    group   => 'sysadmins',
    content => template('jupyterhub/jupyterhub_config.py.erb'),
    require => File[$jh_cfg_dir],
  }
  # Install JupyterHub batch job submission template
  file { "${jh_cfg_dir}/jupyterhub.sge.j2":
    mode    => '0464',
    owner   => 'jupyter',
    group   => 'sysadmins',
    content => template('jupyterhub/jupyterhub.sge.j2.erb'),
    require => File[$jh_cfg_dir],
  }
  # Install JupyterHub systemd unit file
  file { '/etc/systemd/system/jupyterhub.service':
    mode    => '0644',
    owner   => 'root',
    group   => 'sysadmins',
    content => template('jupyterhub/jupyterhub.service.erb'),
    notify  => Exec['systemd-daemon-reload'],
  }
  exec { 'systemd-daemon-reload':
    command     => 'systemctl daemon-reload',
    path        => [ '/bin', '/usr/bin' ],
    refreshonly => true,
  }
  service { 'jupyterhub.service':
    ensure    => running,
    enable    => true,
    # Do not restart JupyterHub service automatically if updated config/service files are deployed
    #subscribe => File[[
    #  "${jh_cfg_dir}/jupyterhub_config.py",
    #  "${jh_cfg_dir}/jupyterhub.sge.j2",
    #  '/etc/systemd/system/jupyterhub.service',
    #]],
  }


  ##########################################
  # Port forwarding + HTTP-HTTPS redirection
  ##########################################

  # Ensure Nginx is installed (for redirecting HTTP to HTTPS and forwarding
  # ports 80/443 on to jupyterhub's configurable-http-proxy, which handles TLS)
  package { 'nginx':
    ensure => 'installed',
  }

  file { '/etc/nginx/nginx.conf':
    ensure  => file,
    source  => 'puppet:///modules/jupyterhub/sharc-jupyterhub/nginx.conf',
    mode    => '0644',
    owner   => 'root',
    group   => 'root',
    require => Package['nginx'],
  }

  # Ensure Nginx is running and restart if the config file changes
  service { 'nginx':
    ensure    => running,
    enable    => true,
    subscribe => File['/etc/nginx/nginx.conf'],
  }


  #########################################################
  # Ensure the root conda environment is upgraded regularly
  #########################################################

  file { '/etc/systemd/system/conda-root-upgrade.service':
    mode    => '0644',
    owner   => 'root',
    group   => 'sysadmins',
    content => template('jupyterhub/conda-root-upgrade.service.erb'),
    require => Service['jupyterhub.service'],
    notify  => Exec['systemd-daemon-reload'],
  }
  service { 'conda-root-upgrade.service':
    enable    => true,
    subscribe => File['/etc/systemd/system/conda-root-upgrade.service'],
    require   => File['/etc/systemd/system/conda-root-upgrade.service'],
  }
  file { '/etc/systemd/system/conda-root-upgrade.timer':
    mode    => '0644',
    owner   => 'root',
    group   => 'sysadmins',
    source  => 'puppet:///modules/jupyterhub/sharc-jupyterhub/conda-root-upgrade.timer',
    require => Service[ 'conda-root-upgrade.service'],
    notify  => Exec['systemd-daemon-reload'],
  }
  service { 'conda-root-upgrade.timer':
    ensure    => running,
    enable    => true,
    subscribe => File['/etc/systemd/system/conda-root-upgrade.timer'],
    require   => File['/etc/systemd/system/conda-root-upgrade.timer'],
  }
}
