#!/usr/bin/env perl -w

use uni::perl ':dumper';
use common::sense;
use lib::abs '../lib';
use Test::More tests => 14;
#use Test::NoWarnings;
use AnyEvent::StreamXML::Stanza;
use AnyEvent::StreamXML::XMPP::Iq;

my $s = AnyEvent::StreamXML::Stanza->new(q{<stream:features id="9"><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'><required>7</required></bind><session xmlns='urn:ietf:params:xml:ns:xmpp-session'><required/></session><ver xmlns='urn:xmpp:features:rosterver'><optional/></ver></stream:features>});
ok $s, 'parsed';
is $s->name, 'stream:features', 'node name';
is $s->attr('id'), 9, 'attr';
ok $s->bind, 'bind no ns';
ok $s->bind('urn:ietf:params:xml:ns:xmpp-bind'), 'bind good ns';
ok !$s->bind(11), 'bind bad ns';
ok $s->bind->required, 'bind required';
ok !$s->bind->optional, 'bind not optional';

ok $s->session->required, 'session required';
ok !$s->session->optional, 'session not optional';

ok !$s->ver->required, 'ver not required';
ok $s->ver->optional, 'ver optional';

is $s->bind->required->value, 7, 'bind required value';

$s = AnyEvent::StreamXML::Stanza->new(q{<iq type="get" from="from@domain.com/res" to="to@domain.com"><bind xmlns="xmpp-bind" /></iq>});

is $s->children->[0]->attr('xmlns'), 'xmpp-bind';
is $s->child(0)->attr('xmlns'), 'xmpp-bind';
ok eval{ $s->child(1)->attr('xmlns'); 1 }, 'child(x) not dies';

=for rem
warn dumper [ $s->children ];
warn dumper [ scalar $s->children ];
warn dumper [ $s->children->[0] ];
warn dumper [ $s->children->[0]->attr('xmlns') ];
warn dumper [ $s->child(0)->attr('xmlns') ];
warn dumper [ $s->child(1)->attr('xmlns') ];
=cut

my $iq = AnyEvent::StreamXML::XMPP::Iq->new($s);
is $iq->from->bare, 'from@domain.com', 'iq.from.bare';
is $iq->to->user, 'to', 'iq.to.user';
is $iq->subtype, 'xmpp-bind', 'iq.subtype';
$iq->child({error => { -xmlns => 'error', -type => 'someerror', 'error-name' => '' }});
ok $iq->error->child('error-name'), 'error created';
#say $iq;
#warn dumper $iq;
#warn dumper $iq->error->child('error-name');

