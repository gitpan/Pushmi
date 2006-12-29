package Pushmi::Apache::AuthCommit;

use strict;
use warnings;

use Apache2::Access ();
use Apache2::RequestUtil ();
use Apache2::RequestRec ();
use Apache2::Const -compile => qw(FORBIDDEN OK HTTP_UNAUTHORIZED DECLINED);

my $memd;

sub handler {
    my $r      = shift;
    my $method = $r->method;

    unless ($memd) {
        my $config = $r->dir_config('PushmiConfig');
        $ENV{PUSHMI_CONFIG} = $config;
        require Pushmi::Config;

        $memd = Pushmi::Config->memcached;
    }

    my ( $status, $password ) = $r->get_basic_auth_pw;
    return $status unless $status == Apache2::Const::OK;

    if ( $method eq 'MKACTIVITY' ) {    # only tryauth on mkactivity
	#warn "===> trying auth for $method";
        my $pushmi    = $r->dir_config('Pushmi');
        my $repospath = $r->dir_config('SVNPath');
        my $config    = $r->dir_config('PushmiConfig');

        $ENV{PUSHMI_CONFIG} = $config;

        # XXX: use stdin or setproctitle
        # XXX: log $!
        system(   "$pushmi mirror $repospath --tryauth '"
                . $r->user
                . "' '$password'" );

	#warn "==> pushmi try-auth works? $?";
	$memd->set( $r->user, $password, 30 ) unless $?;
	return Apache2::Const::OK unless $?;

	#warn "===> not authorised";
	$r->note_basic_auth_failure;
	return Apache2::Const::HTTP_UNAUTHORIZED;
    }

    # refresh
    $memd->set( $r->user, $password, 30 );
    # assuming user is already authenticated after mkactivity
    return Apache2::Const::OK;
}

1;
