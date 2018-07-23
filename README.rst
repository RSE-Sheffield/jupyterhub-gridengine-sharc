JupyterHub + Grid Engine configuration for the University of Sheffield's ShARC cluster
======================================================================================

A Puppet_ module for configuring JupyterHub_ for a `Grid Engine`_ HPC cluster so that 
JupyterHub can spawn and monitor a single-user Jupyter_ session per user on worker node(s) that 
satisfy user-specified resource requests.

.. contents:: 
    :depth: 2


Introduction
------------

Jupyter_ is a literate programming system for 
interacting with Notebooks containing 
blocks of code, formatted text, maths and browser-renderable media.
Users can view, create and modify Notebooks to iteratively explore research workflows:
code cells can be executed in isolation in any order and can generate not just textual outputs
within a Notebook but also graphical (e.g. plots) outputs and tabular outputs.

JupyterHub_ is a multi-user hub that allows multiple users to start, run and manage Jupyter on 
a remote machine (either standalone or in or pool of machines) after first 
authenticating via a web portal.

At the University of Sheffield we provide a **JupyterHub service that 
runs on our ShARC_ high-performance computing (HPC) cluster**.  
JupyterHub and the `Grid Engine`_ software that manages jobs on ShARC
have been configured so that: 

#. A user with an account on ShARC can in to JupyterHub (running on a virtual machine);
#. They can then **request the cluster resources they want for their Jupyter session 
   (CPU cores, GPUs, RAM etc).**;
#. They then request a Jupyter session on a worker node that provides these resources.
   Behind the scenes JupyterHub submits a job that should start running and fire up a 
   single-user Jupyter server if there are cluster resources available or time-out
   if not.

**This repo contains a puppet module that installs and configures JupyterHub so as to provide this service.**

The development of this service has been funded by OpenDreamKit_, a EU-funded project that 
aims to further the open-source mathematical ecosystem.

Puppet and Foreman
------------------

Puppet_ and Foreman_ are used for configuration management on many University systems including ShARC:

* Numerous Puppet modules define recipes for system configuration.  
  The sources of these recipes are all managed using git: 
  pushes to master branches the corresponding repositories make new versions of the modules available to 
  the Foreman_ system that manages Puppet.
* The (database-backed) Foreman_ service is told which modules need applying to which hosts (or host groups) and
  if/how the *classes* contained within those modules should be parameterised per host/host group.
* The `Puppet Agent`_ software running on managed hosts checks in periodically to see if 
  the host configuration is up-to-date.

ShARC's JupyterHub hosts
------------------------

ShARC has two JupyterHub hosts: production (``prod``) and a development (``dev``).
Each is a Centos 7.x VMWare virtual machine.  

The key difference between the two servers is that: 

* ``dev`` only allows users on a whitelist to log in to JupyterHub;
* ``prod`` allows any user to authenticate.

``prod`` and ``dev`` both have network interfaces and statically-assigned IPs on:

* The main University network 
* The cluster's internal Ethernet network

Generic Puppet classes
^^^^^^^^^^^^^^^^^^^^^^

Several cluster-wide Puppet classes within a different module are applied to the ``dev`` and ``prod`` hosts.  These classes are not in this (or any) public git repository.

* ``sharc::puppet`` - ensure the `Puppet Agent`_ service is running;
* ``sharc::admin-users`` and ``sharc::sudo`` - sysadmin accounts and sudo_ config;
* ``sharc::iptables`` - cluster-specific firewall rules;
* ``sharc::ldapclient`` - ensure that LDAP_ can be used as a source of user/group information, inc. for authentication;
* ``sharc::sgeclient`` - the software (Grid Engine plus the MUNGE_ authentication daemon), config files, routes, host info and environment variables
  necessary for a machine to be able to submit jobs to a Grid Engine job scheduler (i.e. to make a machine a *submit host*).  
  The host info is the IP address and hostnames of every host in the cluster, including the JupyterHub hosts.

JupyterHub-specific Puppet classes
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

There is also a jupyterhub-specific 
Puppet module (``jupyterhub``) and 
class (``jupyterhub::sharc-jupyterhub``), 
the source for which is defined here.

