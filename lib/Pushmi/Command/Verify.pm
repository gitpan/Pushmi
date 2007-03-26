package Pushmi::Command::Verify;
use base 'Pushmi::Command::Mirror';
use strict;
use warnings;

use SVK::I18N;

my $logger = Pushmi::Config->logger('pushmi.verify');

sub options {
    ( 'revision=i' => 'revision' )
}

sub run {
    my ($self, $repospath) = @_;
    $self->canonpath($repospath);
    my $repos = SVN::Repos::open($repospath) or die "Can't open repository: $@";

    my $t = $self->root_svkpath($repos);

    $t->repos->fs->revision_prop(0, 'pushmi:auto-verify')
	or return;

    my $verify_mirror = Pushmi::Config->config->{verify_mirror} || 'verify-mirror';
    my $output = `$verify_mirror $repospath / $self->{revision}`;

    unless ($?) {
	$logger->debug("[$repospath] revision $self->{revision} verified");
	return;
    }

    $logger->logdie("[$repospath] can't verify: $!") if $? == -1;

    $t->repos->fs->change_rev_prop(0, 'pushmi:inconsistent', $self->{revision});

    $logger->logdie("[$repospath] can't verify: $output");
}

1;
