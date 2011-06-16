package AmyEvent::StreamXML::XMPP::Error;

use common::sense;
use Carp;

sub import {
	my $me = shift;
	my $caller = caller;
	no strict 'refs';
	for (@_ ? @_ : qw(error)) {
		croak "`$_' not exported by $me" unless defined &$_;
		*{$caller . '::' . $_} = \&$_;
	}
}

our %ERR = (
	'bad-request'             => [modify => 400],
	'conflict'                => [cancel => 409],
	'feature-not-implemented' => [cancel => 501],
	'forbidden'               => [auth   => 403],
	'gone'                    => [modify => 302],
	'internal-server-error'   => [wait   => 500],
	'item-not-found'          => [cancel => 404],
	'jid-malformed'           => [modify => 400],
	'not-acceptable'          => [modify => 406],
	'not-allowed'             => [cancel => 405],
	'not-authorized'          => [auth   => 401],
	'payment-required'        => [auth   => 402],
	'recipient-unavailable'   => [wait   => 404],
	'redirect'                => [modify => 302],
	'registration-required'   => [auth   => 407],
	'remote-server-not-found' => [cancel => 404],
	'remote-server-timeout'   => [wait   => 504],
	'resource-constraint'     => [wait   => 500],
	'service-unavailable'     => [cancel => 503],
	'subscription-required'   => [auth   => 407],
	'undefined-condition'     => [cancel => 500],
	'unexpected-request'      => [wait   => 400],
);
exists $ERR{'internal-server-error'} or die "Need 'internal-server-error'";

sub error {
	
}