This class has several parameters, 
some of which have defaults and 
some of which require values to be fed in from elsewhere 
(specifically, the Foreman database).  
This parameterisation allows:

* the same class to be applied to both hosts but 
  parameters (with associated internal logic) result in differing configuration.
* more confidential information (network addresses, usernames) to be 
  kept out of version control.

The parameters, their defaults as defined in the class and details of how in Foreman they are 
overridden per host or host class:

+------------------------+--------------------------------------------------------------------------+----------------------------------------+-----------------------+
| Parameter              | Description                                                              | Default                                | Overridden in Foreman |
+========================+==========================================================================+========================================+=======================+
| ``is_devel_env``       | Boolean                                                                  | ``False``                              | per host              |
+------------------------+--------------------------------------------------------------------------+----------------------------------------+-----------------------+
| ``cluster_net_cidr``   | Network (in CIDR format) on which cluster-facing interface is listening  | -                                      | for class             |
+------------------------+--------------------------------------------------------------------------+----------------------------------------+-----------------------+
| ``public_net_cidr``    | Network (in CIDR format) on which Internet-facing interface is listening | -                                      | for class             |
+------------------------+--------------------------------------------------------------------------+----------------------------------------+-----------------------+
| ``file_cache``         | Where to store installers                                                | ``/`usr/local/media``                  | -                     |
+------------------------+--------------------------------------------------------------------------+----------------------------------------+-----------------------+
| ``py_vers``            | Version of Python to use                                                 | ``3``                                  | -                     |
+------------------------+--------------------------------------------------------------------------+----------------------------------------+-----------------------+
| ``miniconda_vers``     | Version of Miniconda to use                                              | ``4.3.11``                             | -                     |
+------------------------+--------------------------------------------------------------------------+----------------------------------------+-----------------------+
| ``miniconda_dl_md5``   | Miniconda installer checksum                                             | ``1924c8d9ec0abf09005aa03425e9ab1a``   | -                     |
+------------------------+--------------------------------------------------------------------------+----------------------------------------+-----------------------+
| ``conda_root``         | Where to install Miniconda                                               | ``/usr/local/packages/apps/conda``     | -                     |
+------------------------+--------------------------------------------------------------------------+----------------------------------------+-----------------------+
| ``conda_env``          | Name of JupyterHub conda environment                                     | ``jupyterhub``                         | -                     |
+------------------------+--------------------------------------------------------------------------+----------------------------------------+-----------------------+
| ``jh_admin_users``     | List of JupyterHub administrators                                        | -                                      | for class             |
+------------------------+--------------------------------------------------------------------------+----------------------------------------+-----------------------+
| ``jh_whitelist_users`` | Whitelist of JupyterHub users (used if ``is_devel_env`` is True)         | -                                      | for class             |
+------------------------+--------------------------------------------------------------------------+----------------------------------------+-----------------------+

Internal logic
""""""""""""""

This class does the following:

* Ensures Miniconda_ is installed;
* Ensures a conda environment exists that includes 
  the packages specified in ``jupyterhub.yml`` (production system) or ``jupyterhub-dev.yml`` (dev system),
  upgrading packages if necessary;
  On the University's Iceberg cluster the root conda environment was shared between 
  the cluster nodes and its JupyterHub hosts using NFS.  
  The same has not been done for ShARC's JupyterHub hosts to 
  reduce the coupling of the JupyterHub hosts; 
  a consequence is that an identical conda environment must now be set up 
  on the JupyterHub hosts and the cluster's execution hosts.
* Ensure that a ``jupyter`` system group and system user exist; 
  ``jupyterhub`` is later run as this unprivileged user;
* Configures ``sudo`` to allow the ``jupyter`` user to 
  submit, query the state of and delete Grid Engine jobs 
  (using ``qsub``/``qstat``/``qdel``) 
  as any user without needing a password.  
  ``sudo`` is also configured to pass through certain Grid Engine environment variables so that 
  the Grid Engine commands know what is going on 
  (``SGE_ROOT``, ``SGE_CELL``, ``SGE_EXECD_PORT``, ``SGE_QMASTER_PORT``, ``SGE_CLUSTER_NAME``, ``LANG``, ``JPY_API_TOKEN``);
* Create directories specifically for JupyterHub:

  * ``/srv`` - for runtime data;
  * ``/etc/jupyterhub`` -  for config file(s);
  * ``/etc/jupyterhub/ssl`` -  for X.509 (TLS) certificates;

* Creates a X.509 (TLS) private key, certificate signing request and (on ``dev`` only) a self-signed certificate.

* Installs the JupyterHub ``.py`` config file and 
  a Grid Engine batch job submission template;
* Defines a systemd_ JupyterHub service then tries to 
  start it and enable it at boot 
  (this may fail on ``prod`` if there is not yet a public certificate 
  at the location specified in the JupyterHub config file);
* Configures an Nginx proxy that:

  * Forwards TCP connections to (privileged) port 443 on to (what will be) the Jupyterhub service's public port;
  * Redirects HTTP (port 80) to HTTPS (port 443);
  * Allows for TLS pass-through (i.e. TLS is handled by Jupyterhub, not Nginx);

* Defines, starts and enables a systemd_ service for regularly updating the root conda environment.

.. warning::
   Note: The University has a Cisco ACE service for load balancing, TLS offload and general port forwarding.  
   An attempt was made to use this instead of a local (Nginx) proxy for forwarding connections but 
   `an issue <https://github.com/jupyterhub/jupyterhub/issues/1137>`__ was encountered with 
   the interaction between the ACE proxy and JupyterHub's internal (``configurable-http-proxy``) meaning 
   that this wasn't possible at this time.  
   It is suspected that the cause is a bug in how ``configurable-http-proxy`` 2.0.0 handles 
   HTTP headers set by the ACE module.

