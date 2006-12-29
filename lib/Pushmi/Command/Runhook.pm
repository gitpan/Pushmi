package Pushmi::Command::Runhook;
use base 'Pushmi::Command::Mirror';
use SVK::Editor::MapRev;
our $AUTHOR;

my $logger = Pushmi::Config->logger('pushmi.runhook');

sub options {
    ('txnname=s' => 'txnname')
}

sub run {
    my ($self, $repospath) = @_;
    die "repospath required" unless $repospath;
    $self->canonpath($repospath);
    Carp::confess "txnname required" unless $self->{txnname};
    my $repos = SVN::Repos::open($repospath) or die "Can't open repository: $@";
    my $fs = $repos->fs;
    my $txn = $fs->open_txn($self->{txnname}) or die 'no such txn';
    if ($txn->prop('svk:commit')) {
	$txn->change_prop('svk:commit', undef);
	exit 0;
    }

    my $base = $txn->base_revision;
    my $txn_root = $txn->root;

#    my $anchor = $self->_find_txn_anchor($txn_root);
#    warn "doing $self->{txnname}: ".join(',', keys %{ $txn_root->paths_changed });
    my $t = $self->root_svkpath($repos);

    # XXX: if we reentrant, the mirror will be in deadlock.
    $AUTHOR = $txn->prop('svn:author');
    $logger->info("[$repospath] committing from txn $self->{txnname} by $AUTHOR");
    $self->setup_auth;
    # retrieve from memcached as soon as possible, as get_editor might
    # delay because of the server latency of the first response
    _get_password();
    my ($editor, $inspector, %arg) = $t->get_editor(callback => sub {
 },
						    caller => '',
						    message  => $txn->prop('svn:log'));
    my ($mirror) = $t->is_mirrored;

    require Pushmi::Editor::Locker;
    $editor = Pushmi::Editor::Locker->new
	({ _editor => [$editor],
	   on_close_edit => sub {
	       $mirror->lock;
	   } });

    $editor = SVK::Editor::CopyHandler->new(
        _editor => $editor,
        cb_copy => sub {
            my ( $editor, $path, $rev ) = @_;
            return ( $path, $rev ) if $rev == -1;
            return ( $mirror->url . $path,
                     $mirror->find_changeset($rev) );
        }
    );

    my $base_rev = $mirror->find_changeset( $t->revision );
    $editor = SVK::Editor::MapRev->new
	({ _editor => [$editor],
	   cb_resolve_rev => sub { my ($func, $rev) = @_;
				   return $func =~ m/^add/ ? $rev : $base_rev } });

    my $sync_upto;
    my $error;
    ${ $arg{post_handler} } = sub {
	$logger->info("[$repospath] committed as $_[0]");
	$txn->change_prop( 'svk:committed-by' => $mirror->_lock_token );
        $mirror->_backend->_revmap_prop( $txn, $_[0] );
        $sync_upto = $_[0] - 1;
        return 0;
    };

    {
	local $SVN::Error::handler = sub {
	    $_[0]->clear;
	    die $_[0]->message."\n";
	};

	eval {
            SVN::Repos::replay2($txn_root, $t->path, 0, 1, $editor, undef);
            $editor->close_edit;
        };
	if ($error = $@) {
	    $logger->info("[$repospath] Failed to replay txn to mirror: $error");
	    $txn->change_prop('pushmi:dead', '*');
	}
    }

    # we need to switch back to the sync credential
    delete $mirror->_backend->{_cached_ra};
    $self->setup_auth(Pushmi::Command::Mirror->can('pushmi_auth'));
    my ($first, $last);
    $mirror->_backend->_mirror_changesets( $sync_upto,
        sub { $first ||= $_[0]; $last = $_[0] } );
    $logger->info("[$repospath] sync revision $first to $last") if $first;
    if ($error) {
	$mirror->unlock;
	die $error;
    }
    die $error if $error;
    exit 0;
}

my $_cached_password;
sub _get_password {
    return $_cached_password if defined $_cached_password;
    my $memd = Pushmi::Config->memcached;
    my $password = $memd->get($AUTHOR);

    # XXX: can we decline from the prompt handler?
    $password = '' unless defined $password;

    return $_cached_password = $password;
}

sub pushmi_auth {
    my ($cred, $realm, $default_username, $may_save, $pool) = @_;

    $logger->debug("Try to authenticate as $AUTHOR");
    my $password = _get_password;
    $logger->debug("Failed to get password") unless defined $password;
    $cred->username($AUTHOR);
    $cred->password($password);
    $cred->may_save(0);
    return $SVN::_Core::SVN_NO_ERROR;
}

sub _find_txn_anchor {
    my $self     = shift;
    my $txn_root = shift;
    my $pool     = SVN::Pool->new_default;
    my $anchor;
    for (map { Path::Class::Dir->new_foreign( 'Unix', $_ ) }
         keys %{ $txn_root->paths_changed }) {
        if ( defined $anchor ) {
            while ( !$anchor->subsumes($_) ) {
                $anchor = $anchor->parent;
            }
        } else {
            $anchor = $_;
        }
    }

    while ( $txn_root->check_path( $anchor->stringify ) != $SVN::Node::dir ) {
        $anchor = $anchor->parent;
    }

    return $anchor->stringify;
}

1;
