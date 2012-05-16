#!/usr/bin/env perl -w

use common::sense;
use lib::abs '../lib';
use Test::More tests => 14;
use Test::NoWarnings;
use AnyEvent::StreamXML::Stanza;

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

