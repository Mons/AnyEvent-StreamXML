#!/usr/bin/env perl

use lib::abs '../lib';
use uni::perl;
use AnyEvent::StreamXML::XMPP::Component;
use AnyEvent::StreamXML::XMPP::JID;
use AnyEvent::StreamXML::XMPP::NS;
use Time::HiRes 'time';

my %c;
	my $c = AnyEvent::StreamXML::XMPP::Component->new(
		jid => 'roster-test.rambler.ru',
		host => 'node01.qa.xmpp.rambler.ru',
		#host => 'localhost', port => 35222,
		password => '345dh_dmg254mq',
		debug_stream => 1,
	);
	$c->feature('register');
	my @roster;
	$c->on(ready => sub {
		warn "connected";
		@roster = map { +{ jid => $_.'@'.$c->{jid} } } qw(test1 test2);
		return;
		$c->{__timer} = AE::timer 10,10, sub {
			my $at = time;
			$c->request({
				iq => {
					-to => "rambler.ru",
					query => { -xmlns => ns( 'ping' ) },
				}
			},sub {
				warn "ping reply: in ".sprintf("%0.4fs", time - $at)."\n";
			});
		};
	});
	$c->on(
		register_get => sub {
			my ($c,$iq) = @_;
			my $jid = $iq->from->bare;
					$iq->reply({ iq => { query => [
						{ instructions => 'Enter your UIN and password' },
						{ username     => '', },
						{ password     => '', },
					] } });
			return;
		},
		register_set => sub {
			my ($c,$iq) = @_;
			my $q = $iq->query;
			$iq->reply;
			$c->presence("subscribe", $iq->from->bare);
			$c{$iq->from->bare}{subscribe}++;
			return;
		},
		register_remove => sub {
			my ($c,$iq) = @_;
			my $jid = $iq->from->bare;
			$iq->reply;
			$c->send({
				iq => {
					-type => 'set',
					-from => $c->{jid},
					-to => $jid,
					-id => $c->nextid,
					query => {
						-xmlns => 'rambler:gateway:roster',
						remove => ''
					},
				}
			});
		},
		presence => sub {
			my ($c,$p) = @_;
			if ($p->to eq $c->{jid}) {
				my $from = $p->from;
				my $bare = $from->bare;
				given ($p->type) {
					# global state
					when ('subscribe') {
						$c->presence("subscribed", $bare);
						return if delete $c{$p->from->bare}{subscribe};
						$c->presence("subscribe", $bare);
					}
					when ('unsubscribe') {
						$c->presence("unsubscribed", $bare);
						$c->presence("unsubscribe", $bare);
					}
					when ('subscribed') {
						# update
						return;
			$c->send({
				iq => {
					-type => 'set',
					-from => $c->{jid},
					-to => $bare,
					-id => $c->nextid,
			query => [
				{ -xmlns => 'rambler:gateway:roster' },
				map {+{ item => [
					{
						-jid => $_->{jid},
						-name => $_->{name} // $_->{jid},
						-subscription => $_->{subscription} // 'both',
					},
					exists $_->{group} ? (
						ref $_->{group} ? (
							map { +{group => $_} } @{$_->{group}},
						) : (
							+{ group => $_->{group}, }
						)
					) : (),
				]}} ( { jid => "test1\@$c->{jid}" }, )
			],
				}
			});
						for (@roster) {
							$c->presence('', $_->{jid} => $bare);
						}
					}
					when ('unsubscribed') {
						$c->presence("unsubscribe", $bare);
						$c->presence("unsubscribed", $bare);
					}
					# per client state
					when ('unavailable') {
						$c->presence("unavailable", $from);
						return;
			$c->send({
				iq => {
					-type => 'set',
					-from => $c->{jid},
					-to => $from, # can't be sent to bare!!
					-id => $c->nextid,
					query => {
						-xmlns => 'rambler:gateway:roster',
						unavailable => ''
					},
				}
			});
					}
					default {
						warn "default presence: ".$p->type;
						$c->presence("", $from);
					}
					
				}
			} else {
				#warn "contact presence to ".$p->to. " my (".$c->{jid}.")";
			}
		},

	);
	$c->connect;

AE::cv->recv;

__END__

sub init {
	my $self = shift;
	
	$self->next::method(@_);
	
	my $t;$t = AE::timer 5,5, sub {
		$t;
			my $at = time;
									$self->request({
										iq => {
											-to => "gw1.jabber.rambler.ru",
											query => { -xmlns => ns( 'ping' ) },
										}
									},sub {
										warn "ping reply: in ".sprintf("%0.4fs", time - $at)."\n@_";
										#delete $c->{timers}{ping_wait};
									});
	};
	
	if (!$self->{unregistrator}){
		$self->feature('gateway');
		$self->feature('register');
		$self->feature('rambler:gateway:register');
	}
	
	return;
}
...

