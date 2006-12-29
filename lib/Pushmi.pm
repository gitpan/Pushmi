package Pushmi;
use strict;
use version; our $VERSION = qv(0.99_1);

1;

=head1 NAME

Pushmi - Subversion repository replication tool

=head1 SYNOPSIS

  pushmi mirror /var/db/my-local-mirror http://master.repository/svn
  pushmi sync /var/db/my-local-mirror

=head1 DESCRIPTION

Pushmi provides a mechanism for bidirectionally synchronizing
Subversion repositories.  The main difference between Pushmi and
other replication tools is that Pushmi makes the "slave" repositories
writable by normal Subversion clients.

=head1 CONFIGURATION

=over

=item Set up your local repository

Create F</etc/pushmi.conf> and setup username and password.  See
F<t/pushmi.conf> for example.

  pushmi mirror /var/db/my-local-mirror http://master.repository/svn

=item Bring the mirror up-to-date.

  pushmi sync --nowait /var/db/my-local-mirror

Configure a cron job to run this command every 5 minutes.

=item Configure your local svn

Set up your svn server to serve F</var/db/my-local-mirror> at
C<http://slave.repository/svn>

=back

For your existing Subversion checkouts, you may now switch to the slave 
using this command:

  svn switch --relocate http://master.repository/svn http://slave.repository/svn

From there, you can use normal C<svn> commands to work with your checkout.

=head1 AUTHENTICATION

The above section describes the minimum setup without authentication
and authorisation.

To support auth*, you need to start memcached on the C<authproxy_port>
port specified in pushmi.conf.  For exmaple:

  memcached -p 7123 -dP /var/run/memcached.pid

=over

=item For authz_svn-controlled master repository

You need to use an external mechanism to replicate the authz file and
add a C<AuthzSVNAccessFile> directive in the slave's slave
C<httpd.conf>, along with whatever authentication modules and
configurations.  You will need additional directives in C<httpd.conf>
using mod_perl2:

  # replace with your auth settings
  AuthName "Subversion repository for projectX"
  AuthType Basic
  Require valid-user
  # here are the additional config required for pushmi
  PerlSetVar PushmiConfig /etc/pushmi.conf
  PerlAuthenHandler Pushmi::Apache::AuthCache

=item For public-read master repository

You can defer the auth* to the master on write.  Put the additional
config in C<httpd.conf>:

  PerlSetVar SVNPath /var/db/my-local-mirror
  PerlSetVar Pushmi /usr/local/bin/pushmi
  PerlSetVar PushmiConfig /etc/pushmi.conf
  <LimitExcept GET PROPFIND OPTIONS REPORT>
    AuthName "Subversion repository for projectX"
    AuthType Basic
    Require valid-user
    PerlAuthenHandler Pushmi::Apache::AuthCommit
  </LimitExcept>

=back

=head1 CONFIG FILE

C<pushmi> looks for F</etc/pushmi.conf> or wherever C<PUSHMI_CONFIG>
in environment points to.  Available options are:

=over

=item username

The credential to use for mirroring.

=item password

The credential to use for mirroring.

=item authproxy_port

The port memcached is running on.

=item use_cached_auth

If pushmi should use the cached subversion authentication info.

=back

Some mirror-related options are configurable in svk, in your
F<~/.subversion/config>'s C<[svk]> section:

=over

=item ra-pipeline-delta-threshold

The size in bytes that pipelined sync should leave the textdelta in a
tempfile.  Default is 2m.

=item ra-pipeline-buffer

The max number of revisions that pipelined sync should keep in memory
when it is still busy writing to local repository.

=back

=head1 LOGGING

C<pushmi> uses L<Log::Log4perl> as logging facility.  Create
F</etc/pushmi-log.conf>.  See F<t/pushmi-log.t> as exmaple.  See also
L<Log::Log4perl::Config> for complete reference.

=head1 LICENSE

Copyright 2006 Best Practical Solutions, LLC.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 SUPPORT

To inquire about commercial support, please contact sales@bestpractical.com.

=head1 AUTHORS

Chia-liang Kao

=cut
