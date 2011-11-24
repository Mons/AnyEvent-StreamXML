package AnyEvent::StreamXML::XMPP::Message;

use parent 'AnyEvent::StreamXML::XMPP::Stanza';

sub body { $_[0][2]{body} ||= do {  my $b = ( $_[0][0]->getElementsByTagName('body') )[0]; $b ? $b->textContent : undef }  }

1;
