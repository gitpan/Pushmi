package Pushmi::Command::Mirror;
use strict;
use warnings;
use base 'Pushmi::Command';
use constant subcommands => qw(runhook sync tryauth);

use Pushmi::Mirror;
use Pushmi::Config;
use Path::Class;
use SVN::Mirror;
use SVK::Config;
use SVK::XD;
use SVN::Delta;
use SVK::I18N;
use UNIVERSAL::require;

sub options {
    ('runhook'   => 'runhook',
     'init'      => 'init',
     'tryauth'   => 'tryauth',
     'sync'      => 'sync',
     'txnname=s' => 'txnname')
}

sub run {
    my $self = shift;

    # compat
    for ($self->subcommands) {
	if ($self->{$_}) {
	    my $cmd = 'Pushmi::Command::'.ucfirst($_);
	    $cmd->require or die "can't require $cmd: $@";
	    return (bless $self, $cmd)->run(@_)
	}
    }

    $self->run_init(@_);
}

sub root_svkpath {
    my ($self, $repos) = @_;
    my $depot = SVK::Depot->new( { repos => $repos, repospath => $repos->path, depotname => '' } );
    SVK::Path->real_new(
        {
            depot => $depot,
            path => '/'
        }
    )->refresh_revision;
}

sub setup_auth {
    my $self = shift;
    my $config = Pushmi::Config->config;
    SVK::Config->auth_providers(
    sub {
        [ $config->{use_cached_auth} ? SVN::Client::get_simple_provider() : (),
          SVN::Client::get_username_provider(),
          SVN::Client::get_ssl_server_trust_file_provider(),
          SVN::Client::get_ssl_server_trust_prompt_provider(
                \&SVK::Config::_ssl_server_trust_prompt
          ),
	  SVN::Client::get_simple_prompt_provider( $self->can('pushmi_auth'), 0 ) ]
    });
}

# XXX: we should be using real providers if we can thunk svn::auth providers
sub pushmi_auth {
    my ($cred, $realm, $default_username, $may_save, $pool) = @_;
    my $config = Pushmi::Config->config;
    $cred->username($config->{username});
    $cred->password($config->{password});
    $cred->may_save(0);
    return $SVN::_Core::SVN_NO_ERROR;
}

sub canonpath {
    my $self = shift;
    $_[0] = Path::Class::Dir->new($_[0])->stringify;
}

sub run_init {
    my ($self, $repospath, $url) = @_;
    $self->canonpath($repospath);
    my ($repos, $created);
    die "url required.\n" unless $url;
    if (-e $repospath) {
	$repos = SVN::Repos::open($repospath) or die "Can't open repository: $@";
    }
    else {
	$created = 1;
	$repos = SVN::Repos::create($repospath, undef, undef, undef, undef )
	    or die "Unable to create repository on $repospath";
    }

    my $t = $self->root_svkpath($repos);

    my $mirror = SVK::Mirror->new( { depot => $t->depot, path => '/', url => $url, pool => SVN::Pool->new} );
    require SVK::Mirror::Backend::SVNSync;

    $self->setup_auth;
    my $backend = bless { mirror => $mirror }, 'SVK::Mirror::Backend::SVNSync';
    $mirror->_backend($backend->create( $mirror ));

    Pushmi::Mirror->install_hook($repospath);
    $mirror->depot->repos->fs->set_uuid($mirror->server_uuid);

    print loc("Mirror initialized.\n");

    return;
}

=head1 NAME

Pushmi::Command::Mirror - manage pushmi mirrors

=head1 SYNOPSIS

 mirror --init REPOSPATH URL
 mirror --sync REPOSPATH
 mirror --runhook REPOSPATH

=head1 OPTIONS

 --init            : initialize pushmi mirror on REPOSPATH.
                     this installs the pre-commit-hook.

 --runhook         : run pre-commit-hook. do not use manually.
 --txnname         : txn used for hook.

=cut

1;
