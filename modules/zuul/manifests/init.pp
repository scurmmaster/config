# Copyright 2012-2013 Hewlett-Packard Development Company, L.P.
# Copyright 2012 Antoine "hashar" Musso
# Copyright 2012 Wikimedia Foundation Inc.
# Copyright 2013 OpenStack Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

# == Class: zuul
#
class zuul (
  $vhost_name = $::fqdn,
  $serveradmin = "webmaster@${::fqdn}",
  $gearman_server = '127.0.0.1',
  $internal_gearman = true,
  $gerrit_server = '',
  $gerrit_user = '',
  $zuul_ssh_private_key = '',
  $url_pattern = '',
  $status_url = "https://${::fqdn}/",
  $zuul_url = '',
  $git_source_repo = 'https://git.openstack.org/openstack-infra/zuul',
  $job_name_in_report = false,
  $revision = 'master',
  $statsd_host = '',
  $git_email = '',
  $git_name = '',
  $smtp_host = 'localhost',
  $smtp_port = 25,
  $smtp_default_from = "zuul@${::fqdn}",
  $smtp_default_to = "zuul.reports@${::fqdn}",
  $swift_authurl = '',
  $swift_user = '',
  $swift_key = '',
  $swift_tenant_name = '',
  $swift_region_name = '',
  $swift_default_container = '',
  $swift_default_logserver_prefix = '',
) {
  include apache
  include pip

  $packages = [
    'python-webob',
    'python-lockfile',
    'python-paste',
  ]

  package { $packages:
    ensure => present,
  }

  # A lot of things need yaml, be conservative requiring this package to avoid
  # conflicts with other modules.
  if ! defined(Package['python-yaml']) {
    package { 'python-yaml':
      ensure => present,
    }
  }

  if ! defined(Package['python-paramiko']) {
    package { 'python-paramiko':
      ensure   => present,
    }
  }

  if ! defined(Package['python-daemon']) {
    package { 'python-daemon':
      ensure => present,
    }
  }

  user { 'zuul':
    ensure     => present,
    home       => '/home/zuul',
    shell      => '/bin/bash',
    gid        => 'zuul',
    managehome => true,
    require    => Group['zuul'],
  }

  group { 'zuul':
    ensure => present,
  }

  vcsrepo { '/opt/zuul':
    ensure   => latest,
    provider => git,
    revision => $revision,
    source   => $git_source_repo,
  }

  exec { 'install_zuul' :
    command     => 'pip install /opt/zuul',
    path        => '/usr/local/bin:/usr/bin:/bin/',
    refreshonly => true,
    subscribe   => Vcsrepo['/opt/zuul'],
    require     => Class['pip'],
  }

  file { '/etc/zuul':
    ensure => directory,
  }

# TODO: We should put in  notify either Service['zuul'] or Exec['zuul-reload']
#       at some point, but that still has some problems.
  file { '/etc/zuul/zuul.conf':
    ensure  => present,
    owner   => 'zuul',
    mode    => '0400',
    content => template('zuul/zuul.conf.erb'),
    require => [
      File['/etc/zuul'],
      User['zuul'],
    ],
  }

  file { '/etc/default/zuul':
    ensure  => present,
    mode    => '0444',
    content => template('zuul/zuul.default.erb'),
  }

  file { '/var/log/zuul':
    ensure  => directory,
    owner   => 'zuul',
    require => User['zuul'],
  }

  file { '/var/run/zuul':
    ensure  => directory,
    owner   => 'zuul',
    group   => 'zuul',
    require => User['zuul'],
  }

  file { '/var/run/zuul-merger':
    ensure  => directory,
    owner   => 'zuul',
    group   => 'zuul',
    require => User['zuul'],
  }

  file { '/var/lib/zuul':
    ensure  => directory,
    owner   => 'zuul',
    group   => 'zuul',
  }

  file { '/var/lib/zuul/git':
    ensure  => directory,
    owner   => 'zuul',
    require => File['/var/lib/zuul'],
  }

  file { '/var/lib/zuul/ssh':
    ensure  => directory,
    owner   => 'zuul',
    group   => 'zuul',
    mode    => '0500',
    require => File['/var/lib/zuul'],
  }

  file { '/var/lib/zuul/ssh/id_rsa':
    owner   => 'zuul',
    group   => 'zuul',
    mode    => '0400',
    require => File['/var/lib/zuul/ssh'],
    content => $zuul_ssh_private_key,
  }

  file { '/var/lib/zuul/www':
    ensure  => directory,
    require => File['/var/lib/zuul'],
  }

  package { 'libjs-jquery':
    ensure => present,
  }

  file { '/var/lib/zuul/www/jquery.min.js':
    ensure  => link,
    target  => '/usr/share/javascript/jquery/jquery.min.js',
    require => [File['/var/lib/zuul/www'],
                Package['libjs-jquery']],
  }

  vcsrepo { '/opt/twitter-bootstrap':
    ensure   => latest,
    provider => git,
    revision => 'v3.1.1',
    source   => 'https://github.com/twbs/bootstrap.git',
  }

  file { '/var/lib/zuul/www/bootstrap':
    ensure  => link,
    target  => '/opt/twitter-bootstrap/dist',
    require => [File['/var/lib/zuul/www'],
                Package['libjs-jquery'],
                Vcsrepo['/opt/twitter-bootstrap']],
  }

  vcsrepo { '/opt/jquery-visibility':
    ensure   => latest,
    provider => git,
    revision => 'master',
    source   => 'https://github.com/mathiasbynens/jquery-visibility.git',
  }

  file { '/var/lib/zuul/www/jquery-visibility.min.js':
    ensure  => link,
    target  => '/opt/jquery-visibility/jquery-visibility.min.js',
    require => [File['/var/lib/zuul/www'],
                Vcsrepo['/opt/jquery-visibility']],
  }

  file { '/var/lib/zuul/www/index.html':
    ensure  => link,
    target  => '/opt/zuul/etc/status/public_html/index.html',
    require => File['/var/lib/zuul/www'],
  }

  file { '/var/lib/zuul/www/app.js':
    ensure  => link,
    target  => '/opt/zuul/etc/status/public_html/app.js',
    require => File['/var/lib/zuul/www'],
  }

  file { '/var/lib/zuul/www/images':
    ensure  => link,
    target  => '/opt/zuul/etc/status/public_html/images',
    require => File['/var/lib/zuul/www'],
  }

  file { '/etc/init.d/zuul':
    ensure => present,
    owner  => 'root',
    group  => 'root',
    mode   => '0555',
    source => 'puppet:///modules/zuul/zuul.init',
  }

  file { '/etc/init.d/zuul-merger':
    ensure => present,
    owner  => 'root',
    group  => 'root',
    mode   => '0555',
    source => 'puppet:///modules/zuul/zuul-merger.init',
  }

  apache::vhost { $vhost_name:
    port     => 443,
    docroot  => 'MEANINGLESS ARGUMENT',
    priority => '50',
    template => 'zuul/zuul.vhost.erb',
  }
  if ! defined(A2mod['rewrite']) {
    a2mod { 'rewrite':
      ensure => present,
    }
  }
  if ! defined(A2mod['proxy']) {
    a2mod { 'proxy':
      ensure => present,
    }
  }
  if ! defined(A2mod['proxy_http']) {
    a2mod { 'proxy_http':
      ensure => present,
    }
  }
}
