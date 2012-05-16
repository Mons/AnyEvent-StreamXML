#!/usr/bin/env perl -w

use common::sense;
use lib::abs '../lib';
use Test::More tests => 2;
#use Test::NoWarnings;
use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent::StreamXML;

my $port;
my $s = tcp_server 0,4444, sub{
	warn "accept @_";
	my $fh = shift;
	my $h;$h = AnyEvent::Handle->new(
		fh => $fh,
		on_eof => sub {
			undef $h;
		},
	);
	$h->push_write("<stream:stream>");
	$h->push_write("<iq></iq>");
	return;
}, sub {
	$port = $_[2];
	#warn "prepare @_";
	return;
};

my $sx = AnyEvent::StreamXML->new( debug => 1, host => 0, port => $port, );
$sx->on('stanza' => sub {
	warn "stanza @_";
});

$sx->connect;

AE::cv->recv;

__END__

my $sx = AnyEvent::StreamXML->new( debug => 1 );
$sx->_make_parser;
$sx->{parser}->parse_more( "<stream:stream><iq></iq>" );