package Pushmi::Command::Sync;
use base 'Pushmi::Command::Mirror';
use SVK::I18N;

my $logger = Pushmi::Config->logger('pushmi.sync');

sub options {
    ('nowait' => 'nowait');
}

sub run {
    my ($self, $repospath) = @_;
    $self->canonpath($repospath);
    my $repos = SVN::Repos::open($repospath) or die "Can't open repository: $@";

    my $t = $self->root_svkpath($repos);

    $self->setup_auth;
    my ($mirror) = $t->is_mirrored;

    if ($self->{nowait}) {
	my $token   = $mirror->_lock_token;
	if (my $content = $t->repos->fs->revision_prop( 0, $token )) {
	    print loc("Mirror is locked by %1, skipping.\n", $content);
	    return;
	}
    }

    my ($first, $last);
    eval {
    $mirror->mirror_changesets(undef,
        sub { $first ||= $_[0]; $last = $_[0] });
    };
    $logger->error("[$repospath] sync failed: $@") if $@;
    $logger->info("[$repospath] sync revision $first to $last") if $first;

    return;
}

1;