Manual cluster configuration
----------------------------

#. Grid Engine needs to be notified that ``dev`` and ``prod`` are to be used as submit hosts.  
   From a Grid Engine *administrative host*:

      .. code-block:: bash

         for h in dev prod; do 
             qconf -as $h
         done

#. The same conda environment that was created on the JupyterHub hosts must also be 
   set up in a central location on the cluster (readable from all execution hosts).  
   However, note that ``sgespawner`` does not *need* to be installed in this environment as 
   the environment is only needed once the Grid Engine session has been spawned.

      .. code-block:: bash

         # NB the user `sysadmin` must have write access to the root conda install 
         # so that he/she can create a new conda env in the same central location, 
         # thus allowing the new conda env to be accessible by all users.
         ssh sysadmin@sharc.shef.ac.uk  

         # Start an interactive job (if the root conda install is only available 
         # on the cluster's worker nodes)
         qrshx

         # Activate the conda module
         module load apps/python/conda

         cd path/to/clone/of/this/repo

         # The name of the conda environment we want to create
         CONDA_ENV=jupyterhub  # or jupyterhub-dev

         # The packages (plus versions) that we want to install into this environment
         CONDA_ENV_FILE=worker-conda-env.yml  # or worker-conda-env-dev.yml 

         # Does the conda environment already exist?
         if conda env list | grep -q -e "envs/${CONDA_ENV}\$"; then
            # Yes, so update it if necessary
            conda_cmd=update
         else
            # No, so create it
            conda_cmd=create
         fi
         conda env $conda_cmd --file=$CONDA_ENV_FILE --name=$CONDA_ENV

Testing the JupyterHub setup
----------------------------

Let the hostname of ``dev`` or ``prod`` be ``jhhost``.

#. SSH from your local machine to ``jhhost``:

   .. code-block:: bash

      ssh jhhost

#. Start monitoring the JupyterHub log from within that SSH session:

   .. code-block:: bash

      sudo journalctl -u jupyter.service -f

#. Connect to ``http://jhhost`` in your web browser; 
   the connection should be automatically redirected to HTTPS;
#. Log in using your CiCS username and password 
   (NB on ``dev`` you need to be in the JupyterHub user whitelist); 
   your single-user Jupyter session should then be started automatically and 
   you should be presented with the Jupyter UI after a few seconds;
#. Note down the ``journalctl`` output if you encounter any unexpected warnings/errors.

Additional Grid Engine Queues/Projects/Complexes
------------------------------------------------

The ``sgespawner`` resource request HTML form 
presents the user with a deliberately limited set of 
the resources that could be requested from ShARC's Grid Engine scheduler.

