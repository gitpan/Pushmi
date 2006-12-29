package Pushmi::Command::Unlock;
use base 'Pushmi::Command::Mirror';
use SVK::I18N;

sub options {
    ( 'revision=i' => 'revision' )
}

sub run {
    my ($self, $repospath) = @_;
    $self->canonpath($repospath);
    my $repos = SVN::Repos::open($repospath) or die "Can't open repository: $@";

    my $t = $self->root_svkpath($repos);

    $self->setup_auth;
    my ($mirror) = $t->is_mirrored;

    my $token   = $mirror->_lock_token;
    if ($self->{revision}) {
	my $expected = $t->repos->fs->revision_prop($self->{revision}, 'svk:committed-by') or return;
	return unless $expected eq $token;
    }
    if (my $content = $t->repos->fs->revision_prop( 0, $token )) {
	print loc("Removing lock %1 on %2.\n", $content, $repospath);
	$mirror->unlock('force');
    }

    return;
}

1;