To add options presented via this form:

#. Update the HTML form (the ``c.SGESpawner.options_form`` string in 
   the ``jupyterhub_config.py.erb`` Puppet template).  
   Either **add a new HTML Input** to capture a new type of resource request
   or update an HTML Input to e.g. add to the list of discrete options that 
   can be selected for a given input (e.g. to allow an additional Project name to be selected).

   For example, here is the part of that string that allows the user to 
   select between two different cluster queues:

   .. code-block:: html

      <h3>Job queue</h3>
      <p>Selecting '<em>any</em>' lets the scheduler choose an appropriate queue
      (which is typically what you want).</p>
      <select name="queue">
        <option value="any">any</option>
        <option value="cstest.q">cstest.q</option>
      </select> 

#. Next, update the Grid Engine job submission template used to 
   start a single-user Jupyter session on a worker node 
   (the Puppet template ``jupyterhub.sge.j2.erb``).
   This is a doubly-templated file:

   * Jinja 2 templating is used at run-time to 
     conditionally include resource request details 
     extrated from a ``user_options`` object e.g. ::

        {% if user_options.queue and user_options.queue|first != 'any' %}
        #$ -q {{ user_options.queue|first }}
        {% endif %}
     
   * Puppet ERB templating could be used by Puppet at install time to 
     include/exclude content e.g.

     .. code-block:: erb

        <% if @is_devel_env -%>#$ -l special_new_feature=1<% end %>

   Look at the provided ``jupyterhub.sge.j2.erb`` to see 
   how values are currently extracted from the ``user_options`` object 
   within the Jinja 2 template.
   Note that each attribute of ``user_options`` is *always* a list so 
   one typically needs to extract the first value using Jinja 2's ``|first`` filter.

   You will also see how certain resource requests will only be written into
   the final job submission script if values from the HTML template 
   (the first element of attributes of ``user_options``) are 
   in a whitelist or not in a blacklist 
   (e.g. is not ``any`` or is not ``default``).
   This ensures that if a user requests e.g. 'any queue' then no queue request is written
   into the batch job submission script and 
   the scheduler is free to select what it considers to be an appropriate queue.

#. Commit your updates to a fork of this repository.
#. Ensure Puppet and Foreman re-apply this Puppet module on your JupyterHub hosts.
   This should instantiate the two aforementioned ``.erb`` templates and 
   copy the results to the JupyterHub hosts.
#. Restart the ``jupyterhub`` service on your JupyterHub hosts at a convenient time.

Repo history
------------

Note that this repository was instantiated from the contents (but not history) of a private Git repository.
The private repository contains a little confidential information and is used with Foreman to deploy JupyterHub on ShARC.
Following the creation of this public repository 
the private repository should only receive new commits by merging in changes from this public repo. 

All new issues re JupyterHub on ShARC / Grid Engine should be raised via this public repo.

.. _Foreman: https://www.theforeman.org/
.. _Grid Engine: https://arc.liv.ac.uk/trac/SGE
.. _Jupyter Notebook Extensions: https://docs.continuum.io/anaconda/jupyter-notebook-extensions
.. _Jupyter: http://jupyter.org/
.. _JupyterHub: https://jupyterhub.readthedocs.io/
.. _LDAP: https://en.wikipedia.org/wiki/Lightweight_Directory_Access_Protocol
.. _MUNGE: https://dun.github.io/munge/
.. _Miniconda: https://conda.io/miniconda.html
.. _OpenDreamKit: http://opendreamkit.org/
.. _Puppet Agent: https://linux.die.net/man/8/puppet-agent
.. _Puppet: https://en.wikipedia.org/wiki/Puppet_(software)
.. _ShARC: http://docs.hpc.shef.ac.uk/
.. _Spawner: http://jupyterhub.readthedocs.io/en/latest/spawners.html
.. _conda: https://conda.io/docs/
.. _pip: https://docs.python.org/3/installing/
.. _sgespawner: https://github.com/willfurnass/sgespawner
.. _sudo: https://en.wikipedia.org/wiki/Sudo
.. _systemd: https://www.freedesktop.org/wiki/Software/systemd/
